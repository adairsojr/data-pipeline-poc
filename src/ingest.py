"""Ingestão: leva os dados das FONTES (data/raw) para o BRONZE (data/bronze).

Regras desta camada:
    - Ler os arquivos de origem (CSV/JSON) com Pandas.
    - Fazer APENAS normalizações técnicas mínimas (nomes de coluna,
      metadado de ingestão). Regra de negócio NÃO entra aqui —
      limpeza, padronização e integração são papel do dbt (Silver).
    - Persistir em DELTA LAKE, preservando o dado o mais próximo
      possível de como ele chegou.

POR QUE DELTA LAKE (e não Parquet solto)?
    O Bronze é a camada de PRESERVAÇÃO do bruto. Delta acrescenta ao
    Parquet um LOG DE TRANSAÇÕES (_delta_log/): cada escrita gera uma
    VERSÃO imutável. Isso dá:
      - time travel: consultar a tabela "como ela estava" na versão N;
      - auditoria: quem escreveu o quê, quando (histórico do bruto);
      - reprocessamento seguro: dá para voltar a uma versão anterior.
    Usamos a biblioteca `deltalake` (Rust puro, SEM Spark).

raw    = os arquivos que a origem (INEP) nos entregou (versionados no repo).
bronze = o que o NOSSO pipeline capturou e persistiu (tabela Delta).

CENÁRIO: as duas fontes são um "export" dos dados do INEP — o CSV com as
taxas de rendimento por município (aprovação, reprovação e abandono) e o
JSON com o cadastro de UF -> região. O ABANDONO é a evasão escolar que a
PoC quer analisar.
"""

import logging
import os
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
from deltalake import DeltaTable, write_deltalake
from dotenv import load_dotenv

# ---------------------------------------------------------------------
# Configuração: vem do .env (criado a partir do .env.example). Caminhos
# NÃO ficam hardcoded — o mesmo código roda em qualquer máquina; só o
# .env muda. Em projetos reais, é no .env que entrariam credenciais,
# hosts de banco, buckets etc.
# ---------------------------------------------------------------------
PROJECT_ROOT = Path(__file__).resolve().parents[1]
load_dotenv(PROJECT_ROOT / ".env")

DATA_RAW_PATH = PROJECT_ROOT / os.getenv("DATA_RAW_PATH", "data/raw")
DATA_BRONZE_PATH = PROJECT_ROOT / os.getenv("DATA_BRONZE_PATH", "data/bronze")

logger = logging.getLogger(__name__)


def _gravar_bronze(df: pd.DataFrame, nome: str) -> None:
    """Acrescenta metadado técnico e grava uma tabela DELTA no Bronze.

    mode="overwrite": cada execução do pipeline gera uma NOVA VERSÃO da
    tabela Delta (o dado é reescrito, mas o histórico de versões é
    preservado no _delta_log/). É isso que habilita o time travel.
    """
    df = df.copy()
    df["_ingerido_em"] = datetime.now(timezone.utc).isoformat()
    destino = DATA_BRONZE_PATH / nome
    destino.mkdir(parents=True, exist_ok=True)
    write_deltalake(str(destino), df, mode="overwrite")
    versao = DeltaTable(str(destino)).version()
    logger.info("Bronze (Delta) gravado: %s v%d (%d registros)", nome, versao, len(df))


def ingest_taxas() -> None:
    """Ingestão do CSV de taxas de rendimento — a fonte central da PoC.

    Uma linha por município: taxas de aprovação, reprovação e abandono
    (Fundamental) e abandono (Médio). É desta tabela que sairá a fato.
    """
    origem = DATA_RAW_PATH / "taxas_municipios.csv"
    logger.info("Lendo %s", origem.name)
    # dtype=str => tudo chega como texto.
    # Decisão consciente: o Bronze preserva o dado como veio;
    # tipar é decisão de transformação (Silver/dbt). As taxas têm defeitos
    # (vírgula decimal, ">100") que só serão tratados na Silver.
    df = pd.read_csv(origem, dtype=str).fillna("")
    logger.info("%d registros encontrados", len(df))
    _gravar_bronze(df, "taxas")


def ingest_ufs() -> None:
    """Ingestão do JSON de UFs — o cadastro que dá REGIÃO a cada estado.

    Repare no que muda em relação à ingestão do CSV — e no que NÃO muda:

    - muda o LEITOR: `read_json` no lugar de `read_csv`, porque a origem
      entrega uma lista de objetos JSON, não linhas separadas por vírgula;
    - convertemos tudo para texto com `.astype(str)`, mantendo a mesma
      regra da outra fonte: o Bronze preserva, quem tipa é a Silver;
    - NÃO muda o destino: sai uma tabela Delta igual à outra. É por isso
      que, da Silver em diante, o dbt trata CSV e JSON do mesmo jeito.

    ⚠ Existe uma UF repetida no JSON (mesma sigla, região em outra
    grafia). O Bronze preserva as duas linhas — resolver isso é papel
    da Silver, não da ingestão.
    """
    origem = DATA_RAW_PATH / "ufs.json"
    logger.info("Lendo %s", origem.name)
    df = pd.read_json(origem, dtype=str).astype(str)
    logger.info("%d registros encontrados", len(df))
    _gravar_bronze(df, "ufs")


def main() -> None:
    ingest_taxas()
    ingest_ufs()


if __name__ == "__main__":
    main()
