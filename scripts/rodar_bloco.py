"""Executa um bloco numerado de consultas/oltp_quatro_analistas.sql.

Existe para a aula: permite rodar UM bloco por vez, sem instalar o CLI
do DuckDB e sem precisar copiar/colar SQL no terminal.

Uso, da raiz do projeto:
    python scripts/rodar_bloco.py          # lista os blocos
    python scripts/rodar_bloco.py 3        # roda o bloco 3
"""

import re
import sys
from pathlib import Path

import duckdb

RAIZ = Path(__file__).resolve().parents[1]
ARQUIVO = RAIZ / "consultas" / "oltp_quatro_analistas.sql"
OLTP = str(RAIZ / "data" / "chamados_oltp.duckdb")


def blocos():
    """Divide o arquivo pelos cabeçalhos '-- N) TÍTULO'."""
    texto = ARQUIVO.read_text(encoding="utf-8")
    partes = re.split(r"^-- (\d+)\) (.+)$", texto, flags=re.MULTILINE)
    # partes = [preâmbulo, num, titulo, corpo, num, titulo, corpo, ...]
    return [
        (int(partes[i]), partes[i + 1].strip(), partes[i + 2])
        for i in range(1, len(partes), 3)
    ]


def main():
    if not Path(OLTP).exists():
        sys.exit(f"OLTP não encontrado em {OLTP}\n"
                 f"Rode antes:  python scripts/criar_oltp_simulado.py")

    lista = blocos()
    if len(sys.argv) < 2:
        print("Blocos disponíveis:\n")
        for n, titulo, _ in lista:
            print(f"  {n}) {titulo}")
        print(f"\nUso: python {Path(__file__).name} <número>")
        return

    alvo = int(sys.argv[1])
    achado = [b for b in lista if b[0] == alvo]
    if not achado:
        sys.exit(f"Bloco {alvo} não existe.")
    _, titulo, corpo = achado[0]

    # cada instrução do bloco, sem as linhas de comentário soltas
    comandos = [c for c in corpo.split(";") if c.strip() and
                not all(l.strip().startswith("--") or not l.strip()
                        for l in c.splitlines())]

    con = duckdb.connect(OLTP, read_only=True)
    print(f"\n=== {alvo}) {titulo} ===\n")
    for cmd in comandos:
        print(con.sql(cmd))


if __name__ == "__main__":
    # os Parquet são referenciados por caminho relativo à raiz
    import os
    os.chdir(RAIZ)
    main()
