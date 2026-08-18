-- =====================================================================
-- SILVER | stg_interacoes
-- =====================================================================
-- Mesmos tratamentos das outras stg_ — mas repare numa coisa: este dado
-- veio de um JSON, e os outros vieram de CSV. Daqui para frente, isso
-- é INDIFERENTE.
--
-- Foi a camada de ingestão que absorveu a diferença entre os formatos
-- e entregou tudo como Parquet. É essa a função dela.
--
-- ⚠ GRÃO DIFERENTE: aqui uma linha é um EVENTO dentro de um chamado,
-- não um chamado. É por isso que este modelo NÃO entra na fato.
-- =====================================================================

{{ config(location='../data/silver/stg_interacoes.parquet') }}

with fonte as (

    select * from {{ source('bronze', 'interacoes') }}

)

-- DISTINCT: a origem trouxe 5 eventos integralmente duplicados.
select distinct
    try_cast(chamado_id as bigint) as chamado_id,
    tipo_interacao,

    -- o mesmo problema de formato de data das outras tabelas:
    -- a maioria em ISO, algumas em DD/MM/AAAA
    coalesce(
        try_cast(data_interacao as date),
        try_cast(try_strptime(data_interacao, '%d/%m/%Y') as date)
    ) as data_interacao

from fonte
