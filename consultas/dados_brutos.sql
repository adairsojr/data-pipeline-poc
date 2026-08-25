-- =====================================================================
-- AS QUATRO FONTES, DIRETO DOS ARQUIVOS — sem banco, sem tabela
-- =====================================================================
-- Tudo aqui roda em cima de data/raw/*.csv e *.json.
--
-- NÃO precisa do pipeline, NÃO precisa do dbt, NÃO precisa criar
-- tabela nenhuma. O DuckDB lê CSV e JSON como se fossem tabelas:
--
--     select * from 'data/raw/chamados.csv';
--
-- É esse o ponto do lake: o arquivo JÁ É a tabela.
--
-- COMO EXECUTAR — sempre da RAIZ do projeto (os caminhos são relativos):
--
--   Opção 1 (Python, não precisa instalar nada além do que já temos):
--     python scripts/rodar_bloco.py brutos 1
--
--   Opção 2 (CLI do DuckDB, sem arquivo de banco — tudo em memória):
--     duckdb
--     .read consultas/dados_brutos.sql
--
--   Opção 3 (DBeaver): conexão DuckDB :memory:, e antes rode uma vez
--     SET file_search_path='/Users/vanessaborges/dev_repo/poc-residencia/data-pipeline-poc';
-- =====================================================================


-- =====================================================================
-- 1) O JOIN DAS QUATRO FONTES — a consulta do slide 4
-- =====================================================================
-- Quatro arquivos, de quatro lugares diferentes, em dois formatos.
-- Nenhum banco no meio. Nenhuma chave estrangeira garantindo nada.
--
--   chamados.csv    -> o registro do chamado (e a data de fechamento)
--   unidades.csv    -> o cadastro de unidades
--   categorias.csv  -> o cadastro de categorias
--   interacoes.json -> o andamento de cada chamado, evento a evento
--
-- Estas são as MESMAS quatro fontes, agora preservadas em Parquet na
-- Bronze. É sobre elas que a pergunta precisa ser respondida.

with chamados as (
    select distinct
        try_cast(chamado_id   as bigint)  as chamado_id,
        try_cast(categoria_id as integer) as categoria_id,
        try_cast(unidade_id   as integer) as unidade_id,
        coalesce(try_cast(data_abertura as date),
                 try_cast(try_strptime(data_abertura, '%d/%m/%Y') as date)) as data_abertura,
        coalesce(try_cast(data_fechamento as date),
                 try_cast(try_strptime(data_fechamento, '%d/%m/%Y') as date)) as data_fechamento
    from 'data/bronze/chamados.parquet'
    where chamado_id is not null
),

unidades as (
    select try_cast(unidade_id as integer) as unidade_id, nome_unidade
    from 'data/bronze/unidades.parquet'
),

categorias as (
    select try_cast(categoria_id as integer) as categoria_id, nome_categoria
    from 'data/bronze/categorias.parquet'
),

encerramento as (
    -- a quarta fonte. O group by não é decoração: há eventos duplicados,
    -- e sem agrupar o chamado entraria duas vezes na média (fan-out).
    select
        chamado_id,
        min(coalesce(try_cast(data_interacao as date),
                     try_cast(try_strptime(data_interacao, '%d/%m/%Y') as date))) as encerrou_em
    from 'data/bronze/interacoes.parquet'
    where tipo_interacao = 'Encerramento'
    group by chamado_id
)

select
    u.nome_unidade,
    cat.nome_categoria,
    year(c.data_abertura)                                                    as ano,
    count(*)                                                                 as chamados,
    round(avg(date_diff('day', c.data_abertura, c.data_fechamento)), 1)      as tempo_medio_dias,
    count(e.chamado_id)                                                      as com_encerramento_registrado
from chamados c
join unidades   u   on u.unidade_id     = c.unidade_id     -- 1o join: o nome da unidade
join categorias cat on cat.categoria_id = c.categoria_id   -- 2o join: o nome da categoria
left join encerramento e on e.chamado_id = c.chamado_id    -- 3o join: a quarta fonte
where c.data_fechamento is not null
  and c.data_fechamento >= c.data_abertura
group by 1, 2, 3
order by tempo_medio_dias desc
limit 10;

-- ⚠ REPARE NA ÚLTIMA COLUNA. Ela quase nunca bate com a penúltima.
-- A quarta fonte NÃO CONFIRMA o que a primeira afirma:
--
--   96 chamados fechados segundo o chamados.csv
--   54 deles têm 'Encerramento' registrado no interacoes.json
--   42 não têm nenhum
--    1 tem a data igual à do CSV
--   53 têm data DIFERENTE
--
-- E se alguém resolvesse confiar na quarta fonte em vez da primeira:
--
--   data_fechamento do CSV  ->  10,8 dias em 94 chamados
--   Encerramento do JSON    ->  32,5 dias em 60 chamados
--
-- Três vezes maior. Nenhuma das duas consultas dá erro.
--
-- DIGO: "Num banco relacional isso não aconteceria: existe UMA tabela de
--        interações, ligada por chave estrangeira, e o fechamento é o
--        evento. Aqui são quatro arquivos que vieram de quatro lugares.
--        Nada obriga o de cá a concordar com o de lá. Descobrir QUAL é a
--        verdade não é decisão de SQL — é decisão de governança."
--
-- O contraste com o bloco 2: lá, quatro analistas divergiam por causa do
-- que FILTRARAM. Aqui a divergência vem de qual FONTE cada um acreditou.

-- ---------------------------------------------------------------------
-- E TEM MAIS: o segundo join SOZINHO já estraga a média
-- ---------------------------------------------------------------------
-- O cadastro de categorias tem o id 2 repetido (Rede e Internet /
-- REDE E INTERNET). Juntar com ele DUPLICA todo chamado de categoria 2 —
-- é isso que aparece nas duas linhas 'Aquidauana / Rede e Internet' da
-- consulta acima.
--
-- Ninguém escreveu nada errado. O join está correto. O cadastro é que
-- tem duas linhas para a mesma chave — e num banco relacional a chave
-- primária JAMAIS teria deixado isso ser gravado.

with ch as (
    select distinct
        try_cast(chamado_id as bigint) as chamado_id,
        try_cast(categoria_id as integer) as categoria_id,
        try_cast(unidade_id as integer) as unidade_id,
        coalesce(try_cast(data_abertura as date),
                 try_cast(try_strptime(data_abertura, '%d/%m/%Y') as date)) as ab,
        coalesce(try_cast(data_fechamento as date),
                 try_cast(try_strptime(data_fechamento, '%d/%m/%Y') as date)) as fe
    from 'data/bronze/chamados.parquet' where chamado_id is not null
),
un as (select try_cast(unidade_id as integer) as unidade_id from 'data/bronze/unidades.parquet'),
cat as (select try_cast(categoria_id as integer) as categoria_id from 'data/bronze/categorias.parquet')

select 'so os chamados'                 as etapa, count(*) as linhas,
       round(avg(date_diff('day', ab, fe)), 2) as media
from ch where fe is not null and fe >= ab and unidade_id in (select unidade_id from un)
union all
select 'juntando unidades', count(*), round(avg(date_diff('day', ab, fe)), 2)
from ch join un using (unidade_id) where fe is not null and fe >= ab
union all
select 'juntando categorias  <-- FAN-OUT', count(*), round(avg(date_diff('day', ab, fe)), 2)
from ch join un using (unidade_id) join cat using (categoria_id)
where fe is not null and fe >= ab;

-- RESULTADO ESPERADO:
--   so os chamados         ->   94 linhas   10.83 dias   (o número oficial)
--   juntando unidades      ->   94 linhas   10.83 dias   (join limpo, nada muda)
--   juntando categorias    ->  110 linhas   11.14 dias   (16 chamados contados 2x)
--
-- DIGO: "Um único id repetido num cadastro de SEIS linhas moveu a média
--        da instituição inteira. E o SQL não reclamou."


-- as quatro fontes, e o tamanho de cada uma
select 'chamados.csv'    as fonte, count(*) as linhas from 'data/bronze/chamados.parquet'
union all select 'unidades.csv',    count(*) from 'data/bronze/unidades.parquet'
union all select 'categorias.csv',  count(*) from 'data/bronze/categorias.parquet'
union all select 'interacoes.json', count(*) from 'data/bronze/interacoes.parquet';


-- =====================================================================
-- 2) OS QUATRO ANALISTAS — a tabela do slide, feita no arquivo cru
-- =====================================================================
-- A mesma pergunta, quatro respostas. Ninguém escreveu SQL errado:
-- cada um tomou UMA decisão diferente sobre o que fazer com o dado sujo.
--
-- As duas CTEs abaixo são as ÚNICAS coisas que separam "bruto" de
-- "limpo" — e repare no tamanho delas. É pouca coisa. O problema nunca
-- foi a dificuldade técnica, e sim não haver UM lugar onde essa decisão
-- estivesse escrita.

with bruto as (
    -- o arquivo como veio: 122 linhas, duplicatas incluídas.
    -- all_varchar=true lê tudo como texto de propósito — é assim que o
    -- Bronze guarda, porque tipar já é interpretar.
    select
        try_cast(chamado_id   as bigint)  as chamado_id,
        try_cast(categoria_id as integer) as categoria_id,
        try_cast(unidade_id   as integer) as unidade_id,
        try_cast(equipe_id    as integer) as equipe_id,
        -- a origem mistura AAAA-MM-DD com DD/MM/AAAA. Sem o coalesce,
        -- metade das datas viraria NULL em silêncio.
        coalesce(try_cast(data_abertura as date),
                 try_cast(try_strptime(data_abertura, '%d/%m/%Y') as date)) as data_abertura,
        coalesce(try_cast(data_fechamento as date),
                 try_cast(try_strptime(data_fechamento, '%d/%m/%Y') as date)) as data_fechamento,
        situacao
    from read_csv_auto('data/raw/chamados.csv', all_varchar = true)
),

limpo as (
    -- 122 -> 119. O distinct tira as 2 linhas repetidas, e o filtro tira
    -- 1 chamado que veio sem identificador.
    select distinct * from bruto where chamado_id is not null
),

unidades as (
    select * from 'data/raw/unidades.csv'
),

analista_a as (
    -- A REGRA OFICIAL: só chamados fechados, sem tempo negativo,
    -- e só de unidade que existe no cadastro.
    select round(avg(date_diff('day', data_abertura, data_fechamento)), 1) as media,
           count(*) as n
    from limpo
    where data_fechamento is not null
      and data_fechamento >= data_abertura
      and unidade_id in (select unidade_id from unidades)
),

analista_b as (
    -- ESQUECEU A UNIDADE INEXISTENTE (unidade_id = 99, chamado 500060).
    -- Um único órfão, muito demorado, puxa a média inteira.
    select round(avg(date_diff('day', data_abertura, data_fechamento)), 1), count(*)
    from limpo
    where data_fechamento is not null
      and data_fechamento >= data_abertura
),

analista_c as (
    -- FOI DIRETO NO ARQUIVO CRU. As duplicatas contam duas vezes e
    -- nenhum outro cuidado foi tomado.
    select round(avg(date_diff('day', data_abertura, data_fechamento)), 1), count(*)
    from bruto
    where data_fechamento is not null
),

analista_d as (
    -- ESQUECEU O TEMPO NEGATIVO. Um chamado fechou ANTES de abrir
    -- e entra na média com valor negativo.
    select round(avg(date_diff('day', data_abertura, data_fechamento)), 1), count(*)
    from limpo
    where data_fechamento is not null
      and unidade_id in (select unidade_id from unidades)
)

select 'A' as analista, 'seguiu a regra oficial'                 as decisao, * from analista_a
union all
select 'B', 'esqueceu de filtrar a unidade inexistente',         * from analista_b
union all
select 'C', 'consultou o arquivo cru, com duplicatas',           * from analista_c
union all
select 'D', 'esqueceu de descartar o tempo negativo',            * from analista_d
order by analista;

-- RESULTADO ESPERADO — é a tabela do slide:
--   A | seguiu a regra oficial                      | 10.8 | 94
--   B | esqueceu de filtrar a unidade inexistente   | 11.2 | 95
--   C | consultou o arquivo cru, com duplicatas     | 11.3 | 99
--   D | esqueceu de descartar o tempo negativo      | 10.5 | 95
--
-- DIGO: "Todos os quatro rodaram. Nenhum deu erro. Os quatro números
--        estão numa reunião de diretoria agora."


-- =====================================================================
-- 3) OS DEFEITOS, UM POR UM — todos visíveis no arquivo cru
-- =====================================================================
-- Nenhum destes precisa de ferramenta especial para achar. Precisa de
-- alguém ter DECIDIDO procurar. É essa decisão que a Silver transforma
-- em código, e que os testes do dbt passam a cobrar toda vez.

-- 3.1 duplicata integral: a mesma linha, repetida
select chamado_id, count(*) as vezes
from read_csv_auto('data/raw/chamados.csv', all_varchar = true)
group by chamado_id
having count(*) > 1
order by chamado_id;

-- 3.2 chave primária repetida no cadastro de categorias
--     (o id 2 aparece duas vezes, com grafias diferentes)
select categoria_id, count(*) as vezes, string_agg(nome_categoria, ' | ') as valores
from 'data/raw/categorias.csv'
group by categoria_id
having count(*) > 1;

-- 3.3 chave estrangeira órfã: chamado apontando para unidade que não existe
select chamado_id, unidade_id, data_abertura, data_fechamento
from read_csv_auto('data/raw/chamados.csv', all_varchar = true)
where try_cast(unidade_id as integer) not in (select unidade_id from 'data/raw/unidades.csv');

-- 3.4 registro sem identificador
select *
from read_csv_auto('data/raw/chamados.csv', all_varchar = true)
where chamado_id is null or trim(chamado_id) = '';

-- 3.5 datas em dois formatos no MESMO campo
select
    count(*) filter (where try_cast(data_abertura as date) is not null)                  as formato_iso,
    count(*) filter (where try_cast(data_abertura as date) is null
                       and try_strptime(data_abertura, '%d/%m/%Y') is not null)          as formato_br,
    count(*) filter (where try_cast(data_abertura as date) is null
                       and try_strptime(data_abertura, '%d/%m/%Y') is null)              as nao_reconhecida
from read_csv_auto('data/raw/chamados.csv', all_varchar = true);

-- 3.6 tempo negativo: fechou antes de abrir
select chamado_id, data_abertura, data_fechamento
from read_csv_auto('data/raw/chamados.csv', all_varchar = true)
where coalesce(try_cast(data_fechamento as date),
               try_cast(try_strptime(data_fechamento, '%d/%m/%Y') as date))
    < coalesce(try_cast(data_abertura as date),
               try_cast(try_strptime(data_abertura, '%d/%m/%Y') as date));

-- 3.7 grafia inconsistente: espaço sobrando e caixa alternando
select distinct nome_unidade, '[' || nome_unidade || ']' as com_delimitador
from 'data/raw/unidades.csv'
order by 1;

select distinct situacao, '[' || situacao || ']' as com_delimitador
from read_csv_auto('data/raw/chamados.csv', all_varchar = true)
order by 1;

-- 3.8 interação órfã: andamento de um chamado que não está no cadastro
select i.chamado_id, count(*) as interacoes
from read_json_auto('data/raw/interacoes.json') i
where i.chamado_id not in (
    select try_cast(chamado_id as bigint)
    from read_csv_auto('data/raw/chamados.csv', all_varchar = true)
    where chamado_id is not null
)
group by 1;

-- DIGO: "O arquivo aceitou tudo isso sem reclamar uma única vez.
--        Arquivo não tem chave primária, não tem chave estrangeira,
--        não tem tipo. Arquivo aceita."


-- =====================================================================
-- 4) O QUE UM BANCO TERIA RECUSADO — a prova, em 10 linhas
-- =====================================================================
-- O DuckDB TEM integridade referencial de verdade: primary key,
-- foreign key, unique, not null, check. Vamos provar com duas tabelas
-- temporárias — sem criar banco nenhum, sem persistir nada.
--
-- ⚠ precisa de conexão de ESCRITA (não use read_only aqui).

create or replace temp table unidade_t as
    select * from 'data/raw/unidades.csv';

create or replace temp table cadastro (
    unidade_id integer primary key,
    nome_unidade varchar not null
);

-- carrega o cadastro válido
insert into cadastro select unidade_id, nome_unidade from unidade_t;

create or replace temp table chamado_t (
    chamado_id bigint primary key,
    unidade_id integer not null references cadastro(unidade_id),
    data_abertura date not null
);

-- Agora tente gravar os MESMOS defeitos que o CSV aceitou.
-- Rode uma linha por vez e leia a mensagem em voz alta.

--   (a) a unidade órfã 99, do chamado 500060
--       -> Constraint Error: Violates foreign key constraint because key
--          "unidade_id: 99" does not exist in the referenced table
-- insert into chamado_t values (500060, 99, '2024-05-02');

--   (b) o id de categoria repetido, do categorias.csv
--       -> Constraint Error: Duplicate key "unidade_id: 1" violates
--          primary key constraint.
-- insert into cadastro values (1, 'CAMPO GRANDE');

--   (c) apagar uma unidade que ainda tem chamado
--       -> Constraint Error: Violates foreign key constraint because key
--          "unidade_id: 1" is still referenced by a foreign key
-- insert into chamado_t values (500099, 1, '2024-10-23');
-- delete from cadastro where unidade_id = 1;

-- DIGO: "O banco RECUSOU. O CSV aceitou. A garantia não sumiu por
--        acidente — ela ficou para trás no momento em que o dado saiu
--        do banco e virou arquivo. No lake ela não volta como
--        constraint: volta como TESTE, e é por isso que o teste
--        relationships do dbt existe."
--
-- As restrições que acabamos de declarar, listadas pelo próprio catálogo
-- do DuckDB. É daqui que o DBeaver tira as linhas que ligam as tabelas.
select table_name, constraint_type, constraint_text
from duckdb_constraints()
where table_name in ('cadastro', 'chamado_t')
order by table_name, constraint_type;

-- ⚠ O DuckDB tem FK de verdade, mas com dois limites que valem citar:
--   - não existe ALTER TABLE ... ADD FOREIGN KEY: a chave tem que ser
--     declarada no CREATE TABLE.
--   - não existe ON DELETE CASCADE / SET NULL: ou você apaga o filho
--     antes, ou o banco recusa.
-- Nada disso muda o argumento da aula — só evita a pergunta de quem
-- vier do Postgres.

-- A diferença que fica no quadro:
--   no banco  -> a FK IMPEDE   (erro na hora da gravação)
--   no lake   -> o teste DETECTA (falha no dbt build, depois do fato)
