# Roteiro de leitura da PoC

Este projeto está **completo e comentado**. Ele não é um exercício: é um pipeline
funcionando, escrito para ser **lido e explicado**.

Cada arquivo traz comentários que respondem três perguntas: *o que este código faz*,
*qual problema ele resolve* e *que conceito ele materializa*.

> **As perguntas que movem tudo:**
> 1. taxa média de evasão escolar por **região** e por **UF**;
> 2. a evasão é maior no **Fundamental** ou no **Médio**, e como varia por região.

---

## Executando (5 minutos)

```bash
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\Activate.ps1
pip install -r requirements.txt
cp .env.example .env

python -m src.pipeline        # Fontes -> Bronze (Delta Lake)
cd dbt && dbt deps            # baixa o pacote dbt_utils (1ª vez)
dbt build                     # Bronze -> Silver -> Gold + testes
```

O que esperar:

| Comando | Resultado |
|---|---|
| `python -m src.pipeline` | 2 tabelas Delta em `data/bronze/` (taxas: 5573, ufs: 28) |
| `dbt build` | **PASS=20** (4 modelos + 16 testes) |
| `pytest` | **5 passed** |

---

## A ordem de leitura

### 1. As fontes · `data/raw/`

Um CSV e um JSON, como se tivessem sido exportados do sistema do INEP.
**Contêm problemas de propósito** (lista em [`docs/anomalias-das-fontes.md`](docs/anomalias-das-fontes.md)).

| Arquivo | Formato | **Grão** | Vira |
|---|---|---|---|
| `taxas_municipios.csv` | CSV | um município (taxas 2023) | a tabela fato |
| `ufs.json` | JSON | uma UF (sigla → região) | dimensão |

*Pergunta para a turma:* "os dados estão todos aqui. Já conseguimos responder?" —
não: a **evasão combinada não existe em coluna nenhuma**. O INEP dá o abandono do
Fundamental e do Médio separados; combiná-los é decisão do pipeline.

### 2. A ingestão · `src/ingest.py`

Lê cada fonte e grava uma **tabela Delta** no Bronze. Duas decisões comentadas:

- **tudo é lido como texto** (`dtype=str`) — tipar é interpretar (papel da Silver);
- **compare `ingest_taxas` (CSV) com `ingest_ufs` (JSON)** — muda o leitor, não muda
  o destino. É a ingestão absorvendo a diversidade das fontes.

### 3. O Bronze · `data/bronze/` (Delta Lake)

O que o pipeline capturou, preservado. **Mudou o formato, não o conteúdo** — os
defeitos continuam lá. Cada carga gera uma **versão** (time travel):

```bash
python scripts/time_travel.py    # cria a v1 (correção da taxa > 100) e compara v0 x v1
```

### 4. A Silver · `dbt/models/silver/`

| Modelo | O que demonstra |
|---|---|
| `stg_taxas.sql` | tipagem, deduplicação, **vírgula→ponto** nas taxas, padronização de UF |
| `stg_ufs.sql` | deduplicação que exige uma **decisão de negócio** — qual grafia da região é a oficial? |

### 5. A Gold · `dbt/models/gold/`

| Modelo | O que demonstra |
|---|---|
| `fato_taxa.sql` | grão (município), **métrica derivada** `abandono_combinado`, dimensões degeneradas, tratamento da taxa >100 |
| `dim_uf.sql` | dimensão conformada UF→região, **surrogate key** (hash) + nota sobre SCD |

O `fato_taxa.sql` é o coração: os comentários da métrica `abandono_combinado`
explicam por que a evasão do Fundamental e do Médio é combinada aqui (não existe
pronta) e por que a taxa implausível é neutralizada.

### 6. Os testes · `schema.yml` e `tests/`

- `dbt/models/*/schema.yml` — qualidade de dados como código (16 testes, 4 tipos)
- `tests/test_ingestion.py` — testes do **código** da ingestão (pytest)

O teste `relationships` é o mais didático: em Delta/Parquet **não existe chave
estrangeira**, então a integridade referencial (a UF órfã `ZZ`) vira verificação.

### 7. O consumo · `consultas/analise.sql`

As duas perguntas, com **zero regra de negócio no WHERE**:

```bash
python scripts/rodar_bloco.py analise 1     # Pergunta 1 (região × UF)
python scripts/rodar_bloco.py analise 2     # Pergunta 2 (fundamental × médio)
```

### 8. O dashboard · `app/dashboard.py`

```bash
streamlit run app/dashboard.py
```

Zero regra de negócio: as decisões foram tomadas no pipeline. Trocar o Streamlit por
Power BI produziria o mesmo número. Essa é a função da Gold.

### 9. O lineage

```bash
cd dbt && dbt docs generate && dbt docs serve
```

A DAG do projeto no navegador, com a documentação que nasceu dos mesmos `schema.yml`.

---

## Material de apoio

| Documento | Conteúdo |
|---|---|
| [`DECISOES.md`](DECISOES.md) | as 4 decisões (arquitetura, grão, dado ambíguo, registro inválido) |
| [`docs/architecture.md`](docs/architecture.md) | as camadas e as 5 etapas do `dbt build` |
| [`docs/anomalias-das-fontes.md`](docs/anomalias-das-fontes.md) | os defeitos plantados e onde cada um é tratado |
