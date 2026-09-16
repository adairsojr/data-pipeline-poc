"""Testes da camada de INGESTÃO (pytest).

⚠ A distinção que vale explicar em aula:

    pytest    -> testa o CÓDIGO.  "a função de ingestão se comporta
                 como esperado?" Roda sem precisar de dados novos.

    dbt test  -> testa os DADOS.  "os registros respeitam as regras que
                 declaramos?" Depende do que chegou da origem.

São complementares: um pipeline pode ter código perfeito processando
dados ruins (pytest passa, dbt test falha) — ou o contrário.

O Bronze aqui é DELTA LAKE: cada tabela é uma pasta com _delta_log/.
Lemos de volta com deltalake.DeltaTable.
"""

import pandas as pd
from deltalake import DeltaTable

from src import ingest
from src.ingest import DATA_BRONZE_PATH, DATA_RAW_PATH


def _ler_bronze(nome: str) -> pd.DataFrame:
    return DeltaTable(str(DATA_BRONZE_PATH / nome)).to_pandas()


def test_ingest_taxas_gera_tabela_delta():
    """A ingestão deve produzir a tabela Delta 'taxas' no Bronze."""
    ingest.ingest_taxas()
    assert (DATA_BRONZE_PATH / "taxas" / "_delta_log").exists()


def test_bronze_preserva_todas_as_linhas_da_origem():
    """O Bronze PRESERVA: mesma quantidade de linhas da origem.

    Se alguém um dia colocar um filtro na ingestão ("vamos já remover as
    duplicatas aqui"), este teste falha — e é isso que queremos, porque
    limpeza é papel da Silver, não da captura.
    """
    ingest.ingest_taxas()
    origem = pd.read_csv(DATA_RAW_PATH / "taxas_municipios.csv", dtype=str)
    bronze = _ler_bronze("taxas")
    assert len(bronze) == len(origem)


def test_bronze_tem_metadado_de_ingestao():
    """Toda tabela Bronze carrega a coluna técnica _ingerido_em.

    É o mínimo de rastreabilidade: saber QUANDO aquele dado entrou.
    """
    ingest.ingest_ufs()
    bronze = _ler_bronze("ufs")
    assert "_ingerido_em" in bronze.columns


def test_ingest_ufs_gera_tabela_com_colunas():
    """A ingestão do JSON produz uma tabela Delta com as colunas esperadas.

    Para o resto do pipeline, a diferença de formato na origem
    (CSV vs JSON) desapareceu — foi absorvida pela ingestão.
    """
    ingest.ingest_ufs()
    bronze = _ler_bronze("ufs")
    for coluna in ["uf", "regiao"]:
        assert coluna in bronze.columns


def test_bronze_gera_versao_delta():
    """Cada gravação do Bronze é uma versão Delta (time travel)."""
    ingest.ingest_taxas()
    dt = DeltaTable(str(DATA_BRONZE_PATH / "taxas"))
    assert dt.version() >= 0
    assert len(dt.history()) >= 1
