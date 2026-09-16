# Anomalias das fontes (defeitos plantados)

As duas fontes em `data/raw/` foram geradas a partir dos dados **reais** do INEP
(Taxas de Rendimento Escolar por município, 2023) e depois **contaminadas de
propósito** com problemas de qualidade típicos de um *export* de sistema. É a
existência desses defeitos que justifica a camada Silver.

O gerador é `scripts/gerar_fontes.py` (semente fixa: reprodutível). A origem dos
dados e o passo a passo estão no [`PROCESSO.md`](../PROCESSO.md).

## As fontes

| Arquivo | Formato | Grão (o que é uma linha) | Vira |
|---|---|---|---|
| `taxas_municipios.csv` | CSV | um município (taxas 2023) | a tabela fato |
| `ufs.json` | JSON | uma UF (sigla → região) | dimensão |

## Os defeitos

| # | Defeito | Onde | Tratamento | Onde é tratado |
|---|---|---|---|---|
| 1 | taxa com **vírgula** decimal (`1,2`) em vez de ponto (2 linhas) | taxas | `replace(',', '.')` antes de tipar | `stg_taxas.sql` |
| 2 | `uf` com grafia inconsistente (minúscula, espaços) (3 linhas) | taxas | `upper(trim(...))` | `stg_taxas.sql` |
| 3 | `uf = 'ZZ'` — UF inexistente no cadastro (1 linha) | taxas | filtro na fato + teste `relationships` | `fato_taxa.sql`, `gold/schema.yml` |
| 4 | taxa de abandono **implausível** (`150.0`, > 100) (1 linha) | taxas | valor neutralizado na métrica derivada | `fato_taxa.sql` |
| 5 | `codigo_municipio` vazio — registro sem chave (1 linha) | taxas | descartado (`where codigo_municipio is not null`) | `stg_taxas.sql` |
| 6 | duas linhas **integralmente duplicadas** | taxas | `select distinct` | `stg_taxas.sql` |
| 7 | UF repetida no JSON (mesma sigla, região em outra grafia) | ufs | dedup por `row_number()` com decisão de negócio | `stg_ufs.sql` |

## Por que cada tratamento fica onde fica

- **Vírgula decimal, grafia de UF, deduplicação (defeitos 1, 2, 6, 7):** são
  **limpeza e padronização** → camada **Silver** (`stg_*`).
- **Registro sem chave (defeito 5):** também Silver — sem identidade, o registro não
  segue.
- **Integridade referencial e taxa implausível (defeitos 3, 4):** aparecem na
  construção do **modelo dimensional** → camada **Gold** (`fato_taxa`), porque
  dependem do relacionamento entre fato e dimensão e do cálculo da métrica derivada.

Nenhum defeito é tratado na **ingestão**: o Bronze **preserva o bruto como veio**
(inclusive os defeitos). Essa é a regra da camada de preservação — e o que permite
reprocessar tudo e usar o time travel do Delta para auditar.

> As decisões de governança (o dado ambíguo e o registro inválido) estão em
> [`../DECISOES.md`](../DECISOES.md), decisões 3 e 4.
