-- =====================================================================
-- OS DADOS BRUTOS, DIRETO DOS ARQUIVOS — sem banco, sem tabela
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
-- 1) OS QUATRO ANALISTAS — a tabela do slide, feita no arquivo cru
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
-- 2) OS DEFEITOS, UM POR UM — todos visíveis no arquivo cru
-- =====================================================================
-- Nenhum destes precisa de ferramenta especial para achar. Precisa de
-- alguém ter DECIDIDO procurar. É essa decisão que a Silver transforma
-- em código, e que os testes do dbt passam a cobrar toda vez.

-- 2.1 duplicata integral: a mesma linha, repetida
select chamado_id, count(*) as vezes
from read_csv_auto('data/raw/chamados.csv', all_varchar = true)
group by chamado_id
having count(*) > 1
order by chamado_id;

-- 2.2 chave primária repetida no cadastro de categorias
--     (o id 2 aparece duas vezes, com grafias diferentes)
select categoria_id, count(*) as vezes, string_agg(nome_categoria, ' | ') as valores
from 'data/raw/categorias.csv'
group by categoria_id
having count(*) > 1;

-- 2.3 chave estrangeira órfã: chamado apontando para unidade que não existe
select chamado_id, unidade_id, data_abertura, data_fechamento
from read_csv_auto('data/raw/chamados.csv', all_varchar = true)
where try_cast(unidade_id as integer) not in (select unidade_id from 'data/raw/unidades.csv');

-- 2.4 registro sem identificador
select *
from read_csv_auto('data/raw/chamados.csv', all_varchar = true)
where chamado_id is null or trim(chamado_id) = '';

-- 2.5 datas em dois formatos no MESMO campo
select
    count(*) filter (where try_cast(data_abertura as date) is not null)                  as formato_iso,
    count(*) filter (where try_cast(data_abertura as date) is null
                       and try_strptime(data_abertura, '%d/%m/%Y') is not null)          as formato_br,
    count(*) filter (where try_cast(data_abertura as date) is null
                       and try_strptime(data_abertura, '%d/%m/%Y') is null)              as nao_reconhecida
from read_csv_auto('data/raw/chamados.csv', all_varchar = true);

-- 2.6 tempo negativo: fechou antes de abrir
select chamado_id, data_abertura, data_fechamento
from read_csv_auto('data/raw/chamados.csv', all_varchar = true)
where coalesce(try_cast(data_fechamento as date),
               try_cast(try_strptime(data_fechamento, '%d/%m/%Y') as date))
    < coalesce(try_cast(data_abertura as date),
               try_cast(try_strptime(data_abertura, '%d/%m/%Y') as date));

-- 2.7 grafia inconsistente: espaço sobrando e caixa alternando
select distinct nome_unidade, '[' || nome_unidade || ']' as com_delimitador
from 'data/raw/unidades.csv'
order by 1;

select distinct situacao, '[' || situacao || ']' as com_delimitador
from read_csv_auto('data/raw/chamados.csv', all_varchar = true)
order by 1;

-- 2.8 interação órfã: andamento de um chamado que não está no cadastro
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
-- 3) O QUE UM BANCO TERIA RECUSADO — a prova, em 10 linhas
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
