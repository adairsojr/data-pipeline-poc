-- =====================================================================
-- SILVER | stg_categorias
-- =====================================================================
-- DEDUPLICAÇÃO COM DECISÃO DE NEGÓCIO: este é o modelo mais
-- interessante da camada, porque o SQL sozinho não resolve o problema.
-- =====================================================================

{{ config(location='../data/silver/stg_categorias.parquet') }}

with fonte as (

    select * from {{ source('bronze', 'categorias') }}

),

classificada as (

    select
        cast(categoria_id as integer) as categoria_id,
        nome_categoria,

        -- PROBLEMA: o MESMO categoria_id (2) aparece duas vezes na origem,
        -- com grafias diferentes: "Rede e Internet" e "REDE E INTERNET".
        -- Se não tratarmos, a dim_categoria fica com id duplicado e o join
        -- com a fato DUPLICA linhas (fan-out) — inflando as contagens.
        --
        -- COMO FUNCIONA: row_number() numera as linhas dentro de cada
        -- categoria_id (partition by), numa ordem que nós escolhemos
        -- (order by). Ficamos com a nº 1.
        --
        -- ⚠ A REGRA ESCOLHIDA AQUI: preferir a grafia que NÃO está toda
        -- em maiúsculas — porque "Rede e Internet" preserva acentuação
        -- e capitalização corretas.
        --
        -- MAS ATENÇÃO: essa é uma decisão ARBITRÁRIA que EU tomei.
        -- Numa organização real, "qual é o nome oficial da categoria?"
        -- é uma pergunta para quem é DONO desse dado — não para quem
        -- escreve o SQL. Este é o momento em que a governança aparece
        -- dentro de um modelo dbt.
        row_number() over (
            partition by cast(categoria_id as integer)
            order by (nome_categoria = upper(nome_categoria)) asc
        ) as rn

    from fonte

)

select
    categoria_id,
    nome_categoria
from classificada
where rn = 1     -- fica só a linha escolhida por categoria_id
