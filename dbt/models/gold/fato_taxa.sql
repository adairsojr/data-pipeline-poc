-- =====================================================================
-- GOLD | fato_taxa — a TABELA FATO do modelo dimensional
-- =====================================================================
-- GRÃO: uma linha = um MUNICÍPIO (no ano de 2023, recorte Localização =
-- Total e Dependência = Total). Declarado antes de tudo, porque é a
-- decisão mais importante da modelagem dimensional.
--
-- O QUE FICOU DE FORA DO GRÃO: as quebras por Localização (Urbana/Rural)
-- e por Dependência (Federal/Estadual/Municipal/Privada) que a base do
-- INEP também traz. Ficamos com os totais por município — o recorte foi
-- feito na geração das fontes e está documentado no PROCESSO.md.
--
-- ANATOMIA DE UMA FATO — três tipos de coluna:
--   1. chaves para as dimensões (uf_sk)
--   2. dimensão degenerada (codigo_municipio, nome_municipio, ano)
--   3. MEDIDAS (taxas + a métrica DERIVADA abandono_combinado)
-- =====================================================================

{{ config(location='../data/gold/fato_taxa.parquet') }}

with taxas as (

    -- ref() declara a dependência: só constrói DEPOIS de stg_taxas.
    -- O dbt deduz essa ordem dos ref() e monta a DAG sozinho.
    select * from {{ ref('stg_taxas') }}

)

select
    -- SURROGATE KEY por HASH determinístico da UF. Aplicando a MESMA
    -- função sobre a MESMA chave de negócio, bate com a dim_uf.
    -- (O teste `relationships` no schema.yml confere.)
    {{ dbt_utils.generate_surrogate_key(['t.uf']) }} as uf_sk,   -- FK -> dim_uf

    -- DIMENSÕES DEGENERADAS: identificam a linha, mas não têm dimensão
    -- própria (código e nome do município, ano). O código já é único e
    -- legível — um hash dele seria a mesma informação duas vezes.
    t.codigo_municipio,
    t.nome_municipio,
    t.ano,

    -- MEDIDAS que vieram da fonte (aditivas por município):
    t.taxa_aprovacao_fund,
    t.taxa_reprovacao_fund,
    t.taxa_abandono_fund,
    t.taxa_abandono_med,

    -- =================================================================
    -- A MÉTRICA DERIVADA — o número que NÃO existe em fonte nenhuma
    -- =================================================================
    -- O INEP entrega o abandono do FUNDAMENTAL e do MÉDIO SEPARADOS.
    -- "abandono_combinado" é a média das duas etapas — uma visão única
    -- de evasão por município, calculada AQUI, no pipeline. É a métrica
    -- derivada da PoC: "dado" (duas taxas) vira "informação" (evasão do
    -- município).
    --
    -- Duas decisões de negócio embutidas:
    -- 1) DEFEITO 4 — taxa de abandono IMPLAUSÍVEL (>100): é dado inválido
    --    vindo da origem. Protegemos a métrica derivada zerando essas
    --    entradas para NULL antes de combinar (a taxa individual continua
    --    visível na fato, mas não contamina o combinado).
    -- 2) quando falta uma das etapas, a média usa a que existe (coalesce).
    --
    -- ⚠ Guardamos a métrica POR MUNICÍPIO e não a média já agregada,
    -- porque MÉDIA NÃO É ADITIVA: média de médias não é a média.
    -- Guardando no grão, dá para agregar por UF, região etc. depois.
    (
        coalesce(case when t.taxa_abandono_fund between 0 and 100 then t.taxa_abandono_fund end, 0)
      + coalesce(case when t.taxa_abandono_med  between 0 and 100 then t.taxa_abandono_med  end, 0)
    )
    / nullif(
        (case when t.taxa_abandono_fund between 0 and 100 then 1 else 0 end)
      + (case when t.taxa_abandono_med  between 0 and 100 then 1 else 0 end)
      , 0)                                              as abandono_combinado

from taxas t

-- INTEGRIDADE REFERENCIAL: o DEFEITO 3 é um município com UF inexistente
-- no cadastro (uf = 'ZZ'). Em banco relacional a FK impediria; em
-- Delta/Parquet não há FK, então a proteção vira código (este filtro)
-- mais um TESTE `relationships` que acusa (ver gold/schema.yml).
--
-- ⚠ ALTERNATIVA MAIS MADURA: apontar para uma linha "Não informado"
-- (sk = 0) em vez de descartar. Ver DECISOES.md, decisão 4.
where t.uf in (select uf from {{ ref('stg_ufs') }})
