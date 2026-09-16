-- =====================================================================
-- SILVER | stg_taxas
-- =====================================================================
-- O QUE ESTA CAMADA FAZ: pega o dado como ele chegou (Bronze Delta,
-- tudo texto) e o torna CONFIÁVEL: tipado, limpo, deduplicado e
-- padronizado. NÃO calcula métrica derivada nem modela — isso é da Gold.
--
-- "stg_" é convenção do dbt para modelo de PREPARAÇÃO LÓGICA.
-- Não confundir com a staging area FÍSICA do ETL clássico: lá era um
-- lugar (uma área do banco); aqui é uma transformação declarada em SQL.
-- =====================================================================

{{ config(location='../data/silver/stg_taxas.parquet') }}

with fonte as (

    -- O Bronze é DELTA LAKE. Lemos a VERSÃO ATUAL via delta_scan
    -- (macro ler_bronze). Do lado de fora desta porta está a ingestão em
    -- Python; daqui para frente, tudo é transformação declarativa.
    select * from {{ ler_bronze('taxas') }}

),

convertida as (

    -- DISTINCT resolve o DEFEITO 6: a origem trouxe duas linhas
    -- integralmente duplicadas (export concatenado duas vezes). Só
    -- funciona para duplicata INTEGRAL — se fossem linhas com o mesmo
    -- município e valores diferentes, seria preciso decidir qual vale
    -- (decisão de negócio, não de SQL).
    select distinct

        -- TIPAGEM: no Bronze tudo é texto. Tipar é interpretar, e
        -- interpretar é transformar — é aqui que isso acontece.
        try_cast(ano as integer)              as ano,
        try_cast(codigo_municipio as bigint)  as codigo_municipio,
        nome_municipio,

        -- DEFEITO 2: UF com grafia inconsistente (minúscula, espaços).
        -- Padronizamos: sem espaços nas bordas e em CAIXA ALTA (padrão de
        -- sigla). Assim "sp", " SP" e "SP " viram a MESMA UF no group by.
        upper(trim(uf))                       as uf,

        -- DEFEITO 1: algumas taxas vieram com VÍRGULA decimal ("1,2") em
        -- vez de ponto ("1.2"). Trocamos a vírgula por ponto ANTES de
        -- tipar, senão o try_cast devolveria NULL silenciosamente.
        -- A origem do INEP usa ponto; a vírgula é um defeito de export.
        try_cast(replace(taxa_aprovacao_fund,  ',', '.') as double) as taxa_aprovacao_fund,
        try_cast(replace(taxa_reprovacao_fund, ',', '.') as double) as taxa_reprovacao_fund,
        try_cast(replace(taxa_abandono_fund,   ',', '.') as double) as taxa_abandono_fund,
        try_cast(replace(taxa_abandono_med,    ',', '.') as double) as taxa_abandono_med

    from fonte

)

select *
from convertida

-- DEFEITO 5: um registro veio sem código de município (vazio -> NULL no
-- try_cast). DECISÃO DE QUALIDADE: registro sem chave não segue no
-- pipeline.
-- ⚠ Em produção, o correto seria QUARENTENA + notificar a origem, nunca
-- descartar em silêncio. Aqui filtramos para manter a PoC simples, mas a
-- discussão está no DECISOES.md (decisão 4).
where codigo_municipio is not null
