"""Orquestrador do pipeline de ingestão.

Propositalmente simples: um pipeline é, antes de qualquer ferramenta,
uma SEQUÊNCIA DE ETAPAS COM DEPENDÊNCIAS. Orquestradores profissionais
(Airflow, Dagster...) resolvem agendamento, retries e paralelismo —
mas o conceito é este aqui.

Cada execução regrava as tabelas Delta do Bronze, gerando uma nova
versão (time travel). O pipeline é REPROCESSÁVEL: roda do zero, a
partir das fontes em data/raw/, quantas vezes quiser.

Execução:  python -m src.pipeline
"""

import logging
import os

from src import ingest

# O nível de log vem do .env (carregado em src/ingest.py na importação).
logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="[%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)


def main() -> None:
    logger.info("Iniciando pipeline de ingestão")

    etapas = [
        ingest.ingest_taxas,
        ingest.ingest_ufs,
    ]

    for etapa in etapas:
        etapa()

    logger.info("Ingestão concluída. Bronze (Delta) disponível em data/bronze/")


if __name__ == "__main__":
    main()
