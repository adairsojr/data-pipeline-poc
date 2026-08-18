"""Ingestão: leva os dados das FONTES (data/raw) para o BRONZE (data/bronze).

Regras desta camada:
    - Ler os arquivos de origem (CSV/JSON) com Pandas.
    - Fazer APENAS normalizações técnicas mínimas (nomes de coluna,
      metadado de ingestão). Regra de negócio NÃO entra aqui —
      limpeza, padronização e integração são papel do dbt (Silver).
    - Persistir em Parquet, preservando o dado o mais próximo
      possível de como ele chegou.

raw    = os arquivos que a origem nos entregou (versionados no repo).
bronze = o que o NOSSO pipeline capturou e persistiu (gerado ao executar).

CENÁRIO: os quatro arquivos são um "export" do sistema de chamados da
Central de Serviços — o OLTP. Não temos acesso ao banco: temos o que a
origem quis nos dar, com os defeitos que ela tinha.
"""

import logging
from datetime import datetime, timezone

import pandas as pd

from src.config import DATA_BRONZE_PATH, DATA_RAW_PATH

logger = logging.getLogger(__name__)


def _gravar_bronze(df: pd.DataFrame, nome: str) -> None:
    """Acrescenta metadado técnico de ingestão e grava Parquet no Bronze."""
    df = df.copy()
    df["_ingerido_em"] = datetime.now(timezone.utc).isoformat()
    DATA_BRONZE_PATH.mkdir(parents=True, exist_ok=True)
    destino = DATA_BRONZE_PATH / f"{nome}.parquet"
    df.to_parquet(destino, index=False)
    logger.info("Bronze gravado: %s (%d registros)", destino.name, len(df))


def ingest_chamados() -> None:
    """Ingestão do CSV de chamados — a fonte central da PoC.

    Um chamado por linha: quando foi aberto, quando foi fechado, de que
    unidade veio e de que categoria é. É desta tabela que sairá a fato.
    """
    origem = DATA_RAW_PATH / "chamados.csv"
    logger.info("Lendo %s", origem.name)
    # dtype=str => tudo chega como texto.
    # Decisão consciente: o Bronze preserva o dado como veio;
    # tipar é decisão de transformação (Silver/dbt).
    df = pd.read_csv(origem, dtype=str)
    logger.info("%d registros encontrados", len(df))
    _gravar_bronze(df, "chamados")


def ingest_unidades() -> None:
    """Ingestão do CSV de unidades — o cadastro geográfico.

    Existe para que `unidade_id = 4` vire "Corumbá" no relatório. Sem ele,
    o gestor recebe uma tabela de números.
    """
    origem = DATA_RAW_PATH / "unidades.csv"
    logger.info("Lendo %s", origem.name)
    df = pd.read_csv(origem, dtype=str)
    logger.info("%d registros encontrados", len(df))
    _gravar_bronze(df, "unidades")


def ingest_categorias() -> None:
    """Ingestão do CSV de categorias de chamado.

    São 7 linhas para 6 categorias: o `categoria_id = 2` aparece duas
    vezes, com grafias diferentes. Num banco relacional a chave primária
    impediria; num CSV não existe chave alguma.
    """
    origem = DATA_RAW_PATH / "categorias.csv"
    logger.info("Lendo %s", origem.name)
    df = pd.read_csv(origem, dtype=str)
    logger.info("%d registros encontrados", len(df))
    _gravar_bronze(df, "categorias")


def ingest_interacoes() -> None:
    """Ingestão do JSON de interações dos chamados.

    Repare no que muda em relação às ingestões de CSV — e no que NÃO muda:

    - muda o LEITOR: `read_json` no lugar de `read_csv`, porque a origem
      entrega uma lista de objetos JSON, não linhas separadas por vírgula;
    - `read_json` infere tipos por conta própria (viraria int, datetime...),
      então convertemos tudo para texto com `.astype(str)` — mantendo a
      mesma regra das outras fontes: o Bronze preserva, quem tipa é a Silver;
    - NÃO muda o destino: sai um Parquet igual aos outros. É por isso que,
      da Silver em diante, o dbt trata CSV e JSON exatamente do mesmo jeito.

    Essa é a função da camada de ingestão: absorver a diversidade das fontes
    e entregar um formato único para o resto do pipeline.

    ⚠ ATENÇÃO AO GRÃO: são 408 interações para 122 chamados — de 1 a 6
    eventos por chamado. Aqui um chamado NÃO é uma linha. Juntar este
    arquivo com o de chamados sem pensar multiplica as linhas e corrompe
    qualquer média (isso se chama FAN-OUT).
    """
    origem = DATA_RAW_PATH / "interacoes.json"
    logger.info("Lendo %s", origem.name)
    df = pd.read_json(origem).astype(str)
    logger.info("%d registros encontrados", len(df))
    _gravar_bronze(df, "interacoes")
