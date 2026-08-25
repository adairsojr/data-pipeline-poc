# PoC — A Jornada do Dado: do sistema transacional à decisão

Prova de conceito da disciplina **Gestão e Governança de Dados** (Especialização em Engenharia de Software Inteligente · FACOM/UFMS).

Na aula anterior, estudamos conceitualmente a jornada `Fonte → Ingestão → Armazenamento → Transformação → Serving → Consumo`. Aqui ela deixa de ser um desenho e vira um pipeline que executa.

> **Este projeto está completo e comentado.** Cada arquivo explica o que faz, qual problema resolve e que conceito materializa. A ordem de leitura está em [`POC.md`](POC.md).

## A pergunta de negócio

> **Qual é o tempo médio de atendimento por unidade, categoria e período?**

Uma pergunta simples de enunciar. Todo o projeto existe para respondê-la de forma **confiável e reproduzível** — e responder assim exige a jornada inteira.

## O problema

Os dados de que precisamos estão espalhados em fontes diferentes da Central de Serviços de uma instituição fictícia — CSVs e JSON, como se tivessem sido exportados de sistemas distintos — e **contêm problemas reais de qualidade**: datas em formatos misturados, registros duplicados, identificadores órfãos, grafias inconsistentes. Nada aqui está perfeito de propósito.

O cenário: uma central de atendimento com oito unidades, que registra chamados de suporte (acesso e senha, rede, equipamento, sistema acadêmico, e-mail, impressão). Cada chamado tem uma data de abertura e, se já foi resolvido, uma data de fechamento. **O tempo de atendimento não existe em fonte nenhuma** — é preciso derivá-lo.

## Arquitetura

```text
FONTES            CSV / JSON            (data/raw)
  ↓
INGESTÃO          Python + Pandas       (src/)
  ↓
BRONZE            Parquet               (data/bronze)
  ↓
TRANSFORMAÇÃO     dbt + DuckDB          (dbt/)
  ↓
SILVER            limpos, tipados, integrados
  ↓
GOLD              modelo analítico (fato + dimensões)
  ↓
SERVING           DuckDB                (data/analytics.duckdb)
  ↓
CONSUMO           SQL / indicadores
```

Detalhes e diagrama em [`docs/architecture.md`](docs/architecture.md).

### Quem faz o quê

| Tecnologia | Responsabilidade | O que NÃO faz aqui |
|---|---|---|
| **Python + Pandas** | Ler as fontes e persistir o Bronze (ingestão) | Regra de negócio |
| **Parquet** | Armazenamento colunar do Bronze | — |
| **DuckDB** | Engine analítico local (consulta Parquet, executa o dbt) | Servidor de banco |
| **dbt** | Transformação declarativa: Silver, Gold, testes, docs, lineage | Ingestão |

> O dbt começa a trabalhar quando os dados **já estão disponíveis para um
> engine analítico**. Trazer os dados até lá é papel da ingestão.

### `data/raw` não é Bronze

- **`data/raw/`** — os arquivos que a origem nos entregou (versionados no repo, para a atividade).
- **`data/bronze/`** — o que o **nosso pipeline capturou e persistiu** (gerado quando você executa a ingestão), preservado o mais próximo possível da origem, com metadado de ingestão e formato eficiente.

> ⚠ **Cuidado com a palavra "raw".** Aqui `data/raw/` são os arquivos **recebidos das origens** — o que existe ANTES do pipeline. Em boa parte do mercado, porém, *raw zone* é usado como **sinônimo de Bronze**. São coisas diferentes: `raw` é o que a origem entregou; `bronze` é o que o **nosso pipeline** capturou e persistiu.

### O Medallion mora em `data/`

A pasta `data/` é o **storage** desta PoC — um mini data lake local:

```text
data/
├── raw/   # sistemas de origem (simulados)
├── bronze/       # dado capturado, próximo à origem      <- escrito pela INGESTÃO (Pandas)
├── silver/       # dado limpo, tipado, padronizado       <- escrito pelo DBT
└── gold/         # dado modelado para consumo (fato/dims) <- escrito pelo DBT
```

Todas as camadas são **arquivos Parquet** — abra as pastas depois de rodar o pipeline e o `dbt run` e veja o refinamento progressivo acontecer no disco. O DuckDB registra *views* sobre esses arquivos no `data/analytics.duckdb`: é a separação entre **armazenamento** (arquivos nas pastas) e **processamento** (o engine que os consulta) — o mesmo princípio do Lakehouse, em miniatura. Num projeto real, `data/` viraria um bucket de object storage (S3/MinIO) e nada do raciocínio mudaria.

Em produção não existiria uma pasta `fontes` no repositório: os dados chegariam por APIs, bancos e eventos. O Bronze é a **porta de entrada oficial** do pipeline.

## Estrutura do repositório

```text
data-pipeline-poc/
├── README.md
├── .gitignore            # o que NÃO vai para o Git (dados gerados, .env, artefatos)
├── .env.example          # modelo de configuração (copie para .env)
├── requirements.txt      # dependências Python do projeto
│
├── data/                 # o STORAGE da PoC (nosso mini data lake local)
│   ├── raw/       #   sistemas de origem simulados (CSV/JSON) — versionados
│   ├── bronze/           #   camada Bronze: Parquet gravado pela INGESTÃO
│   ├── silver/           #   camada Silver: Parquet gravado pelo DBT
│   ├── gold/             #   camada Gold:   Parquet gravado pelo DBT
│   ├── analytics.duckdb  #   catálogo/serving do DuckDB (gerado no 1º dbt run)
│   └── chamados_oltp.duckdb #  OLTP normalizado, p/ a comparação do slide 4 (gerado)
│
├── src/                  # código de INGESTÃO (Python)
│   ├── ingest.py         #   ingestão por fonte (lê o .env; Pandas -> Parquet)
│   └── pipeline.py       #   orquestrador: executa as ingestões em sequência
│
├── dbt/                  # projeto de TRANSFORMAÇÃO (dbt)
│   ├── dbt_project.yml   #   configuração do projeto (camadas, materializações)
│   ├── profiles.yml      #   conexão com o DuckDB (sem credenciais -> versionado)
│   ├── packages.yml      #   dependências (dbt_utils -> surrogate keys); dbt deps
│   └── models/
│       ├── sources.yml   #   declara o Bronze como fonte (source) do dbt
│       ├── silver/       #   stg_*: tipagem, limpeza, padronização (1 .sql por tabela)
│       │   └── schema.yml#   testes de qualidade da Silver
│       └── gold/         #   fato_chamado + dimensões (modelo analítico)
│           └── schema.yml#   testes de qualidade da Gold
│
├── diagramas/            # os diagramas em Mermaid (diagrama como código)
│   ├── README.md         #   renderiza tudo; explica como ver no VS Code
│   └── *.mmd             #   modelo da origem · DAG · star schema · jornada
├── notebooks/
│   └── exploracao.ipynb  # explorar os dados de cada camada (opcional)
├── consultas/
│   ├── analise.sql       # o consumo: 5 consultas comentadas (+ 2 armadilhas)
│   ├── dados_brutos.sql  # os 4 analistas + os defeitos, lidos direto de raw/
│   └── oltp_quatro_analistas.sql  # OPCIONAL: o contrafactual, num banco
├── scripts/
│   ├── criar_oltp_simulado.py   # OPCIONAL: o banco que a PoC NÃO tem (contraste)
│   └── rodar_bloco.py           # roda um bloco dos .sql acima, por vez
├── tests/                # pytest: testa o CÓDIGO da ingestão
└── docs/
    ├── architecture.md              # camadas, decisões e as 5 etapas do dbt run
    ├── anomalias-das-fontes.md      # os 15 defeitos, arquivo por arquivo
    └── comparacao-oltp-vs-gold.md   # a mesma pergunta: no OLTP × na Gold
```

**Como ler essa estrutura:** `data/` é o *lugar onde os dados vivem* (storage); `src/` e `dbt/` são o *código que os move e transforma* (processamento). O dado caminha da esquerda para a direita dentro de `data/` (`raw → bronze → silver → gold`), e cada salto é feito por um pedaço de código diferente: o primeiro pela ingestão Python, os demais pelo dbt. Os arquivos `schema.yml` não movem dados — declaram **testes e documentação** sobre cada modelo.

---

## O que este projeto demonstra

| Conceito | Onde ver |
|---|---|
| Fontes ≠ Bronze | `data/raw/` × `data/bronze/` |
| Ingestão absorve a diversidade das fontes | `src/ingest.py` (CSV × JSON) |
| Parquet: colunar, tipado, comprimido | `notebooks/exploracao.ipynb`, seção 2.1 |
| Bronze preserva — inclusive os defeitos | `data/bronze/` × modelos `stg_*` |
| Qualidade de dados como código | `dbt/models/*/schema.yml` |
| `source()` × `ref()` e a DAG | `sources.yml` + qualquer modelo Gold |
| Grão, medida e dimensão | `fato_chamado.sql` |
| Surrogate key (hash) × chave de negócio | `dim_unidade.sql` + `packages.yml` |
| Dimensão degenerada, conformada e role-playing | `fato_chamado.sql`, `dim_unidade.sql`, `dim_tempo.sql` |
| Integridade sem chave estrangeira | teste `relationships` em `gold/schema.yml` |
| O que a governança decide (e o SQL não) | `stg_categorias.sql` |
| Storage × engine | `external_location` em `sources.yml` |
| Quatro fontes, nenhuma chave entre elas | `consultas/dados_brutos.sql`, `docs/anomalias-das-fontes.md` |
| A mesma pergunta no OLTP × na Gold | `docs/comparacao-oltp-vs-gold.md` |

A consulta que fecha a jornada:

```sql
select
    c.nome_unidade,
    cl.nome_categoria,
    t.ano,
    round(avg(f.tempo_atendimento_dias), 1) as tempo_medio_dias
from 'data/gold/fato_chamado.parquet' f
join 'data/gold/dim_unidade.parquet' c  on f.unidade_sk = c.unidade_sk
join 'data/gold/dim_categoria.parquet'  cl on f.categoria_sk  = cl.categoria_sk
join 'data/gold/dim_tempo.parquet'   t  on f.data_abertura_sk = t.data_sk
where f.tempo_atendimento_dias is not null
group by 1, 2, 3;
```

---

## Como executar

Instalação, execução e a **ordem de leitura comentada** estão em **[`POC.md`](POC.md)**.

---

**Engenharia de Dados não existe apenas para mover arquivos ou alimentar dashboards.** Ela constrói e mantém a jornada necessária para transformar dados em informação confiável e utilizável.
