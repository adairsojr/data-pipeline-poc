-- =====================================================================
-- CONSULTAS DE ANÁLISE — o CONSUMO da camada Gold (INEP · evasão escolar)
-- =====================================================================
-- Execute um bloco por vez, da raiz do projeto:
--   python scripts/rodar_bloco.py analise 1
--   python scripts/rodar_bloco.py analise 2
--
-- Repare em TODAS as consultas: NENHUMA regra de negócio no WHERE.
-- A métrica derivada (abandono_combinado) já foi calculada e as decisões
-- (taxa >100, UF órfã, sem código) já foram tomadas no pipeline. Quem
-- consulta apenas JUNTA e AGRUPA — por isso qualquer ferramenta (SQL,
-- Power BI, Metabase) chega ao MESMO número.
-- =====================================================================


-- =====================================================================
-- 1) PERGUNTA 1 — evasão média por REGIÃO e por UF
--   "Qual é a taxa média de evasão escolar (abandono) dos municípios,
--    por REGIÃO e por UF?"
--
--   • métrica DERIVADA: abandono_combinado (média do abandono do
--     Fundamental e do Médio — não existe pronta na fonte, é calculada
--     na fato_taxa);
--   • 2 recortes: por REGIÃO e por UF (hierarquia geográfica).
-- =====================================================================
-- O star schema em ação: a fato no centro, a dim_uf dando o contexto
-- geográfico. O join usa a SURROGATE KEY.
select
    u.regiao,
    u.uf,
    count(*)                                 as municipios,
    round(avg(f.abandono_combinado), 2)      as evasao_media_pct,
    round(max(f.abandono_combinado), 2)      as evasao_max_pct
from 'data/gold/fato_taxa.parquet' f
join 'data/gold/dim_uf.parquet'    u on f.uf_sk = u.uf_sk
-- NÃO é regra de negócio: só ignora municípios sem métrica (a decisão de
-- deixá-los nulos foi tomada na Gold). Sem isso, a média nem existe.
where f.abandono_combinado is not null
group by 1, 2
order by u.regiao, evasao_media_pct desc;


-- =====================================================================
-- 2) PERGUNTA 2 — onde a evasão é maior: Fundamental x Médio, por região
--   "Comparando as etapas, a evasão é maior no Ensino FUNDAMENTAL ou no
--    MÉDIO — e como isso varia por REGIÃO?"
--
--   • 2 recortes: por ETAPA (fundamental/médio) e por REGIÃO;
--   • usa as taxas de origem lado a lado, revelando o "gap" entre etapas.
--   Ajuda o gestor a ver em QUE etapa e em QUE região concentrar política
--   de permanência escolar.
-- =====================================================================
select
    u.regiao,
    count(*)                                    as municipios,
    round(avg(f.taxa_abandono_fund), 2)         as evasao_fundamental_pct,
    round(avg(f.taxa_abandono_med), 2)          as evasao_medio_pct,
    round(avg(f.taxa_abandono_med)
        - avg(f.taxa_abandono_fund), 2)         as gap_medio_menos_fund
from 'data/gold/fato_taxa.parquet' f
join 'data/gold/dim_uf.parquet'    u on f.uf_sk = u.uf_sk
-- exclui as taxas implausíveis (>100) que a Gold já marcou; aqui apenas
-- filtramos o que não é medida válida — não é regra de negócio
where f.taxa_abandono_fund between 0 and 100
  and f.taxa_abandono_med  between 0 and 100
group by 1
order by evasao_medio_pct desc;
