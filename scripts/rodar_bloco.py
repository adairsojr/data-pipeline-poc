"""Executa um bloco numerado de consultas/analise.sql.

Existe para a aula: permite rodar UM bloco por vez, sem instalar o CLI
do DuckDB e sem precisar copiar/colar SQL no terminal.

Uso, da raiz do projeto:
    python scripts/rodar_bloco.py            # lista os blocos disponíveis
    python scripts/rodar_bloco.py 1          # roda a Pergunta 1
    python scripts/rodar_bloco.py analise 2  # idem, explícito
"""

import re
import sys
from pathlib import Path

import duckdb

RAIZ = Path(__file__).resolve().parents[1]

ARQUIVOS = {
    "analise": RAIZ / "consultas" / "analise.sql",
}
PADRAO = "analise"


def blocos(arquivo):
    """Divide o arquivo pelos cabeçalhos '-- N) TITULO'."""
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
    lista = blocos(arquivo)
    if not args:
        print(f"Blocos de {arquivo.name}:\n")
        for n, titulo, _ in lista:
            print(f"  {n}) {titulo}")
        print(f"\nUso: python scripts/rodar_bloco.py <numero>")
        return

    alvo = int(args[0])
    achado = [b for b in lista if b[0] == alvo]
    if not achado:
        sys.exit(f"Bloco {alvo} não existe em {arquivo.name}.")
    _, titulo, corpo = achado[0]

    # tira os comentários ANTES de separar por ';' -- assim um ';' dentro
    # de um comentário não parte a consulta ao meio, e as instruções que
    # estão comentadas de propósito são ignoradas.
    limpo = []
    for linha in corpo.splitlines():
        pos = linha.find("--")
        if pos >= 0 and linha[:pos].count("'") % 2 == 0:
            linha = linha[:pos]
        limpo.append(linha)
    comandos = [c for c in "\n".join(limpo).split(";") if c.strip()]

    con = duckdb.connect()  # consumo lê os Parquet da Gold direto do disco
    print(f"\n=== [{fonte}] {alvo}) {titulo} ===\n")
    for cmd in comandos:
        r = con.sql(cmd)
        if r is not None:
            print(r)


if __name__ == "__main__":
    import os

    os.chdir(RAIZ)
    main()
