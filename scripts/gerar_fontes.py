"""Gera as fontes de dados da PoC — com os defeitos plantados.

Este script NÃO faz parte do pipeline. Ele existe para que as fontes em
`data/raw/` sejam reprodutíveis: mesma semente, mesmos arquivos.

CENÁRIO: a Central de Serviços (service desk) de uma instituição com
unidades em oito cidades. O sistema de chamados é o OLTP; o que temos
aqui é o "export" que a origem nos entregou.

Os 11 defeitos são INTENCIONAIS — são eles que justificam a camada
Silver. A lista completa está em docs/ e no guia da professora.

Execução:  python scripts/gerar_fontes.py
"""

import csv
import json
import random
from datetime import date, timedelta
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
DESTINO = RAIZ / "data" / "raw"

SEMENTE = 20260818
random.seed(SEMENTE)

# --------------------------------------------------------------------
# Cadastros
# --------------------------------------------------------------------

# ⚠ DEFEITO 7: quatro grafias inconsistentes (minúscula, maiúscula e
# espaços em volta). Tratado em stg_unidades.sql.
UNIDADES = [
    (1, "Campo Grande", "MS"),
    (2, "dourados", "MS"),           # minúscula
    (3, "TRÊS LAGOAS", "MS"),        # maiúscula
    (4, "Corumbá", "MS"),
    (5, "Ponta Porã", "MS"),
    (6, "  Aquidauana", "MS"),       # espaços à esquerda
    (7, "Coxim", "MS"),
    (8, "Naviraí ", "MS"),           # espaço à direita
]

CATEGORIAS = [
    (1, "Acesso e Senha"),
    (2, "Rede e Internet"),
    (3, "Equipamento"),
    (4, "Sistema Acadêmico"),
    (5, "E-mail"),
    (6, "Impressão"),
]

# ⚠ DEFEITO 8: o mesmo categoria_id com duas grafias. Em um banco
# relacional a chave primária impediria; num CSV, não há chave alguma.
CATEGORIA_DUPLICADA = (2, "REDE E INTERNET")

TIPOS_INTERACAO = [
    "Abertura",
    "Triagem",
    "Atribuição",
    "Contato com Usuário",
    "Diagnóstico",
    "Solução Aplicada",
    "Encerramento",
]

# Tempo típico de atendimento (em dias) por unidade e por categoria.
# Os valores fazem as unidades terem desempenhos diferentes — é o que
# torna a análise final interessante.
BASE_UNIDADE = {1: 6.0, 2: 9.0, 3: 12.0, 4: 17.0, 5: 14.0, 6: 19.0, 7: 11.4, 8: 11.6}
FATOR_CATEGORIA = {1: 0.35, 2: 1.15, 3: 1.85, 4: 1.35, 5: 0.55, 6: 0.95}

INICIO = date(2023, 1, 2)
FIM = date(2026, 7, 1)

TOTAL_CHAMADOS = 119   # + 2 duplicatas + 1 sem id = 122 linhas no arquivo
EM_ANDAMENTO = 23


def _data_aleatoria(inicio: date, fim: date) -> date:
    return inicio + timedelta(days=random.randint(0, (fim - inicio).days))


def _duracao(unidade_id: int, categoria_id: int) -> int:
    media = BASE_UNIDADE[unidade_id] * FATOR_CATEGORIA[categoria_id]
    # distribuição assimétrica: muitos chamados rápidos, alguns bem lentos
    valor = random.gammavariate(2.0, media / 2.0)
    return max(0, min(120, round(valor)))


def gerar_chamados() -> list[dict]:
    chamados = []
    for i in range(TOTAL_CHAMADOS):
        chamado_id = 500001 + i
        unidade_id = random.choice(list(BASE_UNIDADE))
        categoria_id = random.choice(list(FATOR_CATEGORIA))
        equipe_id = random.randint(1, 5)      # se repete entre unidades
        abertura = _data_aleatoria(INICIO, FIM)

        aberto = i < EM_ANDAMENTO
        if aberto:
            fechamento = None
            situacao = "Em andamento"
        else:
            fechamento = abertura + timedelta(days=_duracao(unidade_id, categoria_id))
            situacao = "Resolvido"

        chamados.append(
            {
                "chamado_id": str(chamado_id),
                "categoria_id": str(categoria_id),
                "unidade_id": str(unidade_id),
                "equipe_id": str(equipe_id),
                "data_abertura": abertura.isoformat(),
                "data_fechamento": fechamento.isoformat() if fechamento else "",
                "situacao": situacao,
            }
        )

    random.shuffle(chamados)

    # =================================================================
    # DEFEITOS PLANTADOS
    # =================================================================
    resolvidos = [c for c in chamados if c["situacao"] == "Resolvido"]

    # Os índices são espalhados de propósito: os defeitos não podem ficar
    # todos nas primeiras linhas, senão saltam aos olhos antes da hora.

    # DEFEITO 1 — data_abertura em DD/MM/AAAA (2 linhas)
    for i in (12, 67):
        c = resolvidos[i]
        a = date.fromisoformat(c["data_abertura"])
        c["data_abertura"] = a.strftime("%d/%m/%Y")

    # DEFEITO 2 — data_fechamento em DD/MM/AAAA (1 linha)
    c = resolvidos[41]
    f = date.fromisoformat(c["data_fechamento"])
    c["data_fechamento"] = f.strftime("%d/%m/%Y")

    # DEFEITO 5 — unidade_id inexistente no cadastro (1 linha)
    resolvidos[25]["unidade_id"] = "99"

    # DEFEITO 6 — fechamento anterior à abertura (1 linha)
    c = resolvidos[80]
    a = date.fromisoformat(c["data_abertura"])
    c["data_fechamento"] = (a - timedelta(days=25)).isoformat()

    # DEFEITO 3 — chamado_id vazio (1 linha)
    vazio = dict(resolvidos[54])
    vazio["chamado_id"] = ""
    chamados.insert(73, vazio)

    # DEFEITO 4 — duas duplicatas INTEGRAIS, no fim do arquivo
    # (como se o export tivesse sido concatenado duas vezes)
    duplicadas = [dict(resolvidos[10]), dict(resolvidos[33])]
    chamados.extend(duplicadas)

    return chamados


def gerar_interacoes(chamados: list[dict]) -> list[dict]:
    validos = [c for c in chamados if c["chamado_id"]]
    interacoes = []

    for c in validos[:119]:
        # a data de abertura pode estar em DD/MM/AAAA — normaliza aqui,
        # porque este é o gerador, não o pipeline
        bruto = c["data_abertura"]
        abertura = (
            date.fromisoformat(bruto)
            if "-" in bruto
            else date(int(bruto[6:]), int(bruto[3:5]), int(bruto[0:2]))
        )
        # Quantas interações este chamado teve?
        # Proporcional à duração: chamado que demora mais acumula mais
        # eventos (triagem, contato, diagnóstico...). Isso é realista —
        # e é justamente o que torna o FAN-OUT perigoso: juntar este
        # arquivo com a fato dá mais peso aos chamados demorados,
        # empurrando a média para cima.
        if c["data_fechamento"]:
            bruto_f = c["data_fechamento"]
            fecha = (
                date.fromisoformat(bruto_f)
                if "-" in bruto_f
                else date(int(bruto_f[6:]), int(bruto_f[3:5]), int(bruto_f[0:2]))
            )
            duracao = max(0, (fecha - abertura).days)
        else:
            duracao = 3

        quantos = max(1, min(7, round(1.8 + duracao / 4 + random.uniform(-1, 1))))

        for tipo in random.sample(TIPOS_INTERACAO, quantos):
            quando = abertura + timedelta(days=random.randint(0, 60))
            interacoes.append(
                {
                    "chamado_id": int(c["chamado_id"]),
                    "tipo_interacao": tipo,
                    "data_interacao": quando.isoformat(),
                }
            )

    random.shuffle(interacoes)
    interacoes = interacoes[:402]

    # DEFEITO 9 — cinco eventos duplicados
    interacoes.extend([dict(x) for x in interacoes[:5]])

    # DEFEITO 10 — duas datas em DD/MM/AAAA
    for m in interacoes[10:12]:
        d = date.fromisoformat(m["data_interacao"])
        m["data_interacao"] = d.strftime("%d/%m/%Y")

    # DEFEITO 11 — um chamado_id órfão (não existe em chamados.csv)
    interacoes.append(
        {
            "chamado_id": 9999999,
            "tipo_interacao": "Triagem",
            "data_interacao": "2025-06-11",
        }
    )

    return interacoes


def main() -> None:
    DESTINO.mkdir(parents=True, exist_ok=True)

    chamados = gerar_chamados()
    campos = list(chamados[0].keys())
    with open(DESTINO / "chamados.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=campos, lineterminator="\n")
        w.writeheader()
        w.writerows(chamados)

    with open(DESTINO / "unidades.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["unidade_id", "nome_unidade", "uf"])
        w.writerows(UNIDADES)

    with open(DESTINO / "categorias.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["categoria_id", "nome_categoria"])
        linhas = [list(c) for c in CATEGORIAS]
        linhas.insert(5, list(CATEGORIA_DUPLICADA))
        w.writerows(linhas)

    interacoes = gerar_interacoes(chamados)
    with open(DESTINO / "interacoes.json", "w", encoding="utf-8") as f:
        json.dump(interacoes, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"chamados.csv     {len(chamados):>4} linhas")
    print(f"unidades.csv     {len(UNIDADES):>4} linhas")
    print(f"categorias.csv   {len(CATEGORIAS) + 1:>4} linhas")
    print(f"interacoes.json  {len(interacoes):>4} registros")


if __name__ == "__main__":
    main()
