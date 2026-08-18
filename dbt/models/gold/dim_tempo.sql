-- =====================================================================
-- GOLD | dim_tempo — DIMENSÃO DE CALENDÁRIO
-- =====================================================================
-- POR QUE UMA DIMENSÃO SÓ PARA DATAS?
--
-- Sem ela, "por período" viraria extract(year from ...) repetido em
-- cada consulta. Com ela, ano/mês/trimestre são calculados UMA vez e
-- ficam prontos para agrupar — e, mais importante, todos usam a MESMA
-- definição (o que é "trimestre" para a organização?).
--
-- É também a dimensão conformed por excelência: qualquer fato com data
-- se conecta a ela.
--
-- ROLE-PLAYING: a fato usa esta dimensão em DOIS papéis —
-- data_abertura e data_fechamento. A mesma tabela, dois significados.
--
-- ⚠ Note que ela NÃO vem de nenhuma fonte: é GERADA. Uma dimensão de
-- calendário não existe em sistema transacional nenhum — ela é
-- construída pelo pipeline.
-- =====================================================================

{{ config(location='../data/gold/dim_tempo.parquet') }}

with datas as (

    -- calendário contínuo entre a menor e a maior data do fato.
    -- Precisa ser CONTÍNUO (todos os dias, inclusive os sem chamado),
    -- senão faltariam períodos nos relatórios.
    select
        cast(range as date) as data
    from range(
        (select min(data_abertura) from {{ ref('stg_chamados') }}),
        (select coalesce(max(data_fechamento), current_date) from {{ ref('stg_chamados') }}) + interval 1 day,
        interval 1 day
    )

)

select
    data,
    extract(year from data)   as ano,
    extract(month from data)  as mes,

    -- nome do mês em português: o DuckDB devolveria em inglês, e
    -- traduzir na camada de consumo seria repetir lógica em todo lugar
    (['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro']
    )[extract(month from data)] as nome_mes,

    quarter(data)              as trimestre,

    -- útil para análises de produtividade: isodow() devolve 1=segunda
    -- ... 7=domingo, então 6 e 7 são o fim de semana
    isodow(data) in (6, 7)     as fim_de_semana

from datas
