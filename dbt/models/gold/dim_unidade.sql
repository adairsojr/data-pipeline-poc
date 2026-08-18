-- =====================================================================
-- GOLD | dim_unidade — DIMENSÃO
-- =====================================================================
-- Dimensão é o CONTEXTO: quem, o quê, onde. Guarda atributos
-- descritivos (os nomes que aparecem no relatório) e hierarquias.
--
-- Esta é uma CONFORMED DIMENSION: quando existir um fato de interações
-- ou de pesquisas de satisfação, ele usará ESTA MESMA dimensão.
-- É isso que permite comparar métricas de fatos diferentes pela mesma
-- perspectiva (drill-across) — e é o conceito mais valioso da
-- modelagem dimensional.
--
-- Repare que ela é pequena e "larga": poucas linhas, colunas
-- descritivas. O oposto da fato, que é estreita e alta.
-- =====================================================================

{{ config(location='../data/gold/dim_unidade.parquet') }}

select
    unidade_id,        -- chave natural (veio da origem)
    nome_unidade,      -- já padronizado na Silver
    uf
from {{ ref('stg_unidades') }}

-- NOTA SOBRE MUDANÇA (SCD): esta dimensão é Type 1 — se a unidade mudar
-- de nome, o valor é sobrescrito e o histórico se perde. Para responder
-- "como se chamava a unidade NA ÉPOCA daquele chamado", seria preciso
-- SCD Type 2 (uma linha por versão, com vigência). No dbt isso se faz
-- com `dbt snapshot`.
