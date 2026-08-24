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
    -- =================================================================
    -- SURROGATE KEY — a identidade que o WAREHOUSE dá à unidade
    -- =================================================================
    -- A chave de negócio (unidade_id) responde "quem é essa unidade?".
    -- A surrogate responde "qual VERSÃO dela, neste warehouse?" — e
    -- existe para: integrar várias fontes (dois sistemas com id = 3
    -- colidiriam), habilitar SCD Type 2 (versões da mesma unidade) e
    -- proteger o modelo de chaves recicladas na origem.
    --
    -- ⚠ Repare: NÃO é um contador sequencial. É um HASH determinístico
    -- da chave de negócio (md5, por baixo). Motivo: nosso pipeline é
    -- IDEMPOTENTE — cada dbt run reconstrói tudo, e um contador
    -- renumeraria as linhas a cada run. O hash sai IGUAL em qualquer
    -- run, em qualquer máquina.
    --
    -- generate_surrogate_key vem do pacote dbt_utils (packages.yml).
    {{ dbt_utils.generate_surrogate_key(['unidade_id']) }} as unidade_sk,

    unidade_id,        -- chave natural (veio da origem) — vira atributo
    nome_unidade,      -- já padronizado na Silver
    uf
from {{ ref('stg_unidades') }}

-- NOTA SOBRE MUDANÇA (SCD): esta dimensão é Type 1 — se a unidade mudar
-- de nome, o valor é sobrescrito e o histórico se perde. Para responder
-- "como se chamava a unidade NA ÉPOCA daquele chamado", seria preciso
-- SCD Type 2 (uma linha por versão, com vigência). No dbt isso se faz
-- com `dbt snapshot`.
