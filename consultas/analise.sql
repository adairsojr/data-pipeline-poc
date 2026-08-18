-- =====================================================================
-- CONSULTAS DE ANÁLISE — o CONSUMO da camada Gold
-- =====================================================================
-- Execute da raiz do projeto:
--   python -c "import duckdb; print(duckdb.sql(open('consultas/analise.sql').read()))"
--
-- (o DuckDB executa a ÚLTIMA instrução do arquivo — descomente uma por vez)
--
-- Repare em todas elas: NENHUMA regra de negócio. A medida já existe,
-- as decisões já foram tomadas no pipeline. Quem consulta apenas agrupa.
-- =====================================================================


-- =====================================================================
-- 1) A PERGUNTA OFICIAL DA POC
--    "tempo médio de atendimento por unidade, categoria e período"
-- =====================================================================
-- 4 arquivos, 3 joins — o star schema em ação: a fato no centro,
-- as três dimensões dando contexto.
select
    u.nome_unidade,
    c.nome_categoria,
    t.ano,
    count(*)                                   as chamados_resolvidos,
    round(avg(f.tempo_atendimento_dias), 1)    as tempo_medio_dias
from 'data/gold/fato_chamado.parquet' f
join 'data/gold/dim_unidade.parquet'   u on f.unidade_id   = u.unidade_id
join 'data/gold/dim_categoria.parquet' c on f.categoria_id = c.categoria_id
-- ROLE-PLAYING: aqui dim_tempo está no papel de "data de abertura".
-- Trocar para f.data_fechamento responderia outra pergunta: chamados
-- FECHADOS no ano, em vez de ABERTOS no ano.
join 'data/gold/dim_tempo.parquet'     t on f.data_abertura = t.data
-- exclui os chamados em andamento (medida nula, por decisão do modelo)
where f.tempo_atendimento_dias is not null
group by 1, 2, 3
order by 1, 2, 3;


-- =====================================================================
-- 2) O RANKING QUE O GESTOR QUER VER — por unidade
-- =====================================================================
-- Resultado esperado: Aquidauana 19,9 · Dourados 15,1 · Ponta Porã 13,3
-- · Três Lagoas 11,3 · Naviraí 9,1 · Corumbá 7,8 · Campo Grande 6,8
-- · Coxim 4,8    (média geral: 10,8 dias)
--
-- select
--     u.nome_unidade,
--     count(*)                                 as chamados_resolvidos,
--     round(avg(f.tempo_atendimento_dias), 1)  as tempo_medio_dias
-- from 'data/gold/fato_chamado.parquet' f
-- join 'data/gold/dim_unidade.parquet' u on f.unidade_id = u.unidade_id
-- where f.tempo_atendimento_dias is not null
-- group by 1
-- order by tempo_medio_dias desc;


-- =====================================================================
-- 3) EVOLUÇÃO NO TEMPO — por unidade e ano
-- =====================================================================
-- select
--     u.nome_unidade,
--     t.ano,
--     count(*)                                 as chamados_resolvidos,
--     round(avg(f.tempo_atendimento_dias), 1)  as tempo_medio_dias
-- from 'data/gold/fato_chamado.parquet' f
-- join 'data/gold/dim_unidade.parquet' u on f.unidade_id = u.unidade_id
-- join 'data/gold/dim_tempo.parquet'   t on f.data_abertura = t.data
-- where f.tempo_atendimento_dias is not null
-- group by 1, 2
-- order by 1, 2;


-- =====================================================================
-- 4) POR EQUIPE — sempre com a unidade!
-- =====================================================================
-- ⚠ equipe_id NÃO é único na organização: a "equipe 2" existe em várias
--   unidades. Agrupar só por equipe_id somaria a equipe 2 de Campo
--   Grande com a de Dourados — um número que não significa nada.
--
--   O HAVING evita médias calculadas sobre 1 ou 2 chamados: uma média
--   de um caso não é uma média.
--
-- select
--     u.nome_unidade,
--     f.equipe_id                              as equipe,
--     count(*)                                 as chamados_resolvidos,
--     round(avg(f.tempo_atendimento_dias), 1)  as tempo_medio_dias
-- from 'data/gold/fato_chamado.parquet' f
-- join 'data/gold/dim_unidade.parquet' u on f.unidade_id = u.unidade_id
-- where f.tempo_atendimento_dias is not null
-- group by 1, 2
-- having count(*) >= 3
-- order by tempo_medio_dias desc;


-- =====================================================================
-- 5) A ARMADILHA — mostre em aula ANTES da consulta 4
-- =====================================================================
-- Olhe a coluna unidades_diferentes: a mesma equipe aparece em várias
-- unidades. É a prova de que agrupar só por equipe_id está errado.
--
-- select
--     equipe_id,
--     count(*)                    as chamados,
--     count(distinct unidade_id)  as unidades_diferentes
-- from 'data/gold/fato_chamado.parquet'
-- where tempo_atendimento_dias is not null
-- group by 1 order by 1;


-- =====================================================================
-- 6) FAN-OUT — o erro nº 1 com tabelas fato
-- =====================================================================
-- A fato está no grão de CHAMADO. Ao juntá-la com interações (grão de
-- EVENTO), cada chamado vira várias linhas e a média muda — sem nenhum
-- erro de sintaxe.
--
-- Resultado esperado:  10,8 dias em 118 linhas  ->  15,2 dias em 395.
-- A média sobe 41% porque chamados demorados acumulam mais interações
-- e passam a pesar mais.
--
-- select count(*) as linhas, round(avg(tempo_atendimento_dias),1) as media
-- from 'data/gold/fato_chamado.parquet' where tempo_atendimento_dias is not null;
--
-- select count(*) as linhas, round(avg(f.tempo_atendimento_dias),1) as media
-- from 'data/gold/fato_chamado.parquet' f
-- join 'data/silver/stg_interacoes.parquet' i on i.chamado_id = f.chamado_id
-- where f.tempo_atendimento_dias is not null;


-- =====================================================================
-- 7) O EFEITO DE UM ÚNICO REGISTRO RUIM — para a discussão final
-- =====================================================================
-- A coluna da esquerda usa a regra oficial (tempo negativo excluído).
-- A da direita esquece esse cuidado. UM registro implausível derruba
-- Ponta Porã de 13,3 para 10,9 e a faz trocar de posição com Três
-- Lagoas no ranking — sem que nenhuma consulta acuse erro.
--
-- select
--     u.nome_unidade,
--     round(avg(f.tempo_atendimento_dias), 1) as regra_oficial,
--     round(avg(case when f.data_fechamento is not null
--                    then date_diff('day', f.data_abertura, f.data_fechamento)
--               end), 1)                      as sem_excluir_negativo
-- from 'data/gold/fato_chamado.parquet' f
-- join 'data/gold/dim_unidade.parquet' u on f.unidade_id = u.unidade_id
-- group by 1
-- order by regra_oficial desc;
