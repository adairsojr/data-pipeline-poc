"""Gera as fontes de dados da PoC — a partir da base pública do INEP.

Este script NÃO faz parte do pipeline. Ele existe para que as fontes em
`data/raw/` sejam reprodutíveis: baixa as **Taxas de Rendimento Escolar
por município (2023)** do INEP e as divide em DUAS fontes, em DOIS formatos:

    - data/raw/taxas_municipios.csv  (CSV)  -> a futura tabela fato
    - data/raw/ufs.json              (JSON) -> cadastro de UF -> região

CENÁRIO: o INEP (Instituto Nacional de Estudos e Pesquisas Educacionais)
divulga, a partir do Censo Escolar, as taxas de rendimento de cada
município: **aprovação, reprovação e abandono**. O ABANDONO é a evasão
escolar — o que este projeto quer analisar.

FONTE: INEP — Indicadores Educacionais / Taxas de Rendimento Escolar
(https://www.gov.br/inep/.../taxas-de-rendimento-escolar). Arquivo:
tx_rend_municipios_2023.zip (contém um .xlsx com cabeçalho multi-linha).
É dado público e não-pessoal (agregado por município). Baixamos o ZIP,
extraímos o xlsx e gravamos um SNAPSHOT em CSV/JSON em data/raw/ para o
pipeline reconstruir sempre igual — inclusive offline (cache).

⚠ A "taxa de evasão combinada" que o projeto usa NÃO existe no arquivo:
o INEP entrega abandono do Fundamental e do Médio SEPARADOS. Combiná-las
é decisão de transformação (Gold). Ver DECISOES.md.

Os defeitos abaixo são INTENCIONAIS — a base real já traz alguns (nulos,
"--"), e nós plantamos outros de propósito para justificar a Silver.
Lista completa em docs/anomalias-das-fontes.md.

Execução:  python scripts/gerar_fontes.py
           python scripts/gerar_fontes.py --offline   (usa o cache local)
"""

import argparse
import csv
import io
import json
import random
import sys
import urllib.request
import zipfile
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
DESTINO = RAIZ / "data" / "raw"
CACHE = DESTINO / "_inep_cache.csv"

SEMENTE = 20260914
random.seed(SEMENTE)

# --------------------------------------------------------------------
# Download do ZIP do INEP
# --------------------------------------------------------------------
URL = (
    "https://download.inep.gov.br/informacoes_estatisticas/"
    "indicadores_educacionais/2023/tx_rend_municipios_2023.zip"
)

# Códigos das colunas do xlsx do INEP (linha de cabeçalho "machine
# readable", que fica na 9ª linha da planilha — skiprows=8).
#   1_CAT_* = Aprovação | 2_CAT_* = Reprovação | 3_CAT_* = Abandono
COLS_INEP = {
    "NU_ANO_CENSO": "ano",
    "NO_REGIAO": "regiao",
    "SG_UF": "uf",
    "CO_MUNICIPIO": "codigo_municipio",
    "NO_MUNICIPIO": "nome_municipio",
    "NO_CATEGORIA": "localizacao",      # Total / Urbana / Rural
    "NO_DEPENDENCIA": "dependencia",    # Total / Federal / Estadual / ...
    "1_CAT_FUN": "taxa_aprovacao_fund",
    "2_CAT_FUN": "taxa_reprovacao_fund",
    "3_CAT_FUN": "taxa_abandono_fund",
    "3_CAT_MED": "taxa_abandono_med",
}

# Nome das regiões por extenso (para a dimensão UF).
REGIOES = {"Norte", "Nordeste", "Sudeste", "Sul", "Centro-Oeste"}


def baixar_inep(offline: bool) -> list[dict]:
    """Baixa o ZIP do INEP e devolve as linhas já com nomes de coluna
    amigáveis. Usa cache CSV local se --offline."""
    if offline and CACHE.exists():
        print(f"[offline] usando cache: {CACHE.name}")
        with open(CACHE, encoding="utf-8") as f:
            return list(csv.DictReader(f))

    print("baixando tx_rend_municipios_2023.zip do INEP (~34 MB) ...")
    try:
        req = urllib.request.Request(URL, headers={"User-Agent": "poc-dados/1.0"})
        with urllib.request.urlopen(req, timeout=180) as resp:
            conteudo = resp.read()
    except Exception as exc:  # noqa: BLE001
        if CACHE.exists():
            print(f"[aviso] download falhou ({exc}); usando cache local")
            with open(CACHE, encoding="utf-8") as f:
                return list(csv.DictReader(f))
        print(f"[erro] download falhou e não há cache: {exc}", file=sys.stderr)
        sys.exit(1)

    import pandas as pd  # só aqui: ler xlsx exige pandas+openpyxl

    with zipfile.ZipFile(io.BytesIO(conteudo)) as z:
        nome_xlsx = next(n for n in z.namelist() if n.endswith(".xlsx"))
        with z.open(nome_xlsx) as fx:
            # skiprows=8 pula o cabeçalho multi-linha; a 9ª linha traz os
            # códigos de coluna (NU_ANO_CENSO, SG_UF, 3_CAT_FUN, ...).
            df = pd.read_excel(fx, skiprows=8, dtype=str, engine="openpyxl")

    df = df[list(COLS_INEP.keys())].rename(columns=COLS_INEP)
    registros = df.to_dict(orient="records")

    # cache em CSV (leve, versionável e legível offline)
    with open(CACHE, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(COLS_INEP.values()))
        w.writeheader()
        w.writerows(registros)
    print(f"  ok: {len(registros)} linhas (cache salvo em {CACHE.name})")
    return registros


def montar_fontes(brutos: list[dict]) -> tuple[list[dict], list[dict]]:
    """Devolve (taxas, ufs) já com os defeitos plantados."""

    # ---------- FATO: taxas por município (CSV) ----------
    # Ficamos com o recorte mais analítico e enxuto: Localização = Total e
    # Dependência = Total (uma linha por município). As outras combinações
    # existem na base, mas manter todas explodiria o volume sem agregar à
    # PoC. É uma decisão de RECORTE da fonte, documentada no PROCESSO.md.
    taxas = []
    for r in brutos:
        if r.get("localizacao") != "Total" or r.get("dependencia") != "Total":
            continue
        taxas.append(
            {
                "ano": (r.get("ano") or "").strip(),
                "codigo_municipio": (r.get("codigo_municipio") or "").strip(),
                "nome_municipio": (r.get("nome_municipio") or "").strip(),
                "uf": (r.get("uf") or "").strip(),
                "taxa_aprovacao_fund": (r.get("taxa_aprovacao_fund") or "").strip(),
                "taxa_reprovacao_fund": (r.get("taxa_reprovacao_fund") or "").strip(),
                "taxa_abandono_fund": (r.get("taxa_abandono_fund") or "").strip(),
                "taxa_abandono_med": (r.get("taxa_abandono_med") or "").strip(),
            }
        )

    # ---------- DIMENSÃO: UF -> região (JSON) ----------
    mapa = {}
    for r in brutos:
        uf = (r.get("uf") or "").strip()
        reg = (r.get("regiao") or "").strip()
        if uf and reg in REGIOES and uf not in mapa:
            mapa[uf] = reg
    ufs = [{"uf": u, "regiao": reg} for u, reg in sorted(mapa.items())]

    # =================================================================
    # DEFEITOS PLANTADOS  (documentados em docs/anomalias-das-fontes.md)
    # =================================================================
    # As taxas do INEP usam PONTO decimal ("93.1"). Simulamos um export
    # que trocou parte delas por VÍRGULA (padrão brasileiro), além dos
    # outros problemas clássicos.

    # DEFEITO 1 — taxa com vírgula decimal em vez de ponto (2 linhas).
    for i in (10, 500):
        if i < len(taxas):
            v = taxas[i]["taxa_abandono_fund"]
            taxas[i]["taxa_abandono_fund"] = v.replace(".", ",")

    # DEFEITO 2 — UF com grafia inconsistente (minúscula, espaços) (3 linhas).
    for i, mut in ((30, str.lower), (60, lambda s: "  " + s), (90, lambda s: s + " ")):
        if i < len(taxas):
            taxas[i]["uf"] = mut(taxas[i]["uf"])

    # DEFEITO 3 — UF inexistente no cadastro (id órfão) (1 linha).
    if len(taxas) > 120:
        taxas[120]["uf"] = "ZZ"

    # DEFEITO 4 — abandono implausível: taxa > 100 (1 linha).
    if len(taxas) > 200:
        taxas[200]["taxa_abandono_fund"] = "150.0"

    # DEFEITO 5 — código de município vazio (registro sem chave) (1 linha).
    if len(taxas) > 300:
        vazio = dict(taxas[300])
        vazio["codigo_municipio"] = ""
        taxas.insert(305, vazio)

    # DEFEITO 6 — duas duplicatas INTEGRAIS (export concatenado 2x).
    if len(taxas) > 50:
        taxas.extend([dict(taxas[15]), dict(taxas[42])])

    # DEFEITO 7 — UF duplicada no JSON, com região em CAIXA ALTA
    # (mesma UF, grafia diferente). Num banco a PK impediria; no JSON não.
    if ufs:
        dup = dict(ufs[0])
        dup["regiao"] = dup["regiao"].upper()
        ufs.append(dup)

    return taxas, ufs


def main() -> None:
    parser = argparse.ArgumentParser(description="Gera as fontes INEP da PoC.")
    parser.add_argument(
        "--offline", action="store_true", help="usa o cache local em vez do INEP"
    )
    args = parser.parse_args()

    DESTINO.mkdir(parents=True, exist_ok=True)
    brutos = baixar_inep(args.offline)
    taxas, ufs = montar_fontes(brutos)

    campos = list(taxas[0].keys())
    with open(DESTINO / "taxas_municipios.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=campos, lineterminator="\n")
        w.writeheader()
        w.writerows(taxas)

    with open(DESTINO / "ufs.json", "w", encoding="utf-8") as f:
        json.dump(ufs, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"taxas_municipios.csv  {len(taxas):>6} linhas  (CSV)")
    print(f"ufs.json              {len(ufs):>6} registros (JSON)")


if __name__ == "__main__":
    main()
