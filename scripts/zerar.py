"""Zera o projeto para a aula: apaga tudo o que o pipeline GERA.

O que apaga:
    data/bronze/*.parquet     escrito pela ingestao (Python)
    data/silver/*.parquet     escrito pelo dbt
    data/gold/*.parquet       escrito pelo dbt
    data/analytics.duckdb     o catalogo do DuckDB
    dbt/target/               manifesto, SQL compilado, run_results

O que NAO apaga, nunca:
    data/raw/                 os 4 arquivos que a origem entregou
    data/chamados_oltp.duckdb o contrafactual (use --tudo para apagar)
    dbt/logs/                 historico de execucao
    dbt/dbt_packages/         o dbt_utils (evita ter que rodar dbt deps)

Uso, da raiz do projeto:
    python scripts/zerar.py            # mostra o que vai apagar e pergunta
    python scripts/zerar.py --sim      # apaga sem perguntar
    python scripts/zerar.py --tudo     # inclui o OLTP simulado
"""

import shutil
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]

CAMADAS = ["bronze", "silver", "gold"]
CATALOGO = RAIZ / "data" / "analytics.duckdb"
TARGET = RAIZ / "dbt" / "target"
OLTP = RAIZ / "data" / "chamados_oltp.duckdb"


def em_uso(caminho: Path) -> str | None:
    """Devolve o motivo se o .duckdb estiver travado por outro processo.

    ⚠ Este é o erro mais comum antes da aula: o DBeaver fica com o
    arquivo aberto, o rm 'funciona' mas o processo continua lendo a
    versão fantasma do inode. Melhor recusar e avisar.
    """
    if not caminho.exists():
        return None
    try:
        import duckdb

        con = duckdb.connect(str(caminho))
        con.close()
        return None
    except Exception as e:
        return str(e).splitlines()[0]


def levantar():
    """Lista o que existe hoje, sem apagar nada."""
    alvos = []
    # Bronze é Delta Lake: cada tabela é uma PASTA (com _delta_log/).
    for p in sorted((RAIZ / "data" / "bronze").iterdir() if (RAIZ / "data" / "bronze").exists() else []):
        if p.is_dir():
            alvos.append(p)
    # Silver e Gold são arquivos Parquet soltos.
    for camada in ["silver", "gold"]:
        for p in sorted((RAIZ / "data" / camada).glob("*.parquet")):
            alvos.append(p)
    if CATALOGO.exists():
        alvos.append(CATALOGO)
    if TARGET.exists():
        alvos.append(TARGET)
    if "--tudo" in sys.argv and OLTP.exists():
        alvos.append(OLTP)
    return alvos


def main():
    alvos = levantar()

    if not alvos:
        print("Já está zerado — nada a apagar.")
        print("\nPara reconstruir:")
        print("    python -m src.pipeline")
        print("    cd dbt && dbt build && cd ..")
        return

    print(f"Vai apagar {len(alvos)} item(ns):\n")
    for p in alvos:
        tipo = "pasta " if p.is_dir() else "arquivo"
        print(f"  {tipo}  {p.relative_to(RAIZ)}")

    print("\nNÃO será tocado:")
    print("  data/raw/          os 4 arquivos da origem")
    print("  dbt/dbt_packages/  o dbt_utils (não precisa rodar dbt deps de novo)")
    if "--tudo" not in sys.argv and OLTP.exists():
        print("  data/chamados_oltp.duckdb   (use --tudo para incluir)")

    # o lock do DBeaver é o tropeço clássico — checar ANTES de apagar
    for db in [CATALOGO] + ([OLTP] if "--tudo" in sys.argv else []):
        motivo = em_uso(db)
        if motivo:
            print(f"\n⚠ {db.name} está EM USO por outro processo:")
            print(f"  {motivo}")
            print("\n  Feche a conexão no DBeaver (botão direito → Disconnect)")
            print("  e rode de novo. Apagar com ele aberto não resolve:")
            print("  o processo continua lendo a versão antiga do arquivo.")
            sys.exit(1)

    if "--sim" not in sys.argv:
        resposta = input("\nConfirma? [s/N] ").strip().lower()
        if resposta not in ("s", "sim", "y"):
            print("Cancelado. Nada foi apagado.")
            return

    for p in alvos:
        if p.is_dir():
            shutil.rmtree(p)
        else:
            p.unlink()

    # as pastas das camadas continuam existindo, vazias, com o .gitkeep
    for camada in CAMADAS:
        (RAIZ / "data" / camada).mkdir(parents=True, exist_ok=True)
        (RAIZ / "data" / camada / ".gitkeep").touch()

    print(f"\nPronto. {len(alvos)} item(ns) apagado(s).")
    print("\nAs três camadas estão vazias. Para reconstruir ao vivo:")
    print("    python -m src.pipeline          # Bronze (Delta): taxas 5573, ufs 28")
    print("    cd dbt && dbt build && cd ..    # Silver + Gold + testes")


if __name__ == "__main__":
    main()
