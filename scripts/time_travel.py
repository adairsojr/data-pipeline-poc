"""Demonstração de TIME TRAVEL do Delta Lake na camada de preservação.

CONTEXTO: o Bronze é uma tabela Delta. Cada escrita gera uma VERSÃO
imutável, registrada no _delta_log/. Este script mostra o recurso na
prática, em três passos:

  1. Mostra o histórico de versões da tabela Delta `taxas`.
  2. Simula uma NOVA CARGA da origem (uma "correção": o INEP reenviou os
     dados corrigindo a taxa de abandono IMPLAUSÍVEL — o valor 150.0, o
     DEFEITO 4 — para um valor válido). Isso gera uma nova VERSÃO.
  3. Roda a MESMA consulta na versão ANTERIOR e na versão ATUAL, lado a
     lado, provando que o passado continua consultável (auditoria) e que
     dá para voltar no tempo (reprocessamento seguro).

Uso, da raiz do projeto:
    python -m src.pipeline            # garante o Bronze v0
    python scripts/time_travel.py     # cria a v1 (correção) e compara

⚠ Idempotência: rode `python -m src.pipeline` de novo para o Bronze
voltar a uma carga limpa (nova versão), quando quiser reapresentar.
"""

from pathlib import Path

from deltalake import DeltaTable, write_deltalake

RAIZ = Path(__file__).resolve().parents[1]
TABELA = RAIZ / "data" / "bronze" / "taxas"


def historico(dt: DeltaTable) -> None:
    print(f"\nVersão atual da tabela Delta 'taxas': v{dt.version()}")
    print("Histórico (mais recente primeiro):")
    for h in dt.history():
        print(
            f"  v{h.get('version'):>2}  {h.get('operation'):<10}  "
            f"timestamp={h.get('timestamp')}"
        )


def contar_implausiveis(versao: int) -> int:
    """Conta, numa versão específica do Bronze, as taxas de abandono
    IMPLAUSÍVEIS (> 100), tratando vírgula decimal."""
    dt = DeltaTable(str(TABELA), version=versao)
    df = dt.to_pandas()

    def _to_float(v):
        try:
            return float(str(v).replace(",", "."))
        except (ValueError, TypeError):
            return None

    vals = df["taxa_abandono_fund"].map(_to_float)
    return int((vals > 100).sum())


def main() -> None:
    if not TABELA.exists():
        raise SystemExit("Bronze não encontrado. Rode antes:  python -m src.pipeline")

    dt = DeltaTable(str(TABELA))
    historico(dt)
    versao_antes = dt.version()

    # -----------------------------------------------------------------
    # PASSO 2 — a origem reenvia os dados CORRIGINDO a taxa implausível.
    # Lemos a versão atual, corrigimos e regravamos -> nova versão Delta.
    # -----------------------------------------------------------------
    df = dt.to_pandas()

    def _corrige(v):
        try:
            f = float(str(v).replace(",", "."))
            if f > 100:
                return ""   # a origem admite que o valor era inválido
        except (ValueError, TypeError):
            pass
        return v

    df["taxa_abandono_fund"] = df["taxa_abandono_fund"].map(_corrige)
    write_deltalake(str(TABELA), df, mode="overwrite")
    print("\n>> Nova carga da origem gravada (correção da taxa de abandono > 100).")

    dt2 = DeltaTable(str(TABELA))
    historico(dt2)
    versao_depois = dt2.version()

    # -----------------------------------------------------------------
    # PASSO 3 — a MESMA consulta, nas duas versões.
    # -----------------------------------------------------------------
    print("\n=== TIME TRAVEL: taxas de abandono IMPLAUSÍVEIS (> 100) ===")
    antes = contar_implausiveis(versao_antes)
    depois = contar_implausiveis(versao_depois)
    print(f"  v{versao_antes} (anterior): {antes} taxa(s) implausível(is)")
    print(f"  v{versao_depois} (atual)  : {depois} taxa(s) implausível(is)")
    print(
        "\nO dado antigo NÃO foi perdido: continua consultável na v"
        f"{versao_antes}. É auditoria e reprocessamento seguro — o que o"
        " Delta Lake acrescenta ao Parquet solto."
    )


if __name__ == "__main__":
    main()
