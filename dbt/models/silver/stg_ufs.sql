-- =====================================================================
-- SILVER | stg_ufs
-- =====================================================================
-- DEDUPLICAÇÃO COM DECISÃO DE NEGÓCIO: este é o modelo mais
-- interessante da camada, porque o SQL sozinho não resolve o problema.
-- =====================================================================

{{ config(location='../data/silver/stg_ufs.parquet') }}

with fonte as (

    select * from {{ ler_bronze('ufs') }}

),

classificada as (

    select
        upper(trim(uf)) as uf,
        trim(regiao)    as regiao,

        -- DEFEITO 7: a MESMA UF aparece duas vezes no JSON, com a região
        -- em grafias diferentes ("Norte" e "NORTE"). Se não tratarmos, a
        -- dim_uf fica com sigla duplicada e o join com a fato DUPLICA
        -- linhas (fan-out), inflando as contagens.
        --
        -- COMO FUNCIONA: row_number() numera as linhas dentro de cada UF
        -- (partition by), numa ordem que nós escolhemos (order by).
        -- Ficamos com a nº 1.
        --
        -- ⚠ A REGRA ESCOLHIDA: preferir a grafia que NÃO está toda em
        -- maiúsculas — porque preserva a capitalização correta do nome
        -- da região.
        --
        -- MAS ATENÇÃO: essa escolha é ARBITRÁRIA do time técnico. Numa
        -- organização real, "qual é o nome oficial da região?" é pergunta
        -- para o dono do dado (governança), não para quem escreve o SQL.
        -- (Ver DECISOES.md, decisão 3.)
        row_number() over (
            partition by upper(trim(uf))
            order by (regiao = upper(regiao)) asc   -- false<true: não-maiúsculas no topo
        ) as rn

    from fonte

)

select
    uf,
    regiao
from classificada
where rn = 1     -- fica só a linha escolhida por UF
