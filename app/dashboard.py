"""Dashboard da Central de Serviços — o CONSUMO da camada Gold.

Este é o último elo da jornada: Fontes -> Bronze -> Silver -> Gold -> AQUI.

Repare no que este dashboard NÃO faz:
    - não limpa dado (a Silver já limpou);
    - não calcula a medida (a Gold já derivou tempo_atendimento_dias);
    - não decide regra de negócio (as decisões estão no pipeline,
      documentadas e testadas).
Quem consome a Gold apenas FILTRA e AGRUPA. É por isso que qualquer
ferramenta de BI (Power BI, Metabase, Streamlit...) chega ao MESMO
número: a regra mora num lugar só.

Execução, da raiz do projeto:
    streamlit run app/dashboard.py
"""

from pathlib import Path

import duckdb
import streamlit as st

# ---------------------------------------------------------------------
# Onde está a Gold: ARQUIVOS Parquet. Sem servidor de banco.
# O DuckDB (motor OLAP embutido) consulta os arquivos direto do disco —
# a mesma separação storage × engine da aula.
# ---------------------------------------------------------------------
RAIZ = Path(__file__).resolve().parent.parent
GOLD = RAIZ / "data" / "gold"

st.set_page_config(page_title="Central de Serviços", page_icon="📊", layout="wide")


@st.cache_data  # cache: os Parquet só são relidos se mudarem de verdade
def carregar():
    con = duckdb.connect()
    fato = con.sql(f"select * from '{GOLD}/fato_chamado.parquet'").df()
    unidades = con.sql(f"select * from '{GOLD}/dim_unidade.parquet'").df()
    categorias = con.sql(f"select * from '{GOLD}/dim_categoria.parquet'").df()
    return fato, unidades, categorias


if not (GOLD / "fato_chamado.parquet").exists():
    st.error("Gold não encontrada. Rode antes:  python -m src.pipeline  e  dbt run")
    st.stop()

fato, unidades, categorias = carregar()

# ---------------------------------------------------------------------
# O STAR SCHEMA em ação: o join fato × dimensões acontece AQUI,
# no consumo — exatamente como desenhado na aula.
# ---------------------------------------------------------------------
df = (
    fato.merge(unidades, on="unidade_sk")
        .merge(categorias, on="categoria_sk")
)
# a SK de data é a "smart key" AAAAMMDD — o ano é os 4 primeiros
# dígitos, sem precisar de join com a dim_tempo
df["ano"] = df["data_abertura_sk"] // 10000

# ---------------------------- filtros --------------------------------
st.sidebar.header("Filtros (as dimensões!)")
f_unidade = st.sidebar.multiselect("Unidade", sorted(df["nome_unidade"].unique()))
f_categoria = st.sidebar.multiselect("Categoria", sorted(df["nome_categoria"].unique()))
f_ano = st.sidebar.multiselect("Ano (abertura)", sorted(df["ano"].unique()))

st.sidebar.caption(
    "Cada filtro é uma dimensão do cubo da aula: "
    "**unidade · categoria · período**."
)

if f_unidade:
    df = df[df["nome_unidade"].isin(f_unidade)]
if f_categoria:
    df = df[df["nome_categoria"].isin(f_categoria)]
if f_ano:
    df = df[df["ano"].isin(f_ano)]

# a medida só existe para chamados resolvidos com datas plausíveis —
# a decisão foi tomada na fato_chamado, NÃO aqui
resolvidos = df.dropna(subset=["tempo_atendimento_dias"])

# ------------------------------ KPIs ---------------------------------
st.title("📊 Central de Serviços — tempo de atendimento")
st.caption("Fonte: camada Gold (Parquet) · medida derivada e testada no pipeline dbt")

c1, c2, c3, c4 = st.columns(4)
c1.metric("Chamados (total)", len(df))
c2.metric("Resolvidos com medida", len(resolvidos))
c3.metric("Em andamento", int((df["situacao"] == "Em andamento").sum()))
c4.metric(
    "Tempo médio (dias)",
    f"{resolvidos['tempo_atendimento_dias'].mean():.1f}" if len(resolvidos) else "—",
)

# ----------------------------- gráficos ------------------------------
col_a, col_b = st.columns(2)

with col_a:
    st.subheader("Ranking por unidade")
    ranking = (
        resolvidos.groupby("nome_unidade")["tempo_atendimento_dias"]
        .mean().round(1).sort_values(ascending=False)
    )
    st.bar_chart(ranking)

with col_b:
    st.subheader("Evolução por ano de abertura")
    evolucao = (
        resolvidos.groupby("ano")["tempo_atendimento_dias"]
        .mean().round(1)
    )
    st.line_chart(evolucao)

st.subheader("Por categoria")
por_categoria = (
    resolvidos.groupby("nome_categoria")["tempo_atendimento_dias"]
    .agg(chamados="count", tempo_medio_dias="mean").round(1)
    .sort_values("tempo_medio_dias", ascending=False)
)
st.dataframe(por_categoria, use_container_width=True)

# ------------------------- rodapé didático ---------------------------
st.divider()
st.caption(
    "⚙️ Este dashboard tem ZERO regra de negócio: os nulos, os tempos "
    "negativos e a unidade inexistente foram decididos no pipeline — "
    "uma vez, para todos. Troque este Streamlit por Power BI ou Metabase "
    "e o número será o mesmo. **Essa é a função da Gold.**"
)
