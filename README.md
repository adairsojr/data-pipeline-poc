# PoC — A Jornada do Dado: do Censo Escolar à decisão (evasão escolar · INEP)

Prova de conceito da disciplina **Gestão e Governança de Dados** (Especialização em
Engenharia de Software Inteligente · FACOM/UFMS).

Este repositório **não é um template**: é a jornada
`Fonte → Ingestão → Preservação do bruto → Transformação → Consumo → Resposta`
**já aplicada, ponta a ponta**, sobre uma base pública real e brasileira — as **Taxas de
Rendimento Escolar** do **INEP** (Censo Escolar 2023), com foco na **evasão (abandono)
escolar por município**. O pipeline roda, os testes passam e as perguntas de negócio
já têm resposta (veja [As respostas](#as-respostas-encontradas)).

> **Equipe:** Adair, Michel e Julia.
> **Base:** [INEP — Taxas de Rendimento Escolar](https://www.gov.br/inep/pt-br/acesso-a-informacao/dados-abertos/indicadores-educacionais/taxas-de-rendimento-escolar)
> (dados públicos e agregados por município, não-pessoais). Arquivo `tx_rend_municipios_2023.zip`.

**Estado atual (verificado):** `python -m src.pipeline` gera o Bronze (Delta) com
5.573 municípios; `dbt build` roda 4 modelos + 16 testes (**PASS=20, ERROR=0**);
`pytest` **5 passed**. A `fato_taxa` tem **5.569 municípios** após o tratamento dos
defeitos (5.573 − 2 duplicatas − 1 sem código − 1 UF órfã).

---

## As perguntas de negócio

O INEP, a partir do Censo Escolar, calcula para cada município as taxas de
**aprovação, reprovação e abandono**. O **abandono** é a evasão escolar — quando o
aluno deixa a escola durante o ano letivo.

> **Pergunta 1 — Qual é a taxa média de evasão escolar dos municípios, por REGIÃO e por UF?**
>
> **Pergunta 2 — A evasão é maior no Ensino FUNDAMENTAL ou no MÉDIO — e como isso varia por REGIÃO?**

O detalhe que move o projeto: a **evasão combinada por município não existe em fonte
nenhuma**. O INEP entrega o abandono do Fundamental e do Médio **separados**; a visão
única (`abandono_combinado`) é uma **métrica derivada** — calculada no pipeline. E as
perguntas pedem **recortes** por região, UF e etapa de ensino.

---

## O problema (os defeitos são de propósito)

As duas fontes em `data/raw/` são um recorte real dos dados do INEP, com **7 problemas
de qualidade plantados de propósito** — e **todos já tratados** no pipeline (lista
completa e onde cada um é resolvido em [`docs/anomalias-das-fontes.md`](docs/anomalias-das-fontes.md)):

- taxas com **vírgula** decimal em vez de ponto (padrão brasileiro vs. o do arquivo);
- duas linhas integralmente duplicadas;
- um município sem código (registro sem chave);
- um município apontando para uma UF que não existe no cadastro (`ZZ`);
- UF com grafia inconsistente (caixa/espaços);
- uma taxa de abandono **implausível** (> 100);
- uma UF repetida no JSON, com a região em outra grafia.

Nada aqui está perfeito — e é por isso que a camada Silver existe.

---

## Arquitetura

```text
FONTES            CSV + JSON             (data/raw)
  ↓
INGESTÃO          Python + Pandas        (src/)
  ↓
BRONZE            DELTA LAKE (versionado)(data/bronze)   <- preservação do bruto
  ↓
TRANSFORMAÇÃO     dbt + DuckDB           (dbt/)
  ↓
SILVER            limpo, tipado, padronizado  (Parquet)
  ↓
GOLD              estrela: fato + dimensão     (Parquet)
  ↓
CONSUMO           SQL (consultas/) + dashboard (app/)
```

### Quem faz o quê

| Tecnologia | Responsabilidade |
|---|---|
| **Python + Pandas** | Ler as fontes e persistir o Bronze (ingestão) — sem regra de negócio |
| **Delta Lake** (`deltalake`, sem Spark) | Armazenar o Bronze **versionado** (time travel, auditoria) |
| **DuckDB** | Engine analítico local (lê Delta e Parquet, executa o dbt) |
| **dbt** | Transformação declarativa: Silver, Gold, testes, docs, lineage |

As **4 decisões de arquitetura e modelagem** estão em [`DECISOES.md`](DECISOES.md).
O passo a passo completo do processo (onde os dados foram buscados, o que mudou e por
quê) está em [`PROCESSO.md`](PROCESSO.md).

### O modelo dimensional (Gold)

- **`fato_taxa`** — grão: **um município** por linha (2023). Métrica derivada: `abandono_combinado`.
- **`dim_uf`** — UF + macrorregião (deduplicada). Hierarquia município → UF → região.

---

## Como executar

Pré-requisitos: **Python 3.11+**. Da raiz do projeto:

```bash
python -m venv .venv
# Windows PowerShell:  .venv\Scripts\Activate.ps1
# Linux/macOS:         source .venv/bin/activate

pip install -r requirements.txt
copy .env.example .env     # Windows   (Linux/macOS: cp .env.example .env)

# 1) INGESTÃO — Fontes (data/raw) -> Bronze (Delta Lake)
python -m src.pipeline

# 2) TRANSFORMAÇÃO — Bronze -> Silver -> Gold + testes
cd dbt
dbt deps          # baixa o dbt_utils (só na 1ª vez)
dbt build         # roda os 4 modelos + os 16 testes
cd ..
```

**Critério de aceite (clone limpo):** `python -m src.pipeline` seguido de
`dbt build` funciona sem ajuste manual. O que esperar:

| Comando | Resultado |
|---|---|
| `python -m src.pipeline` | 2 tabelas Delta em `data/bronze/` (taxas: 5573, ufs: 28) |
| `dbt build` | **PASS=20** (4 modelos + 16 testes), ERROR=0 |
| `pytest` | **5 passed** |

> Se o comando `dbt` não estiver no PATH, use o executável em
> `…/PythonScripts/dbt.exe` ou rode `python -c "from dbt.cli.main import cli; cli()" build`.

### As respostas (o consumo)

```bash
python scripts/rodar_bloco.py analise 1     # Pergunta 1 (região × UF)
python scripts/rodar_bloco.py analise 2     # Pergunta 2 (fundamental × médio)
```

Ou o dashboard: `streamlit run app/dashboard.py`.

<a name="as-respostas-encontradas"></a>
#### As respostas encontradas

Executando as consultas sobre a Gold (números reais, 2023):

- **Pergunta 1 (evasão média por região):** a evasão é mais alta no **Nordeste**
  (~2,49%) e mais baixa no **Centro-Oeste** (~0,87%). Entre as UFs, o **Acre** lidera
  (~5,8% de evasão média por município). *Onde concentrar política de permanência.*
- **Pergunta 2 (Fundamental × Médio):** em **todas** as regiões a evasão do **Ensino
  Médio** é bem maior que a do Fundamental — diferença de ~1,3 a ~3,6 pontos
  percentuais. *O problema se concentra no Médio; é ali que a política precisa agir.*

Esses números saem da métrica derivada e das taxas já tratadas no pipeline — não de
ajustes na consulta. Trocar a ferramenta de consumo (SQL, dashboard, Power BI) dá o
mesmo resultado: a regra mora num lugar só.

### Time travel do Delta Lake (2+ versões)

```bash
python -m src.pipeline            # garante o Bronze v0
python scripts/time_travel.py     # cria a v1 (correção) e compara as versões
```

O script simula uma **nova carga da origem** que corrige a taxa de abandono
implausível (> 100), gerando a **versão 1** do Bronze, e roda a **mesma consulta** na
v0 e na v1 lado a lado: a v0 ainda mostra o defeito, a v1 já não — provando auditoria e
reprocessamento seguro.

### Recomeçar do zero (para a demo ao vivo)

```bash
python scripts/zerar.py --sim     # apaga Bronze/Silver/Gold gerados (mantém data/raw)
```

### Gerar as fontes de novo (opcional)

As fontes já vêm versionadas em `data/raw/`. Para regerá-las a partir do cache do INEP:

```bash
python scripts/gerar_fontes.py --offline   # usa o cache (data/raw/_inep_cache.csv)
python scripts/gerar_fontes.py             # rebaixa o ZIP do INEP
```

---

## Os 9 itens obrigatórios — onde ver cada um

| Item | Onde |
|---|---|
| 1. Fontes (2+, 2 formatos, com defeitos) | `data/raw/taxas_municipios.csv` (CSV) + `data/raw/ufs.json` (JSON) |
| 2. Ingestão (Python, sem regra de negócio) | `src/ingest.py`, `src/pipeline.py` |
| 3. Preservação do bruto (reprocessável) | Bronze em Delta Lake — `data/bronze/` |
| 4. Transformação com regras comentadas | `dbt/models/silver/stg_*.sql` |
| 5. Camada de consumo (grão declarado) | `dbt/models/gold/fato_taxa.sql` |
| 6. Testes (≥8, 3+ tipos) | `dbt/models/*/schema.yml` (16 testes; 4 tipos) |
| 7. Linhagem (dbt docs / DAG) | `cd dbt && dbt docs generate && dbt docs serve` |
| 8. A resposta (SQL sem regra no WHERE) | `consultas/analise.sql` |
| 9. Versionamento com Delta Lake (2+ versões) | `src/ingest.py` + `scripts/time_travel.py` |

As 4 decisões: [`DECISOES.md`](DECISOES.md).

---

**Engenharia de Dados não existe apenas para mover arquivos ou alimentar dashboards.**
Ela constrói e mantém a jornada necessária para transformar dados em informação
confiável e utilizável.
