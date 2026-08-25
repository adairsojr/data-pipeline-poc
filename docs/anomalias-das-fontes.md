# As anomalias das fontes, arquivo por arquivo

Tudo aqui foi **verificado nos arquivos**, não copiado do gerador. Reproduzível com
`python scripts/rodar_bloco.py 3`.

As quatro fontes de `data/raw/` chegaram de lugares diferentes, em dois formatos, e
**nenhuma chave garante nada entre elas**. Nada disso dá erro: arquivo aceita tudo.

| Arquivo | Formato | Linhas | Anomalias próprias |
|---|---|---|---|
| `chamados.csv` | CSV | 122 | 6 |
| `unidades.csv` | CSV | 8 | 1 (em 4 linhas) |
| `categorias.csv` | CSV | 7 | 1 |
| `interacoes.json` | JSON | 408 | 3 |
| *entre as fontes* | — | — | 4 |

---

## 1. `chamados.csv` — 122 linhas

| # | Anomalia | Onde | Linhas | Por que passa despercebido |
|---|---|---|---|---|
| 1 | `data_abertura` em **DD/MM/AAAA** | 500051 · 500079 | 2 | `try_cast` devolve `NULL` **em silêncio** — o chamado some da média sem aviso |
| 2 | `data_fechamento` em **DD/MM/AAAA** | 500024 | 1 | idem |
| 3 | `chamado_id` **vazio** | 1 linha (categoria 4, unidade 2, 2025-02-03) | 1 | o registro é válido em tudo o mais; só não dá para identificá-lo |
| 4 | **Duplicata integral** — linha repetida | 500025 · 500117 | 2 | são idênticas: nada no arquivo indica que são a mesma coisa |
| 5 | `unidade_id` **inexistente** no cadastro | 500060 → `unidade_id` 99 | 1 | o join simplesmente descarta a linha, ou a mantém órfã, conforme o tipo de join |
| 6 | **Fechamento antes da abertura** | 500103 → `−25` dias | 1 | entra na média como número **negativo** e puxa o resultado para baixo |

**O impacto medido de cada uma** (regra do analista A):

| Defeito | Sem tratar | Tratado |
|---|---|---|
| duplicata integral (#4) | 96 linhas · **11,21** dias | 94 linhas · **10,83** dias |
| unidade órfã (#5) | 95 linhas · **11,2** dias | 94 · **10,8** |
| tempo negativo (#6) | 95 linhas · **10,5** dias | 94 · **10,8** |

### O que NÃO é anomalia neste arquivo

- **23 chamados com `data_fechamento` vazio.** É a situação `Em andamento` — dado
  legítimo, não defeito. Vira `NULL` na medida, não linha descartada.
- **`equipe_id` de 1 a 5, repetindo entre unidades.** Não há `equipes.csv`: a equipe
  não tem cadastro próprio. É o que a torna **dimensão degenerada** — fica na fato,
  como atributo, sem virar tabela.

---

## 2. `unidades.csv` — 8 linhas

| # | Anomalia | Linhas | Impacto |
|---|---|---|---|
| 7 | **Grafia inconsistente** no `nome_unidade` | 4 de 8 | um `GROUP BY nome_unidade` separaria "Dourados" de "dourados" como se fossem duas unidades |

| `unidade_id` | Valor no arquivo | Problema |
|---|---|---|
| 2 | `dourados` | tudo minúsculo |
| 3 | `TRÊS LAGOAS` | tudo maiúsculo |
| 6 | `  Aquidauana` | dois espaços à esquerda |
| 8 | `Naviraí ` | um espaço à direita |

Os espaços são os piores: **invisíveis na tela**. Só aparecem se você delimitar o
valor — `'[' || nome_unidade || ']'`.

---

## 3. `categorias.csv` — 7 linhas para 6 categorias

| # | Anomalia | Onde | Impacto |
|---|---|---|---|
| 8 | **Chave primária repetida** | `categoria_id` 2 aparece 2× | `Rede e Internet` e `REDE E INTERNET` |

Este é o defeito de maior impacto do conjunto, e o mais silencioso:

| Etapa | Linhas | Média |
|---|---|---|
| só os chamados | 94 | **10,83** |
| juntando `unidades` | 94 | 10,83 |
| juntando `categorias` | **110** | **11,14** |

**16 chamados contados duas vezes** por um único id repetido num cadastro de seis
linhas. Num banco relacional a chave primária jamais teria permitido a gravação —
é a demonstração mais direta de "o que se perdeu quando o dado virou arquivo".

---

## 4. `interacoes.json` — 408 registros

| # | Anomalia | Onde | Registros |
|---|---|---|---|
| 9 | **Evento duplicado** (objeto inteiro repetido) | 500011 · 500025 · 500026 · 500048 · 500091 | 5 |
| 10 | `data_interacao` em **DD/MM/AAAA** | 500095 · 500096 | 2 |
| 11 | `chamado_id` **órfão** | 9999999 (`Triagem`, 2025-06-11) | 1 |

Sobre o #9: um dos cinco é um **`Encerramento`** (chamado 500048). Derivar o
fechamento a partir das interações sem `group by` faria esse chamado entrar duas
vezes na média — é o *fan-out* clássico. Nesta PoC o efeito é pequeno (93→94 linhas,
11,48→11,49 dias) porque a data de fechamento vem do CSV; num pipeline que dependesse
só do JSON, seria grave.

---

## 5. Entre as fontes — o que nenhuma tabela sozinha revela

Estas não pertencem a arquivo nenhum. Só aparecem quando você tenta juntar.

| # | Anomalia | Números |
|---|---|---|
| 12 | **O `chamados.csv` e o `interacoes.json` discordam sobre o fechamento** | 96 fechados no CSV · 54 têm `Encerramento` no JSON · **42 não têm nenhum** |
| 13 | **E quando têm, a data é outra** | 53 divergem · **1** confere |
| 14 | **Chamados `Em andamento` que já têm `Encerramento` no JSON** | 7 |
| 15 | **Chamados sem nenhuma interação registrada** | 2 |

O #12 e o #13 juntos mudam a resposta da pergunta de negócio:

| De onde veio a data de fechamento | Média | Chamados |
|---|---|---|
| `data_fechamento`, do `chamados.csv` | **10,8** dias | 94 |
| `Encerramento`, do `interacoes.json` | **32,5** dias | 60 |

Três vezes maior, e nenhuma das duas consultas dá erro. **Qual das duas é a verdade
não é decisão de SQL** — é decisão de governança, e alguém precisa tomá-la e
escrevê-la em algum lugar.

---

## Onde cada uma é resolvida

| # | Anomalia | Resolvida em | Como |
|---|---|---|---|
| 1, 2 | datas em dois formatos | `stg_chamados.sql` | `coalesce(try_cast, try_strptime)` |
| 3 | `chamado_id` vazio | `stg_chamados.sql` | `where chamado_id is not null` |
| 4 | duplicata integral | `stg_chamados.sql` | `select distinct` |
| 5 | unidade órfã | `fato_chamado.sql` | `where c.unidade_id in (select ... from stg_unidades)` |
| 6 | tempo negativo | `fato_chamado.sql` | `case when data_fechamento >= data_abertura` |
| 7 | grafia inconsistente | `stg_unidades.sql` | `trim` + capitalização palavra a palavra |
| 8 | `categoria_id` repetido | `stg_categorias.sql` | `row_number()` — **decisão de governança**, não de SQL |
| 9, 10 | eventos duplicados e datas | `stg_interacoes.sql` | `select distinct` + `coalesce` |
| 11 | interação órfã | *não tratada* | o `stg_interacoes` não alimenta a Gold |
| 12–15 | as fontes discordam | *não tratada* | **é a discussão da aula**, não um bug a consertar |

Três observações que valem mais que o conserto:

1. **O #3 é descartado em silêncio.** Em produção, o correto seria mandá-lo para
   uma área de **quarentena** e notificar a origem. Descartar sem avisar é a opção
   mais perigosa.
2. **O #5 também.** A alternativa madura é apontar para uma linha "Não informado"
   na dimensão (a clássica `sk = 0`), para o chamado aparecer no relatório em vez
   de sumir.
3. **O #8 é o único que o SQL não sabe resolver sozinho.** "Qual é o nome oficial
   da categoria?" é pergunta para quem é **dono** do dado. O `row_number()` escolhe
   a grafia que não está em maiúsculas — uma decisão arbitrária, tomada por quem
   escreveu o modelo.

---

## Como ver cada uma ao vivo

```bash
python scripts/rodar_bloco.py 3      # os defeitos, um por consulta
python scripts/rodar_bloco.py 1      # o join das 4 fontes: fan-out e divergência
python scripts/rodar_bloco.py 4      # o que um banco teria RECUSADO (PK e FK)
```

O bloco 4 é o fecho: cria duas tabelas com chave primária e estrangeira de verdade
e tenta gravar nelas os mesmos defeitos. O DuckDB recusa os três, na tela.
