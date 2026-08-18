-- =====================================================================
-- SILVER | stg_chamados
-- =====================================================================
-- O QUE ESTA CAMADA FAZ: pega o dado como ele chegou (Bronze, tudo texto)
-- e o torna CONFIÁVEL: tipado, limpo, deduplicado.
--
-- "stg_" é convenção do dbt para modelo de PREPARAÇÃO LÓGICA.
-- Não confundir com a staging area FÍSICA do ETL clássico: lá era um
-- lugar (uma área do banco); aqui é uma transformação declarada em SQL.
-- =====================================================================

{{ config(location='../data/silver/stg_chamados.parquet') }}

with fonte as (

    -- source() = a porta de entrada do dado no domínio do dbt.
    -- Do lado de fora dela está a ingestão em Python; daqui para
    -- frente, tudo é transformação declarativa.
    select * from {{ source('bronze', 'chamados') }}

),

convertida as (

    -- DISTINCT resolve o PROBLEMA 1: a origem trouxe duas linhas
    -- integralmente duplicadas (o mesmo chamado repetido no fim do
    -- arquivo, como se o export tivesse sido concatenado duas vezes).
    -- Repare que isso só funciona para duplicata INTEGRAL. Se fossem
    -- duas linhas com o mesmo id e dados diferentes, seria preciso
    -- decidir qual vale — e isso é decisão de negócio, não de SQL.
    select distinct

        -- TIPAGEM: no Bronze tudo é texto, porque tipar é interpretar,
        -- e interpretar é transformar. É aqui que a interpretação acontece.
        try_cast(chamado_id   as bigint)  as chamado_id,
        try_cast(categoria_id as integer) as categoria_id,
        try_cast(unidade_id   as integer) as unidade_id,
        try_cast(equipe_id    as integer) as equipe_id,

        -- PROBLEMA 2: a origem mistura DOIS formatos de data.
        -- A maioria vem como AAAA-MM-DD, mas algumas vêm como DD/MM/AAAA.
        -- O try_cast sozinho transformaria essas últimas em NULL —
        -- silenciosamente. O coalesce tenta o segundo formato:
        --   1º tenta o padrão ISO
        --   2º tenta o formato brasileiro
        -- Usamos try_* (e não cast direto) para que uma data impossível
        -- vire NULL em vez de derrubar o pipeline inteiro.
        coalesce(
            try_cast(data_abertura as date),
            try_cast(try_strptime(data_abertura, '%d/%m/%Y') as date)
        ) as data_abertura,

        coalesce(
            try_cast(data_fechamento as date),
            try_cast(try_strptime(data_fechamento, '%d/%m/%Y') as date)
        ) as data_fechamento,

        situacao

    from fonte

)

select *
from convertida

-- PROBLEMA 3: um registro veio sem identificador.
-- DECISÃO DE QUALIDADE: registro sem chave não segue no pipeline.
-- ⚠ Em produção, o correto seria mandá-lo para uma área de QUARENTENA
-- e notificar a origem — nunca descartar em silêncio. Aqui filtramos
-- para manter a PoC simples, mas a discussão é importante:
-- quem decide o que fazer com dado inválido? (governança)
where chamado_id is not null
