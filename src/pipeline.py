"""Orquestrador do pipeline de ingestão.

Propositalmente simples: um pipeline é, antes de qualquer ferramenta,
uma SEQUÊNCIA DE ETAPAS COM DEPENDÊNCIAS. Orquestradores profissionais
(Airflow, Dagster...) resolvem agendamento, retries e paralelismo —
mas o conceito é este aqui.

Execução:  python -m src.pipeline
"""

import logging

from src import ingest
from src.config import LOG_LEVEL

logging.basicConfig(
    level=LOG_LEVEL,
    format="[%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)


def main() -> None:
    logger.info("Iniciando pipeline de ingestão")

    etapas = [
        ingest.ingest_chamados,
        ingest.ingest_unidades,
        ingest.ingest_categorias,
        ingest.ingest_interacoes,
    ]

    for etapa in etapas:
        etapa()

    logger.info("Ingestão concluída. Bronze disponível em data/bronze/")


if __name__ == "__main__":
    main()
