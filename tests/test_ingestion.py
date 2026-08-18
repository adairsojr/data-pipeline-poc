"""Testes da camada de INGESTÃO (pytest).

⚠ A distinção que vale explicar em aula:

    pytest    -> testa o CÓDIGO.  "a função de ingestão se comporta
                 como esperado?" Roda sem precisar de dados novos.

    dbt test  -> testa os DADOS.  "os registros respeitam as regras que
                 declaramos?" Depende do que chegou da origem.

São complementares: um pipeline pode ter código perfeito processando
dados ruins (pytest passa, dbt test falha) — ou código com bug sobre
dados bons (o contrário).
"""

import pandas as pd

from src import ingest
from src.config import DATA_BRONZE_PATH, DATA_RAW_PATH


def test_ingest_chamados_gera_parquet():
    """A ingestão deve produzir o arquivo Parquet no Bronze."""
    ingest.ingest_chamados()
    assert (DATA_BRONZE_PATH / "chamados.parquet").exists()


def test_bronze_preserva_todas_as_linhas_da_origem():
    """O Bronze PRESERVA: mesma quantidade de linhas da origem.

    Este é o teste que garante o princípio da camada. Se alguém um dia
    colocar um filtro na ingestão ("vamos já remover as duplicatas
    aqui"), este teste falha — e é isso que queremos, porque limpeza
    é papel da Silver, não da captura.
    """
    ingest.ingest_chamados()
    origem = pd.read_csv(DATA_RAW_PATH / "chamados.csv", dtype=str)
    bronze = pd.read_parquet(DATA_BRONZE_PATH / "chamados.parquet")
    assert len(bronze) == len(origem)


def test_bronze_tem_metadado_de_ingestao():
    """Toda tabela Bronze carrega a coluna técnica _ingerido_em.

    É o mínimo de rastreabilidade: saber QUANDO aquele dado entrou no
    pipeline. Numa implementação madura, entrariam também o nome do
    arquivo de origem e um hash do conteúdo.
    """
    ingest.ingest_unidades()
    bronze = pd.read_parquet(DATA_BRONZE_PATH / "unidades.parquet")
    assert "_ingerido_em" in bronze.columns


def test_ingest_interacoes_gera_parquet_com_colunas():
    """A ingestão do JSON produz Parquet com as colunas esperadas.

    Repare: o teste é igual ao do CSV. Para o resto do pipeline, a
    diferença de formato na origem desapareceu — foi absorvida pela
    ingestão.
    """
    ingest.ingest_interacoes()
    destino = DATA_BRONZE_PATH / "interacoes.parquet"
    assert destino.exists()
    bronze = pd.read_parquet(destino)
    for coluna in ["chamado_id", "tipo_interacao", "data_interacao"]:
        assert coluna in bronze.columns


def test_bronze_interacoes_preserva_eventos():
    """O Bronze do JSON também preserva a contagem da origem."""
    ingest.ingest_interacoes()
    origem = pd.read_json(DATA_RAW_PATH / "interacoes.json")
    bronze = pd.read_parquet(DATA_BRONZE_PATH / "interacoes.parquet")
    assert len(bronze) == len(origem)
