-- =====================================================================
-- GOLD | dim_categoria — DIMENSÃO
-- =====================================================================
-- Também conformed: servirá qualquer fato que precise da perspectiva
-- "categoria de chamado".
--
-- ⚠ Repare de onde ela vem: stg_categorias, que resolveu a duplicação
-- de categoria_id. Se aquele problema não tivesse sido tratado na
-- Silver, ele CONTAMINARIA esta dimensão — e o join com a fato
-- duplicaria linhas, inflando todas as contagens.
--
-- Moral: problema não tratado na Silver não fica na Silver.
-- =====================================================================

{{ config(location='../data/gold/dim_categoria.parquet') }}

select
    -- SK hash da chave de negócio — mesma técnica e mesmos motivos
    -- explicados em dim_unidade.sql.
    {{ dbt_utils.generate_surrogate_key(['categoria_id']) }} as categoria_sk,

    categoria_id,
    nome_categoria
from {{ ref('stg_categorias') }}
