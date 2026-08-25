# Diagramas

Os diagramas desta PoC são **Mermaid** — diagrama como código. São arquivos de texto
(`.mmd`), então versionam no Git, aparecem no `git diff` quando mudam, e não dependem
de nenhuma ferramenta de desenho.

É a mesma ideia que a aula defende para o SQL: se o pipeline é código, o desenho do
pipeline também deveria ser.

## Como visualizar

### O jeito mais rápido: este próprio arquivo

Instale a extensão **Markdown Preview Mermaid Support** (`bierner.markdown-mermaid`):
`Cmd+Shift+X`, buscar pelo nome, instalar.

Depois **abra este `README.md` e aperte `Cmd+Shift+V`** — os quatro diagramas aparecem
renderizados de uma vez, com a explicação de cada um.

⚠ **Essa extensão NÃO renderiza arquivos `.mmd`.** Ela só adiciona Mermaid ao preview de
Markdown. Se você abrir um `.mmd`, vai ver só o texto — é o comportamento esperado.

### Para pré-visualizar um `.mmd` direto

Aí precisa de outra extensão:

- **Mermaid Chart** (`MermaidChart.vscode-mermaid-chart`) — a oficial. Abre o `.mmd` e
  aparece um botão de preview no canto superior direito.
- **Mermaid Preview** (`vstirbu.vscode-mermaid-preview`) — mais leve.
  `Cmd+Shift+P` → "Mermaid: Preview".

### Sem instalar nada: `ver-diagramas.html`

**Dê duplo clique em `diagramas/ver-diagramas.html`.** Ele abre no navegador e renderiza
os quatro diagramas, sem depender de extensão nenhuma do VS Code. É a saída garantida
quando o preview do Markdown não coopera.

Precisa de internet na primeira vez (o Mermaid vem de um CDN). Se você editar um `.mmd`,
rode `python diagramas/gerar_html.py` para atualizar a página.

E para gerar imagem para um slide: copie o conteúdo do `.mmd` e cole em
<https://mermaid.live> — renderiza na hora e exporta PNG ou SVG.

### No GitHub

Blocos ` ```mermaid ` em arquivos `.md` renderizam sozinhos. Por isso os quatro diagramas
estão embutidos aqui embaixo, além de existirem como `.mmd` — o `.mmd` é a fonte, este
README é a vitrine.

---

## 1. O modelo relacional da origem

O sistema que gerou os nossos quatro arquivos: normalizado, orientado a eventos.
Reproduzível com `python scripts/criar_oltp_simulado.py`.

Dois pontos que a aula explora:

- **`chamado` não tem `data_fechamento`** — o fechamento é uma interação do tipo
  "Encerramento". É por isso que a medida precisa ser derivada.
- **A unidade vem via equipe** — não existe `unidade_id` no chamado, o que obriga a
  consulta OLTP a dois joins encadeados.

```mermaid
erDiagram
    UNIDADE ||--o{ EQUIPE : "tem"
    EQUIPE  ||--o{ CHAMADO : "atende"
    CATEGORIA ||--o{ CHAMADO : "classifica"
    SITUACAO  ||--o{ CHAMADO : "estado atual"
    CHAMADO ||--o{ INTERACAO : "registra"
    TIPO_INTERACAO ||--o{ INTERACAO : "qualifica"

    UNIDADE {
        integer unidade_id PK "8 linhas"
        varchar nome_unidade
        varchar uf
    }
    EQUIPE {
        integer equipe_id PK "40 linhas"
        integer unidade_id FK
        integer numero_equipe
        varchar nome_equipe
    }
    CATEGORIA {
        integer categoria_id PK "6 linhas"
        varchar nome_categoria
    }
    SITUACAO {
        integer situacao_id PK "2 linhas"
        varchar descricao
    }
    CHAMADO {
        bigint chamado_id PK "118 linhas"
        varchar protocolo
        integer categoria_id FK
        integer equipe_id FK
        integer situacao_id FK
        date data_abertura "NAO existe data_fechamento"
    }
    INTERACAO {
        bigint interacao_id PK "434 linhas"
        bigint chamado_id FK
        integer tipo_interacao_id FK
        date data_interacao
    }
    TIPO_INTERACAO {
        integer tipo_interacao_id PK "7 linhas"
        varchar descricao "Abertura, Triagem, ... Encerramento"
    }
```

**O que a origem exportou.** Os quatro arquivos de `data/raw/` são *exports
desnormalizados* deste modelo:

| Arquivo | Vem de | Linhas |
|---|---|---|
| `chamados.csv` | `chamado` + `equipe.unidade_id` + `situacao.descricao` + a data de fechamento derivada da interação | 122 |
| `unidades.csv` | `unidade` | 8 |
| `categorias.csv` | `categoria` — **com 1 id duplicado**, que o banco jamais teria permitido | 7 |
| `interacoes.json` | `interacao` + `tipo_interacao.descricao` | 408 |

O export achata o modelo: some a normalização, somem as chaves estrangeiras — e some a
garantia que o banco dava. É daí que nasce a necessidade dos testes.

---

## 2. A DAG do pipeline

O grafo que o dbt **deduz** dos `source()` e `ref()`. Ninguém escreve a ordem de
execução em lugar nenhum.

Confere com `cd dbt && dbt docs generate && dbt docs serve`, ou direto em
`dbt/target/manifest.json`.

```mermaid
flowchart LR
    subgraph FONTES["FONTES (data/raw)"]
        f1["chamados.csv<br/>122"]
        f2["unidades.csv<br/>8"]
        f3["categorias.csv<br/>7"]
        f4["interacoes.json<br/>408"]
    end

    subgraph BRONZE["BRONZE — Python/Pandas"]
        b1[(bronze.chamados)]
        b2[(bronze.unidades)]
        b3[(bronze.categorias)]
        b4[(bronze.interacoes)]
    end

    subgraph SILVER["SILVER — dbt, usa source()"]
        s1["stg_chamados<br/>119"]
        s2["stg_unidades<br/>8"]
        s3["stg_categorias<br/>6"]
        s4["stg_interacoes<br/>403"]
    end

    subgraph GOLD["GOLD — dbt, usa ref()"]
        g1["fato_chamado<br/>118"]
        g2["dim_unidade"]
        g3["dim_categoria"]
        g4["dim_tempo"]
    end

    f1 --> b1 --> s1
    f2 --> b2 --> s2
    f3 --> b3 --> s3
    f4 --> b4 --> s4

    s1 --> g1
    s2 --> g1
    s2 --> g2
    s3 --> g3
    s1 --> g4

    g1 --> R(["Resposta: 10,8 dias"])
    g2 --> R
    g3 --> R
    g4 --> R

    classDef bronze fill:#FFF4E6,stroke:#DD6B20,color:#7C2D12
    classDef silver fill:#F1F5F9,stroke:#64748B,color:#1E293B
    classDef gold   fill:#FEF9E7,stroke:#B7791F,color:#744210
    classDef fonte  fill:#fff,stroke:#94A3B8,color:#334155
    class b1,b2,b3,b4 bronze
    class s1,s2,s3,s4 silver
    class g1,g2,g3,g4 gold
    class f1,f2,f3,f4 fonte
```

Repare em duas coisas:

- **A fato não aponta para as dimensões.** Ela depende de `stg_chamados` e
  `stg_unidades`, e só. Estrela é modelo *lógico* (como consultar); DAG é ordem de
  *construção*. O encontro entre fato e dimensão acontece na consulta.
- **A `dim_tempo` depende de `stg_chamados`** — não porque a fato precise dela, mas
  porque ela usa a menor e a maior data dos chamados para saber que intervalo de
  calendário gerar.

---

## 3. O modelo dimensional da Gold

O star schema implementado. Grão: uma linha = um chamado (118 linhas, 94 com medida).

```mermaid
erDiagram
    DIM_UNIDADE   ||--o{ FATO_CHAMADO : "onde"
    DIM_CATEGORIA ||--o{ FATO_CHAMADO : "o que"
    DIM_TEMPO     ||--o{ FATO_CHAMADO : "quando"

    FATO_CHAMADO {
        varchar unidade_sk FK "hash"
        varchar categoria_sk FK "hash"
        integer data_abertura_sk FK "AAAAMMDD"
        integer data_fechamento_sk FK "nulo se em andamento"
        bigint chamado_id "DD - identifica a linha"
        integer equipe_id "DD - sem cadastro proprio"
        varchar situacao
        bigint tempo_atendimento_dias "A MEDIDA - derivada"
    }
    DIM_UNIDADE {
        varchar unidade_sk PK "hash de unidade_id"
        integer unidade_id "chave de negocio"
        varchar nome_unidade
        varchar uf
    }
    DIM_CATEGORIA {
        varchar categoria_sk PK "hash de categoria_id"
        integer categoria_id "chave de negocio"
        varchar nome_categoria
    }
    DIM_TEMPO {
        integer data_sk PK "AAAAMMDD"
        date data
        integer ano
        integer mes
        varchar nome_mes
        integer trimestre
        boolean fim_de_semana
    }
```

**Só as chaves de dimensão ganham surrogate key.** A fato não tem SK própria: com grão
de um chamado por linha, o `chamado_id` degenerado já identifica a linha, e um hash
dele seria a mesma informação duas vezes.

- `unidade_sk` e `categoria_sk` são **hash** da chave de negócio
  (`dbt_utils.generate_surrogate_key`) — determinístico, igual em qualquer run, o que
  importa num pipeline idempotente.
- `data_sk` é a exceção: **smart key `AAAAMMDD`**, a única SK "com significado" que o
  Kimball aceita, porque é legível, ordena cronologicamente e filtra por faixa sem join.
- `data_abertura_sk` e `data_fechamento_sk` apontam para a **mesma** `dim_tempo`, em
  papéis diferentes — é o *role-playing*.

---

## 4. A jornada do dado

O mapa da aula: sete etapas, cada uma virando código executável.

```mermaid
flowchart LR
    A["1. FONTES<br/>CSV + JSON<br/>data/raw/"]
    B["2. INGESTAO<br/>Python + Pandas<br/>src/ingest.py"]
    C["3. BRONZE<br/>preservado<br/>data/bronze/"]
    D["4. SILVER<br/>limpo e tipado<br/>data/silver/"]
    E["5. GOLD<br/>fato + dimensoes<br/>data/gold/"]
    F["6. SERVING<br/>DuckDB<br/>analytics.duckdb"]
    G["7. CONSUMO<br/>SQL e Streamlit<br/>10,8 dias"]

    A --> B --> C
    C -->|"dbt · source()"| D
    D -->|"dbt · ref()"| E
    E --> F --> G

    C -.->|"preservar"| N1[/"defeitos entram<br/>e ficam registrados"/]
    D -.->|"confiar"| N2[/"28 testes<br/>de qualidade"/]
    E -.->|"consumir"| N3[/"a regra mora<br/>num lugar so"/]

    classDef etapa fill:#fff,stroke:#123C6D,stroke-width:2px,color:#123C6D
    classDef nota fill:#F8FAFC,stroke:#94A3B8,stroke-dasharray:4 3,color:#475569
    class A,B,C,D,E,F,G etapa
    class N1,N2,N3 nota
```

---

## Gerar imagem para os slides

O jeito mais rápido é o <https://mermaid.live>: cole o `.mmd`, ajuste o tema se quiser,
e exporte PNG ou SVG.

Por linha de comando, se preferir automatizar:

```bash
npm install -g @mermaid-js/mermaid-cli
mmdc -i diagramas/01-modelo-relacional-origem.mmd \
     -o diagramas/01-modelo-relacional-origem.png \
     -b white -s 3
```

O `-s 3` triplica a resolução — necessário para projeção.

## Manter os diagramas honestos

O diagrama 2 (a DAG) é o único que pode divergir do código sem ninguém perceber, porque
o dbt deduz o grafo sozinho. Para conferir:

```bash
cd dbt && dbt docs generate && dbt docs serve
```

Se o grafo do `dbt docs` e o `.mmd` discordarem, **o `.mmd` é que está errado**.
