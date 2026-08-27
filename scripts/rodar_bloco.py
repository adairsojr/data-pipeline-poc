"""Executa um bloco numerado de um dos arquivos de consultas/.

Existe para a aula: permite rodar UM bloco por vez, sem instalar o CLI
do DuckDB e sem precisar copiar/colar SQL no terminal.

Uso, da raiz do projeto:
    python scripts/rodar_bloco.py                 # lista os blocos (brutos)
    python scripts/rodar_bloco.py 1               # roda o bloco 1 (brutos)
    python scripts/rodar_bloco.py brutos 2        # idem, explicito
    python scripts/rodar_bloco.py oltp 3          # roda no OLTP simulado

Dois arquivos, dois mundos:
    brutos -> consultas/dados_brutos.sql   (le data/raw/ direto, sem banco)
    oltp   -> consultas/oltp_quatro_analistas.sql
              (precisa de python scripts/criar_oltp_simulado.py antes)
    fontes -> consultas/mesma_pergunta_nas_fontes.sql
              (a mesma pergunta da Gold, lida direto do CSV/JSON)
"""

import re
import sys
from pathlib import Path

import duckdb

RAIZ = Path(__file__).resolve().parents[1]
OLTP = str(RAIZ / "data" / "chamados_oltp.duckdb")

ARQUIVOS = {
    "brutos": RAIZ / "consultas" / "dados_brutos.sql",
    "oltp": RAIZ / "consultas" / "oltp_quatro_analistas.sql",
    "fontes": RAIZ / "consultas" / "mesma_pergunta_nas_fontes.sql",
}
PADRAO = "brutos"


def blocos(arquivo):
    """Divide o arquivo pelos cabecalhos '-- N) TITULO'."""
    partes = re.split(r"^-- (\d+)\) (.+)$", arquivo.read_text(encoding="utf-8"),
                      flags=re.MULTILINE)
    return [
        (int(partes[i]), partes[i + 1].strip(), partes[i + 2])
        for i in range(1, len(partes), 3)
    ]


def main():
    args = sys.argv[1:]
    fonte = PADRAO
    if args and args[0] in ARQUIVOS:
        fonte = args.pop(0)

    arquivo = ARQUIVOS[fonte]
    if fonte == "oltp" and not Path(OLTP).exists():
        sys.exit(f"OLTP nao encontrado em {OLTP}\n"
                 f"Rode antes:  python scripts/criar_oltp_simulado.py")

    lista = blocos(arquivo)
    if not args:
        print(f"Blocos de {arquivo.name}:\n")
        for n, titulo, _ in lista:
            print(f"  {n}) {titulo}")
        outra = "oltp" if fonte == "brutos" else "brutos"
        print(f"\nUso: python scripts/rodar_bloco.py [{fonte}|{outra}] <numero>")
        return

    alvo = int(args[0])
    achado = [b for b in lista if b[0] == alvo]
    if not achado:
        sys.exit(f"Bloco {alvo} nao existe em {arquivo.name}.")
    _, titulo, corpo = achado[0]

    # tira os comentarios ANTES de separar por ';' -- assim um ';' dentro
    # de um comentario nao parte a consulta ao meio, e as instrucoes que
    # estao comentadas de proposito (para rodar a mao) sao ignoradas.
    limpo = []
    for linha in corpo.splitlines():
        pos = linha.find("--")
        if pos >= 0 and linha[:pos].count("'") % 2 == 0:
            linha = linha[:pos]
        limpo.append(linha)
    comandos = [c for c in "\n".join(limpo).split(";") if c.strip()]

    # brutos le arquivo direto: nao precisa de banco nenhum
    con = duckdb.connect(OLTP, read_only=True) if fonte == "oltp" else duckdb.connect()
    print(f"\n=== [{fonte}] {alvo}) {titulo} ===\n")
    for cmd in comandos:
        r = con.sql(cmd)
        if r is not None:
            print(r)


if __name__ == "__main__":
    import os
    os.chdir(RAIZ)
    main()
