-- =====================================================================
-- GOLD | dim_uf — DIMENSÃO (Unidade da Federação -> Região)
-- =====================================================================
-- Dimensão é o CONTEXTO: quem, o quê, onde. Aqui, o "onde": a UF e a
-- macrorregião a que ela pertence. É por esta dimensão que a análise
-- consegue subir de município -> UF -> região (uma hierarquia).
--
-- CONFORMED DIMENSION: se surgir um segundo fato (ex.: IDEB por
-- município), ele usará ESTA MESMA dimensão — permitindo comparar
-- métricas pela mesma perspectiva geográfica (drill-across).
-- =====================================================================

{{ config(location='../data/gold/dim_uf.parquet') }}

select
    -- SURROGATE KEY por HASH determinístico (idempotente entre runs),
    -- não um contador sequencial que renumeraria a cada dbt run.
    {{ dbt_utils.generate_surrogate_key(['uf']) }} as uf_sk,

    uf,        -- chave natural (a sigla) — vira atributo
    regiao     -- macrorregião, já deduplicada na Silver
from {{ ref('stg_ufs') }}

-- NOTA SOBRE MUDANÇA (SCD): esta dimensão é Type 1. UF -> região é
-- praticamente estável; se mudasse, o valor seria sobrescrito. Para
-- guardar histórico ("a que região pertencia NA ÉPOCA"), usaria-se
-- SCD Type 2 (`dbt snapshot`).
