-- =====================================================================
-- SILVER | stg_unidades
-- =====================================================================
-- PADRONIZAÇÃO: o mesmo nome de unidade chega escrito de várias formas.
-- Este modelo mostra por que "limpar" não é só tipar — é uniformizar
-- o significado.
-- =====================================================================

{{ config(location='../data/silver/stg_unidades.parquet') }}

with fonte as (

    select * from {{ source('bronze', 'unidades') }}

)

select
    cast(unidade_id as integer) as unidade_id,

    -- PROBLEMA: a origem traz "dourados", "TRÊS LAGOAS", "  Aquidauana"
    -- e "Naviraí " — caixa e espaços inconsistentes. Sem tratamento,
    -- o relatório final exibe os nomes sujos, e um GROUP BY por nome
    -- separaria "Dourados" de "dourados" como se fossem duas unidades.
    --
    -- COMO FUNCIONA (o DuckDB não tem a função initcap):
    --   1. lower(trim(...))  -> tudo minúsculo, sem espaços nas pontas
    --   2. string_split       -> quebra a frase em palavras
    --   3. list_transform     -> para cada palavra, sobe a 1ª letra
    --                            (w[1] é a inicial; w[2:] é o resto)
    --   4. array_to_string    -> recompõe a frase
    -- Resultado: "  TRÊS LAGOAS" -> "Três Lagoas"
    array_to_string(
        list_transform(
            string_split(lower(trim(nome_unidade)), ' '),
            w -> upper(w[1]) || w[2:]
        ),
        ' '
    ) as nome_unidade,

    upper(trim(uf)) as uf

from fonte
