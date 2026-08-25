"""Cria um sistema de chamados normalizado (OLTP) para a demonstração.

Gera data/chamados_oltp.duckdb com o modelo relacional normalizado a
partir das mesmas fontes da PoC — para comparar, ao vivo, a consulta no
OLTP com a consulta na Gold (ver docs/comparacao-oltp-vs-gold.md).

A diferença mais importante que este script materializa: no OLTP **não
existe** uma coluna `data_fechamento`. O fechamento é um EVENTO na
tabela de interações, como qualquer outro andamento. É por isso que a
mesma pergunta exige uma CTE e quatro joins do lado transacional.

Uso, da raiz do projeto:
    python scripts/criar_oltp_simulado.py
    python -c "from pathlib import Path

import duckdb; con=duckdb.connect('data/chamados_oltp.duckdb'); print(con.sql('show tables'))"
"""

from pathlib import Path

import duckdb

# Fica em data/ junto com o resto do storage da PoC — e no .gitignore,
# porque é artefato gerado (a regra data/*.duckdb já cobre).
DESTINO = Path(__file__).resolve().parents[1] / "data" / "chamados_oltp.duckdb"
DESTINO.unlink(missing_ok=True)          # sempre do zero, evita schema antigo
con = duckdb.connect(str(DESTINO))

con.execute("""
-- ⚠ AS CHAVES ESTRANGEIRAS SÃO O PONTO DA AULA.
-- Este banco tem PK e FK de verdade: é ele que IMPEDE a gravação
-- inválida. Quando o dado sai daqui para um CSV, essa garantia some —
-- e é por isso que, no lake, a integridade vira um TESTE.
-- As FKs também fazem o DBeaver desenhar as ligações no diagrama.

create or replace table unidade (
    unidade_id integer primary key,
    nome_unidade varchar not null,
    uf varchar not null
);
create or replace table categoria (
    categoria_id integer primary key,
    nome_categoria varchar not null           -- o CSV terá o id 2 repetido; aqui é impossível
);
create or replace table situacao (
    situacao_id integer primary key,
    descricao varchar not null
);
create or replace table tipo_interacao (
    tipo_interacao_id integer primary key,
    descricao varchar not null
);
create or replace table equipe (
    equipe_id integer primary key,
    unidade_id integer not null references unidade(unidade_id),
    numero_equipe integer not null,
    nome_equipe varchar not null
);
create or replace table chamado (
    chamado_id bigint primary key,
    protocolo varchar not null,
    categoria_id integer not null references categoria(categoria_id),
    equipe_id integer not null references equipe(equipe_id),
    situacao_id integer not null references situacao(situacao_id),
    data_abertura date not null
    -- NÃO existe data_fechamento: o fechamento é uma interação
);
create or replace table interacao (
    interacao_id bigint primary key,
    chamado_id bigint not null references chamado(chamado_id),
    tipo_interacao_id integer not null references tipo_interacao(tipo_interacao_id),
    data_interacao date not null
);
""")

con.execute("""
insert into unidade
select cast(unidade_id as integer),
       array_to_string(list_transform(string_split(lower(trim(nome_unidade)),' '), w -> upper(w[1])||w[2:]),' '),
       upper(trim(uf))
from 'data/raw/unidades.csv';

insert into categoria
select distinct on (cast(categoria_id as integer)) cast(categoria_id as integer), nome_categoria
from 'data/raw/categorias.csv';

insert into situacao values (1,'Em andamento'), (2,'Resolvido');
insert into tipo_interacao values
 (1,'Abertura'),(2,'Triagem'),(3,'Atribuição'),(4,'Contato com Usuário'),
 (5,'Diagnóstico'),(6,'Solução Aplicada'),(7,'Encerramento');

insert into equipe
select row_number() over (order by u.unidade_id, e.n), u.unidade_id, e.n, 'Equipe ' || e.n
from unidade u cross join (select unnest([1,2,3,4,5]) as n) e;
""")

con.execute("""
create or replace temp table cham_raw as
select
    try_cast(chamado_id as bigint) as chamado_id,
    try_cast(categoria_id as integer) as categoria_id,
    try_cast(unidade_id as integer) as unidade_id,
    try_cast(equipe_id as integer) as equipe_local,
    coalesce(try_cast(data_abertura as date),
             try_cast(try_strptime(data_abertura,'%d/%m/%Y') as date)) as data_abertura,
    coalesce(try_cast(data_fechamento as date),
             try_cast(try_strptime(data_fechamento,'%d/%m/%Y') as date)) as data_fechamento
from 'data/raw/chamados.csv'
where try_cast(chamado_id as bigint) is not null
  and try_cast(unidade_id as integer) in (select unidade_id from unidade);

insert into chamado
select distinct on (c.chamado_id)
    c.chamado_id,
    printf('CH-%04d-%06d', extract(year from c.data_abertura), c.chamado_id % 1000000),
    c.categoria_id, e.equipe_id,
    case when c.data_fechamento is not null then 2 else 1 end,
    c.data_abertura
from cham_raw c
join equipe e on e.unidade_id = c.unidade_id and e.numero_equipe = c.equipe_local;

insert into interacao
select row_number() over () as interacao_id, chamado_id, tipo_interacao_id, data_interacao
from (
    select chamado_id, 1 as tipo_interacao_id, data_abertura as data_interacao
    from cham_raw
    union all
    select c.chamado_id, 2, c.data_abertura + interval 1 day
    from cham_raw c
    union all
    select c.chamado_id, 5, c.data_fechamento - interval 1 day
    from cham_raw c where c.data_fechamento is not null
    union all
    -- o ENCERRAMENTO como evento — é aqui que mora a data de fechamento
    select c.chamado_id, 7, c.data_fechamento
    from cham_raw c where c.data_fechamento is not null
);
""")

for t in ["unidade", "equipe", "categoria", "chamado", "interacao"]:
    n = con.execute(f"select count(*) from {t}").fetchone()[0]
    print(f"{t:15s} {n}")
print(f"\nOK -> {DESTINO}")
