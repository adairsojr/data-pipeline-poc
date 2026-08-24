-- =====================================================================
-- GOLD | fato_chamado — a TABELA FATO do modelo dimensional
-- =====================================================================
-- GRÃO: uma linha = um chamado.
--
-- O grão é a decisão mais importante da modelagem dimensional, e por
-- isso é declarado antes de qualquer coisa. Ele responde: "o que
-- representa UMA linha desta tabela?"
--
-- ⚠ Consequência prática: se alguém juntar esta fato com interações
-- (que estão no grão de EVENTO), cada chamado vira várias linhas e as
-- médias se corrompem. Isso se chama FAN-OUT e é o erro nº 1 com fatos.
--
-- ANATOMIA DE UMA FATO — só três tipos de coluna:
--   1. chaves para as dimensões (unidade_sk, categoria_sk, datas_sk)
--   2. dimensões degeneradas (chamado_id, equipe_id)
--   3. MEDIDAS (tempo_atendimento_dias)
-- Atributo descritivo (como nome_unidade) NÃO entra: é da dimensão.
--
-- TIPO DE FATO: esta é um "accumulating snapshot" — guarda marcos do
-- ciclo de vida (abertura e fechamento) e a linha é ATUALIZADA quando o
-- chamado é resolvido. Um fato de interações seria "transactional"
-- (só insere, nunca atualiza).
-- =====================================================================

{{ config(location='../data/gold/fato_chamado.parquet') }}

with chamados as (

    -- ref() declara a dependência: este modelo só pode ser construído
    -- DEPOIS de stg_chamados. Ninguém escreve essa ordem em lugar
    -- nenhum — o dbt a deduz dos ref() e monta a DAG do projeto.
    select * from {{ ref('stg_chamados') }}

)

select
    -- =================================================================
    -- AS SURROGATE KEYS — como a fato "encontra" a SK da dimensão
    -- =================================================================
    -- No Kimball clássico (SK sequencial), a carga da fato faria um
    -- JOIN de lookup na dimensão para buscar a SK. Com SK por HASH não
    -- precisa: aplicando a MESMA função sobre a MESMA chave de negócio,
    -- o resultado é idêntico ao da dimensão — determinismo é isso.
    -- (O teste `relationships` no schema.yml confere que bate.)
    {{ dbt_utils.generate_surrogate_key(['c.chamado_id']) }}   as chamado_sk,
    {{ dbt_utils.generate_surrogate_key(['c.unidade_id']) }}   as unidade_sk,   -- FK -> dim_unidade
    {{ dbt_utils.generate_surrogate_key(['c.categoria_id']) }} as categoria_sk, -- FK -> dim_categoria

    c.chamado_id,           -- dimensão degenerada (identificador de negócio)

    -- equipe_id é uma DIMENSÃO DEGENERADA: fica na própria fato porque a
    -- origem só nos dá o identificador, sem nome nem atributos — não há
    -- o que colocar numa dim_equipe. Se chegasse um cadastro de equipes
    -- (nome, turno, responsável), aí sim valeria uma dimensão.
    --
    -- ⚠ ATENÇÃO ao analisar: equipe_id NÃO é único na organização — a
    -- "equipe 2" existe em várias unidades. Agrupar só por equipe_id
    -- mistura equipes diferentes. A identificação real é o par
    -- (unidade_id, equipe_id).
    c.equipe_id,

    -- as duas datas são chaves para a MESMA dim_tempo, em papéis
    -- diferentes: isso se chama ROLE-PLAYING DIMENSION.
    -- Consequência: "chamados abertos em 2025" e "chamados fechados
    -- em 2025" são perguntas diferentes, com joins diferentes.
    --
    -- A SK de data é a "smart key" AAAAMMDD (ver dim_tempo.sql) —
    -- por isso dá para filtrar por faixa sem join:
    --   where data_abertura_sk between 20250101 and 20251231
    -- Chamado em andamento não tem fechamento: a SK fica NULA.
    cast(strftime(c.data_abertura,   '%Y%m%d') as integer) as data_abertura_sk,
    cast(strftime(c.data_fechamento, '%Y%m%d') as integer) as data_fechamento_sk,

    c.situacao,

    -- =================================================================
    -- A MEDIDA — o número que o negócio quer analisar
    -- =================================================================
    -- Ela NÃO existe em fonte nenhuma: é DERIVADA de dois marcos.
    -- É aqui que "dado" vira "informação".
    --
    -- Duas decisões de negócio embutidas neste CASE:
    --
    -- 1) Chamados EM ANDAMENTO (sem data_fechamento) ficam com medida
    --    NULA. Ou seja: não entram nas médias. É uma decisão consciente
    --    — incluí-los como "tempo até hoje" daria outro número, também
    --    defensável. O importante é que a decisão esteja documentada
    --    e valha para todos, e não escondida na consulta de cada um.
    --
    -- 2) Tempo NEGATIVO (fechamento anterior à abertura) também vira
    --    NULO. É dado implausível vindo da origem. Note a diferença:
    --    aqui nós protegemos a métrica, mas o problema continua lá.
    --    Quem avisa a origem? Isso é gestão de dados, não SQL.
    --
    -- ⚠ Por que guardamos a medida POR CHAMADO e não a média já
    -- calculada? Porque MÉDIA NÃO É ADITIVA: média de médias não é a
    -- média. Guardando no grão, é possível agregar por qualquer
    -- combinação de dimensões depois.
    case
        when c.data_fechamento is not null
         and c.data_fechamento >= c.data_abertura
        then date_diff('day', c.data_abertura, c.data_fechamento)
    end as tempo_atendimento_dias

from chamados c

-- INTEGRIDADE REFERENCIAL: a origem tem um chamado apontando para uma
-- unidade que não existe no cadastro (unidade_id = 99).
--
-- Em um banco relacional, a chave estrangeira IMPEDIRIA essa gravação.
-- Em arquivos Parquet não existe FK — então a proteção vira código
-- (este filtro) mais um TESTE que acusa o problema (ver schema.yml).
--
-- ⚠ ALTERNATIVA MAIS MADURA: em vez de descartar, apontar o registro
-- para uma linha "Não informado" na dimensão (a clássica sk = 0).
-- Assim o chamado apareceria no relatório como "Não informado" em vez
-- de sumir silenciosamente. Sumir com o dado problemático é sempre a
-- opção mais perigosa.
where c.unidade_id in (select unidade_id from {{ ref('stg_unidades') }})
