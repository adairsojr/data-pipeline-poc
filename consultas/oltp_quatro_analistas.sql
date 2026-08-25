-- =====================================================================
-- SLIDE 4 — "Então por que não fazemos simplesmente um AVG no OLTP?"
-- =====================================================================
-- Este arquivo REPRODUZ AO VIVO o slide dos quatro analistas.
--
-- PRÉ-REQUISITOS (uma vez, da raiz do projeto):
--     python -m src.pipeline                     # Bronze
--     cd dbt && dbt build && cd ..               # Silver + Gold
--     python scripts/criar_oltp_simulado.py      # o OLTP simulado
--
-- COMO EXECUTAR — sempre a partir da RAIZ do projeto (os caminhos dos
-- Parquet são relativos):
--
--   Opção 1 (terminal, tudo de uma vez):
--     duckdb data/chamados_oltp.duckdb < consultas/oltp_quatro_analistas.sql
--
--   Opção 2 (terminal interativo, roda bloco a bloco):
--     duckdb data/chamados_oltp.duckdb
--     .read consultas/oltp_quatro_analistas.sql
--
--   Opção 3 (DBeaver — RECOMENDADO para a aula):
--     conexão DuckDB apontando para data/chamados_oltp.duckdb
--     ⚠ antes de rodar, execute UMA vez:
--         SET file_search_path='/Users/vanessaborges/dev_repo/poc-residencia/data-pipeline-poc';
--     (sem isso, o DBeaver não acha os Parquet dos caminhos relativos)
--
--   Opção 4 (Python, sem instalar o CLI do DuckDB) — roda um bloco por
--   vez; troque o número do bloco no final:
--     python scripts/rodar_bloco.py 3
--
-- ⚠ O .duckdb aceita UM escritor por vez: feche o DBeaver antes de
--   rodar pelo terminal (e vice-versa).
-- =====================================================================


-- =====================================================================
-- 1) A CONSULTA DO SLIDE — a versão do analista A, no OLTP
-- =====================================================================
-- É esta a consulta desenhada no slide. Repare no tamanho: 5 tabelas,
-- 4 joins e 1 CTE para responder "tempo médio de atendimento".
--
-- O motivo do CTE: no OLTP NÃO EXISTE uma coluna data_fechamento.
-- O fechamento é um EVENTO na tabela de interações, como qualquer
-- outro andamento do chamado. Para saber quando o chamado fechou é
-- preciso ir buscar a interação do tipo 'Encerramento'.

with fechamento as (
    -- min() e não max(): se o chamado foi REABERTO, existe mais de um
    -- encerramento. Escolhemos o primeiro — e essa é a decisão nº 2.
    select
        i.chamado_id,
        min(i.data_interacao) as data_fechamento
    from interacao i
    join tipo_interacao ti on ti.tipo_interacao_id = i.tipo_interacao_id
    where ti.descricao = 'Encerramento'
    group by i.chamado_id
)
select
    u.nome_unidade,
    e.nome_equipe,
    count(*)                                                            as chamados_resolvidos,
    round(avg(date_diff('day', c.data_abertura, f.data_fechamento)), 1) as tempo_medio_dias
from chamado c
join equipe     e on e.equipe_id  = c.equipe_id
join unidade    u on u.unidade_id = e.unidade_id   -- a unidade vem VIA equipe
join fechamento f on f.chamado_id = c.chamado_id
where c.data_abertura is not null
  and f.data_fechamento >= c.data_abertura         -- descarta data implausível
group by 1, 2
having count(*) >= 3                               -- mínimo de casos
order by tempo_medio_dias desc;


-- =====================================================================
-- 2) A MÉDIA GERAL, NO OLTP  ->  esperado: 10,8 dias em 94 chamados
-- =====================================================================

with fechamento as (
    select i.chamado_id, min(i.data_interacao) as data_fechamento
    from interacao i
    join tipo_interacao ti on ti.tipo_interacao_id = i.tipo_interacao_id
    where ti.descricao = 'Encerramento'
    group by i.chamado_id
)
select
    round(avg(date_diff('day', c.data_abertura, f.data_fechamento)), 1) as tempo_medio_dias,
    count(*)                                                            as chamados
from chamado c
join equipe     e on e.equipe_id  = c.equipe_id
join unidade    u on u.unidade_id = e.unidade_id
join fechamento f on f.chamado_id = c.chamado_id
where c.data_abertura is not null
  and f.data_fechamento >= c.data_abertura;


-- =====================================================================
-- 3) ⭐ OS QUATRO ANALISTAS, LADO A LADO
-- =====================================================================
-- Uma única consulta reproduz a tabela do slide.
--
-- Cada analista muda EXATAMENTE UMA decisão em relação ao A. Nenhum
-- escreveu SQL errado — todos rodam e parecem corretos.
--
-- Aqui usamos as camadas do pipeline (Bronze e Silver) em vez do OLTP,
-- porque é nelas que cada decisão fica visível isoladamente. A camada
-- Silver já resolveu as datas em formatos misturados e as duplicatas;
-- a Bronze preservou tudo como veio.

with silver as (
    select * from 'data/silver/stg_chamados.parquet'
),

-- a Bronze crua: 122 linhas, com duplicatas, e as datas ainda em texto
bronze as (
    select
        try_cast(chamado_id   as bigint)  as chamado_id,
        try_cast(categoria_id as integer) as categoria_id,
        try_cast(unidade_id   as integer) as unidade_id,
        coalesce(try_cast(data_abertura   as date),
                 try_cast(try_strptime(data_abertura,   '%d/%m/%Y') as date)) as data_abertura,
        coalesce(try_cast(data_fechamento as date),
                 try_cast(try_strptime(data_fechamento, '%d/%m/%Y') as date)) as data_fechamento
    from 'data/bronze/chamados.parquet'
),

analista_a as (
    -- A REGRA OFICIAL: exclui em andamento, tempo negativo e unidade inválida
    select round(avg(date_diff('day', data_abertura, data_fechamento)), 1) as media,
           count(*) as n
    from silver
    where data_fechamento is not null
      and data_fechamento >= data_abertura
      and unidade_id in (select unidade_id from 'data/silver/stg_unidades.parquet')
),

analista_b as (
    -- ESQUECEU DE FILTRAR A UNIDADE INEXISTENTE (unidade_id = 99)
    -- Um único chamado órfão, muito demorado, puxa a média para cima.
    select round(avg(date_diff('day', data_abertura, data_fechamento)), 1), count(*)
    from silver
    where data_fechamento is not null
      and data_fechamento >= data_abertura
),

analista_c as (
    -- CONSULTOU OS DADOS BRUTOS, SEM REMOVER DUPLICATAS
    -- Foi direto na Bronze: as 2 linhas duplicadas contam duas vezes,
    -- e nenhum dos outros cuidados foi aplicado.
    select round(avg(date_diff('day', data_abertura, data_fechamento)), 1), count(*)
    from bronze
    where data_fechamento is not null
),

analista_d as (
    -- ESQUECEU DE DESCARTAR O TEMPO NEGATIVO
    -- Um chamado com fechamento ANTES da abertura entra na média com
    -- valor negativo e puxa o número para baixo.
    select round(avg(date_diff('day', data_abertura, data_fechamento)), 1), count(*)
    from silver
    where data_fechamento is not null
      and unidade_id in (select unidade_id from 'data/silver/stg_unidades.parquet')
)

select 'A' as analista, 'seguiu a regra oficial'                    as decisao, * from analista_a
union all
select 'B', 'esqueceu de filtrar a unidade inexistente',            * from analista_b
union all
select 'C', 'consultou os dados brutos, sem remover duplicatas',    * from analista_c
union all
select 'D', 'esqueceu de descartar o tempo negativo',               * from analista_d
order by analista;

-- RESULTADO ESPERADO (é a tabela do slide):
--   A | seguiu a regra oficial                              | 10.8 |  94
--   B | esqueceu de filtrar a unidade inexistente           | 11.2 |  95
--   C | consultou os dados brutos, sem remover duplicatas   | 11.3 |  99
--   D | esqueceu de descartar o tempo negativo              | 10.5 |  95
--
-- 💬 A FRASE: "a diferença entre A e D é de MEIO DIA. É isso que a
--    torna perigosa: ninguém desconfia de 10,5 contra 10,8."


-- =====================================================================
-- 4) O IMPACTO PRÁTICO — quando o ranking MUDA
-- =====================================================================
-- A média geral quase não se move. O RANKING, sim.
-- Um único registro com tempo negativo derruba Ponta Porã de 13,3 para
-- 10,9 e a faz TROCAR DE POSIÇÃO com Três Lagoas.

select
    u.nome_unidade,
    round(avg(case when c.data_fechamento >= c.data_abertura
                   then date_diff('day', c.data_abertura, c.data_fechamento)
              end), 1)                                              as regra_oficial_A,
    round(avg(date_diff('day', c.data_abertura, c.data_fechamento)), 1) as versao_D_sem_filtro
from 'data/silver/stg_chamados.parquet' c
join 'data/silver/stg_unidades.parquet' u on u.unidade_id = c.unidade_id
where c.data_fechamento is not null
group by 1
order by regra_oficial_A desc;

-- RESULTADO ESPERADO:
--   Aquidauana    19,9 | 19,9
--   Dourados      15,1 | 15,1
--   Ponta Porã    13,3 | 10,9   <- cai 2,4 dias
--   Três Lagoas   11,3 | 11,3   <- e passa Ponta Porã
--   Naviraí        9,1 |  9,1
--   Corumbá        7,8 |  7,8
--   Campo Grande   6,8 |  6,8
--   Coxim          4,8 |  4,8
--
-- 💬 "Se esse ranking embasar uma decisão de gestão — alocar equipe,
--    priorizar unidade — a decisão MUDA por causa de uma escolha
--    técnica que ninguém percebeu."


-- =====================================================================
-- 5) A MESMA PERGUNTA, NA GOLD — o contraste
-- =====================================================================
-- Compare com o bloco 1: lá foram 5 tabelas, 4 joins e 1 CTE, e seis
-- decisões escondidas. Aqui a medida JÁ EXISTE, testada e documentada.

select
    u.nome_unidade,
    count(*)                                 as chamados_resolvidos,
    round(avg(f.tempo_atendimento_dias), 1)  as tempo_medio_dias
from 'data/gold/fato_chamado.parquet' f
join 'data/gold/dim_unidade.parquet'  u on f.unidade_sk = u.unidade_sk
where f.tempo_atendimento_dias is not null
group by 1
order by tempo_medio_dias desc;

-- 💬 "2 arquivos, 1 join, zero decisão. As seis decisões continuam
--    existindo — só que foram tomadas UMA vez, no pipeline, de forma
--    versionada, testada e documentada."
