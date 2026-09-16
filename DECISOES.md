# DECISÕES

As quatro decisões que a atividade pede, documentadas de forma específica
para o nosso projeto — o pipeline das **Taxas de Rendimento Escolar do INEP
(2023)**, com foco na **evasão (abandono) escolar por município**.

---

## 1. A arquitetura de armazenamento

**O que decidimos:** três camadas, no padrão **Medallion (Bronze → Silver → Gold)**,
materializadas como arquivos no diretório `data/` (um mini data lake local).

| Camada | Formato | Escrita por | Papel |
|---|---|---|---|
| **Bronze** | **Delta Lake** | ingestão Python (`deltalake`) | preservação do bruto, versionada |
| **Silver** | Parquet | dbt (materialização `external`) | limpo, tipado, padronizado |
| **Gold** | Parquet | dbt (materialização `external`) | modelo dimensional para consumo |

**Por quê Medallion:** separa claramente *preservar* (Bronze), *confiar* (Silver) e
*servir* (Gold). Cada salto é rastreável — sempre dá para voltar uma camada e
entender de onde o número veio. O DuckDB é o **engine** que lê os arquivos; storage
(arquivos) e processamento (engine) ficam separados — o princípio do Lakehouse, em
miniatura.

**Por quê Delta Lake no Bronze (e não Parquet solto):** o Bronze é a camada de
**preservação do bruto**. Delta acrescenta ao Parquet um **log de transações**
(`_delta_log/`): cada carga da origem vira uma **versão imutável**. Isso dá:

- **time travel** — consultar a tabela numa versão anterior;
- **auditoria** — histórico de quem escreveu o quê e quando;
- **reprocessamento seguro** — voltar a uma versão anterior sem perder nada.

Usamos a biblioteca `deltalake` (Rust puro, **sem Spark**). Silver e Gold ficam em
Parquet simples porque são **derivadas e reconstruíveis** por `dbt build` a partir do
Bronze — não precisam de histórico próprio.

---

## 2. O grão do modelo principal

**O que decidimos:** o grão da `fato_taxa` é **um município por linha** (no ano de
2023, no recorte Localização = Total e Dependência = Total). Declarado no comentário
do topo de `fato_taxa.sql`.

**O que ficou de fora do grão:** a base do INEP também quebra cada município por
**Localização** (Urbana/Rural) e por **Dependência administrativa** (Federal,
Estadual, Municipal, Privada). Ficamos apenas com os **totais por município** — o
recorte foi feito na geração das fontes (`scripts/gerar_fontes.py`) e está explicado
no `PROCESSO.md`. Manter todas as quebras multiplicaria as linhas sem agregar à
pergunta da PoC.

**Por que 2023 e não uma base mais recente:** as taxas de rendimento vêm da **2ª etapa
do Censo Escolar**, apurada só ao final do ano letivo — o que cria uma defasagem de
divulgação. O rendimento **de 2024** só saiu em **agosto de 2025**, e o de **2025** nem
existe ainda (a 2ª etapa do Censo 2025 estava em coleta). **2023 era a base pública
fechada disponível** quando o pipeline foi construído. O ano é indiferente ao objetivo
da PoC: trocá-lo seria uma nova carga da origem, sem mexer no pipeline, nos testes ou na
métrica derivada.

**Por quê ESTRELA (star schema) e não tabela larga:** escolhemos estrela porque as
perguntas pedem **recortes por perspectivas geográficas** (UF, região) que se repetem
e formam **hierarquia** (município → UF → região). Com a `dim_uf` conformada:

- a mesma dimensão serve para agrupar por UF ou subir para região;
- uma futura segunda fato (ex.: IDEB por município) reaproveitaria `dim_uf`
  (*drill-across*);
- a métrica fica no grão do município, permitindo agregar por qualquer combinação —
  importante porque **média não é aditiva** (média de médias não é a média).

**A métrica é DERIVADA:** `abandono_combinado` = média das taxas de abandono do
**Ensino Fundamental** e do **Ensino Médio**. O INEP entrega as duas etapas
**separadas**; a visão única de evasão por município **não existe em fonte nenhuma** —
é calculada na `fato_taxa`. É o requisito da métrica derivada.

---

## 3. Um dado ambíguo que exigiu escolha

**O caso (o nosso "REDE E INTERNET"):** o cadastro de UFs (`ufs.json`) traz a **mesma
UF duas vezes**, com a mesma sigla e a **região em grafias diferentes**:

```
AC → "Norte"
AC → "NORTE"
```

Se não tratássemos, a `dim_uf` teria a sigla `AC` duplicada, e o join com a fato
**multiplicaria linhas** (fan-out), inflando contagens e distorcendo médias.

**A regra que o código aplicou** (em `stg_ufs.sql`): deduplicar por UF com
`row_number()`, mantendo a grafia que **não** está toda em maiúsculas (preferindo a
capitalização "de nome próprio"). Regra determinística e documentada — vale para
todos, sempre.

**Quem deveria decidir:** essa escolha é **arbitrária do time técnico**. "Qual é a
grafia oficial do nome da região?" é pergunta para o **dono do dado / a governança**,
não para quem escreve o SQL. O código aplica *uma* regra para não travar o pipeline,
mas o certo é a definição vir de fora e o SQL apenas obedecê-la. É aqui que a
governança de dados aparece dentro de um modelo dbt.

---

## 4. O destino do registro inválido

Temos três situações de registro/valor inválido, com escolhas diferentes — porque a
decisão depende do que o registro quebra.

**a) Município sem código (`codigo_municipio` vazio) → DESCARTAR.**
Sem chave não há identidade: não dá para deduplicar, referenciar nem auditar. É
filtrado em `stg_taxas.sql` (`where codigo_municipio is not null`).

**b) Município com UF inexistente no cadastro (`uf = 'ZZ'`) → DESCARTAR, com teste.**
Violação de integridade referencial. Em banco relacional a FK impediria; em
Delta/Parquet não há FK, então a proteção virou **código** (o filtro na `fato_taxa`)
**mais um teste** `relationships` que falha se algo escapar.

**c) Taxa de abandono IMPLAUSÍVEL (> 100) → NEUTRALIZAR na métrica derivada.**
Uma taxa percentual não pode passar de 100. Em vez de descartar a linha inteira (o
município tem outras taxas válidas), a `fato_taxa` **ignora só o valor implausível**
ao calcular `abandono_combinado` (a taxa individual continua visível, mas não
contamina a métrica). O time travel do Delta mostra a origem **corrigindo** esse valor
numa nova versão.

**Por quê essas escolhas — e a ressalva honesta:** descartar/neutralizar mantém a PoC
simples e a métrica limpa, mas **fazer isso em silêncio é perigoso** — o dado "some"
sem ninguém perceber. Numa implementação madura, o correto seria **quarentena** (isolar
o registro e **notificar a origem**) ou a linha **"Não informado"** (a clássica
`sk = 0`, para o registro aparecer no relatório como tal em vez de desaparecer).
Escolhemos descartar/neutralizar **nesta PoC** por clareza didática, mas deixamos a
decisão explícita e discutível — que é o que a governança exige: regra consciente,
documentada e igual para todos, não um efeito colateral escondido na consulta.
