-- =====================================================================
-- A MESMA PERGUNTA, LIDA DIRETO DAS FONTES (CSV / JSON)
-- =====================================================================
-- "Dá para trocar o .parquet por .csv?"
--
-- Sintaticamente, SIM: o DuckDB lê CSV, JSON e Parquet com a mesma
-- cláusula `from '<arquivo>'`. Nada muda no SQL.
--
-- Semanticamente, NÃO: a consulta da Gold não sobrevive à troca. Ela
-- fala de `unidade_sk`, `data_abertura_sk`, `ano`, `tempo_atendimento_dias`
-- — e nenhuma dessas colunas existe nas fontes. Elas foram CRIADAS pelo
-- pipeline.
--
-- Estes 4 blocos mostram o que acontece quando se tenta mesmo assim.
-- Rodar da raiz do projeto:
--     python scripts/rodar_bloco.py fontes 1
-- =====================================================================


-- =====================================================================
-- 1) A troca ingenua: so mudar o nome do arquivo (NAO RODA)
-- =====================================================================
-- Resultado: NÃO RODA. Erro de conversão na primeira linha em DD/MM/AAAA.
--
--   Conversion Error: invalid date field format: "11/03/2024",
--   expected format is (YYYY-MM-DD)
--
-- É o melhor dos casos: o erro apareceu. Compare com o bloco 2.
select
    u.nome_unidade,
    cat.nome_categoria,
    year(cast(c.data_abertura as date))      as ano,
    count(*)                                 as chamados_resolvidos,
    round(avg(date_diff('day',
        cast(c.data_abertura  as date),
        cast(c.data_fechamento as date))), 1) as tempo_medio_dias
from 'data/raw/chamados.csv'   c
join 'data/raw/unidades.csv'   u   on c.unidade_id   = u.unidade_id
join 'data/raw/categorias.csv' cat on c.categoria_id = cat.categoria_id
where c.data_fechamento is not null
  and year(cast(c.data_abertura as date)) = 2025
group by 1, 2, 3
order by 5 desc;


-- =====================================================================
-- 2) A troca ingenua 'consertada' com try_cast (RODA, e erra)
-- =====================================================================
-- Agora RODA. E é por isso que é perigosa.
--
-- Resultado: 33 linhas · 39 chamados
-- (o certo é 27 linhas · 31 chamados — bloco 3)
--
-- O que aconteceu, linha a linha do resultado:
--   • "Rede e Internet" E "REDE E INTERNET" aparecem SEPARADAS
--     -> o categoria_id 2 está duplicado no cadastro: cada chamado
--        de rede foi CONTADO DUAS VEZES (fan-out no join)
--   • "dourados", "TRÊS LAGOAS", "Naviraí " com a grafia da origem
--     -> num relatório viram unidades diferentes das outras
--   • os chamados com data em DD/MM/AAAA sumiram, EM SILÊNCIO
--     -> try_cast devolveu NULL e o `year(...) = 2025` os descartou
--   • o chamado 500103 (fecha antes de abrir) entrou com tempo NEGATIVO
--   • as duplicatas integrais 500025 e 500117 entraram duas vezes
--   • o chamado da unidade 99 sumiu no join, sem ninguém avisar
select
    u.nome_unidade,
    cat.nome_categoria,
    year(try_cast(c.data_abertura as date))  as ano,
    count(*)                                 as chamados_resolvidos,
    round(avg(date_diff('day',
        try_cast(c.data_abertura  as date),
        try_cast(c.data_fechamento as date))), 1) as tempo_medio_dias
from 'data/raw/chamados.csv'   c
join 'data/raw/unidades.csv'   u   on c.unidade_id   = u.unidade_id
join 'data/raw/categorias.csv' cat on c.categoria_id = cat.categoria_id
where c.data_fechamento is not null
  and year(try_cast(c.data_abertura as date)) = 2025
group by 1, 2, 3
order by 5 desc;


-- =====================================================================
-- 3) A versao HONESTA sobre as fontes (o pipeline dentro da query)
-- =====================================================================
-- Mesmo número da Gold: 27 linhas · 31 chamados.
-- Campo Grande · Rede e Internet · 2025 -> 10 dias.
--
-- ⚠ ESTE É O PONTO DA AULA: para chegar ao número certo lendo as fontes,
-- foi preciso reescrever o pipeline INTEIRO dentro da consulta —
-- 5 CTEs, 40 linhas. E isso para UMA pergunta, UM ano.
--
-- Cada CTE abaixo é um modelo dbt que já existe no projeto:
--     chamados        -> stg_chamados   (o `select distinct`)
--     chamados_limpos -> stg_chamados   (o coalesce das datas, o not null)
--     categorias      -> stg_categorias (o row_number da deduplicação)
--     unidades        -> stg_unidades   (o trim + capitalização)
--     os dois filtros do `where` -> fato_chamado
--
-- A pergunta seguinte ("e por unidade, sem categoria?") obriga a copiar
-- tudo de novo. A décima pergunta já tem dez cópias divergentes.
-- A Gold existe para que essa reconstrução aconteça UMA vez, versionada
-- e testada — e não dentro de cada consulta.
with chamados as (
    -- stg_chamados: remove as 2 duplicatas integrais (500025, 500117)
    select distinct * from 'data/raw/chamados.csv'
),
chamados_limpos as (
    -- stg_chamados: os dois formatos de data + o registro sem id
    select
        chamado_id,
        categoria_id,
        unidade_id,
        coalesce(try_cast(data_abertura as date),
                 try_strptime(data_abertura,  '%d/%m/%Y')::date) as data_abertura,
        coalesce(try_cast(data_fechamento as date),
                 try_strptime(data_fechamento, '%d/%m/%Y')::date) as data_fechamento
    from chamados
    where chamado_id is not null
),
categorias as (
    -- stg_categorias: o categoria_id 2 está repetido; fica a grafia
    -- que NÃO está toda em maiúscula. Decisão de GOVERNANÇA, não de SQL.
    select categoria_id, nome_categoria
    from (
        select *,
               row_number() over (
                   partition by categoria_id
                   order by (nome_categoria = upper(nome_categoria))
               ) as rn
        from 'data/raw/categorias.csv'
    )
    where rn = 1
),
unidades as (
    -- stg_unidades: "  TRÊS LAGOAS" e "dourados" viram "Três Lagoas"
    -- e "Dourados"
    select
        unidade_id,
        array_to_string(
            list_transform(string_split(lower(trim(nome_unidade)), ' '),
                           w -> upper(w[1]) || w[2:]),
            ' '
        ) as nome_unidade
    from 'data/raw/unidades.csv'
)
select
    u.nome_unidade,
    cat.nome_categoria,
    year(c.data_abertura)                    as ano,
    count(*)                                 as chamados_resolvidos,
    round(avg(date_diff('day', c.data_abertura, c.data_fechamento)), 1) as tempo_medio_dias
from chamados_limpos c
join unidades   u   on c.unidade_id   = u.unidade_id   -- descarta a unidade 99
join categorias cat on c.categoria_id = cat.categoria_id
where c.data_fechamento is not null
  and date_diff('day', c.data_abertura, c.data_fechamento) >= 0  -- descarta o 500103
  and year(c.data_abertura) = 2025
group by 1, 2, 3
order by 5 desc;


-- =====================================================================
-- 4) E o JSON? A mesma sintaxe.
-- =====================================================================
-- O DuckDB não pede nada de especial: CSV, JSON e Parquet entram no
-- `from` do mesmo jeito. A ingestão absorveu o formato — e é por isso
-- que nenhum modelo dbt do projeto precisa saber de onde o dado veio.
select
    'csv     · chamados'   as fonte, count(*) as linhas from 'data/raw/chamados.csv'
union all select
    'csv     · unidades',        count(*) from 'data/raw/unidades.csv'
union all select
    'csv     · categorias',      count(*) from 'data/raw/categorias.csv'
union all select
    'json    · interacoes',      count(*) from 'data/raw/interacoes.json'
union all select
    'parquet · bronze/chamados', count(*) from 'data/bronze/chamados.parquet';
