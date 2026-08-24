# A mesma pergunta, dois caminhos

> "Qual é o tempo médio de atendimento por equipe?"

Este documento mostra a **mesma pergunta** respondida de dois jeitos: direto no banco transacional (OLTP, como no sistema de chamados) e na camada Gold do nosso pipeline. Os dois chegam ao **mesmo número** — o que muda é o esforço, o risco de erro e quem paga a conta.

## Caminho 1 — Direto no OLTP

Num sistema de chamados real, o modelo é normalizado e orientado a **eventos**:

```text
chamado         (chamado_id, protocolo, categoria_id, equipe_id, situacao_id, data_abertura)
equipe          (equipe_id, unidade_id, numero_equipe, nome_equipe)
unidade         (unidade_id, nome_unidade, uf)
interacao       (interacao_id, chamado_id, tipo_interacao_id, data_interacao)
tipo_interacao  (tipo_interacao_id, descricao)
```

Repare no que **não existe**: uma coluna `data_fechamento`. O fechamento é uma **interação**, como qualquer outro andamento do chamado. A consulta:

```sql
with fechamento as (
    -- O fechamento não é uma coluna: é um EVENTO na tabela de interações.
    -- E pode haver mais de um (reabertura!), então pegamos o primeiro.
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
join unidade    u on u.unidade_id = e.unidade_id     -- unidade vem VIA equipe
join fechamento f on f.chamado_id = c.chamado_id
where c.data_abertura is not null
  and f.data_fechamento >= c.data_abertura           -- descarta data implausível
group by 1, 2
having count(*) >= 3
order by tempo_medio_dias desc;
```

**O que foi preciso saber para escrever isso:**

1. que o fechamento é uma **interação**, e não uma coluna do chamado;
2. que o tipo de interação está em **outra tabela** (normalização) — mais um join;
3. que um chamado pode ter **mais de um encerramento** (reabertura) — daí o `min()`;
4. que a unidade **não** se liga direto ao chamado: vem **através** da equipe;
5. que existem datas implausíveis a filtrar;
6. que a média sobre 1 ou 2 casos não é média.

Total: **5 tabelas, 4 joins, 1 CTE** — e seis decisões de negócio embutidas no SQL. Cada analista que reescrever isso pode tomar decisões diferentes em qualquer um dos seis pontos. É assim que dois relatórios sobre o mesmo dado divergem.

E o custo: essa consulta varre a tabela `interacao` — a que mais cresce em qualquer central de serviços — **no banco que está atendendo os usuários naquele momento**.

## Caminho 2 — Na Gold

```sql
select
    u.nome_unidade,
    f.equipe_id                              as equipe,
    count(*)                                 as chamados_resolvidos,
    round(avg(f.tempo_atendimento_dias), 1)  as tempo_medio_dias
from 'data/gold/fato_chamado.parquet' f
join 'data/gold/dim_unidade.parquet'  u on f.unidade_sk = u.unidade_sk
where f.tempo_atendimento_dias is not null
group by 1, 2
having count(*) >= 3
order by tempo_medio_dias desc;
```

**2 arquivos, 1 join.** As seis decisões continuam existindo — só que foram tomadas **uma vez**, no pipeline, de forma versionada, testada e documentada. `tempo_atendimento_dias` já é a medida oficial da organização.

## O resultado

Idêntico nos dois caminhos. Um recorte:

| unidade | equipe | chamados | tempo médio (dias) |
|---|---|---|---|
| Aquidauana | 1 | 3 | 29,3 |
| Ponta Porã | 4 | 6 | 16,0 |
| Naviraí | 2 | 3 | 14,7 |
| Três Lagoas | 1 | 4 | 14,3 |

## A moral

O pipeline **não existe para dar respostas diferentes**. Ele existe para que a resposta certa seja:

- **fácil de obter** — 1 join em vez de 4 mais uma CTE;
- **consistente** — a regra da medida está num lugar só, testada;
- **barata** — não compete com o sistema que atende o público;
- **rastreável** — o lineage mostra de onde cada número veio;
- **reproduzível** — amanhã, com dados novos, é só rodar.

> A pergunta não ficou mais fácil de responder. Ela ficou mais difícil de responder **errado**.
