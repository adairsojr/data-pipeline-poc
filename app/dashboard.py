"""Dashboard da evasão escolar (INEP) — o CONSUMO da camada Gold.

Este é o último elo da jornada: Fontes -> Bronze -> Silver -> Gold -> AQUI.

Repare no que este dashboard NÃO faz:
    - não limpa dado (a Silver já limpou);
    - não calcula a métrica (a Gold já derivou abandono_combinado);
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

RAIZ = Path(__file__).resolve().parent.parent
GOLD = RAIZ / "data" / "gold"

st.set_page_config(page_title="Evasão escolar (INEP)", page_icon="🎓", layout="wide")


@st.cache_data
def carregar():
    con = duckdb.connect()
    fato = con.sql(f"select * from '{GOLD}/fato_taxa.parquet'").df()
    ufs = con.sql(f"select * from '{GOLD}/dim_uf.parquet'").df()
    return fato, ufs


if not (GOLD / "fato_taxa.parquet").exists():
    st.error("Gold não encontrada. Rode antes:  python -m src.pipeline  e  dbt build")
    st.stop()

fato, ufs = carregar()

# O STAR SCHEMA em ação: o join fato x dimensão acontece AQUI, no consumo.
df = fato.merge(ufs, on="uf_sk")

# ---------------------------- filtros --------------------------------
st.sidebar.header("Filtros (as dimensões!)")
f_regiao = st.sidebar.multiselect("Região", sorted(df["regiao"].unique()))
f_uf = st.sidebar.multiselect("UF", sorted(df["uf"].unique()))

#st.sidebar.caption("Cada filtro é uma dimensão do cubo: **região · UF**.")

if f_regiao:
    df = df[df["regiao"].isin(f_regiao)]
if f_uf:
    df = df[df["uf"].isin(f_uf)]

# a métrica derivada só existe para municípios com taxa válida — a decisão
# foi tomada na fato_taxa, NÃO aqui
validos = df.dropna(subset=["abandono_combinado"])

# ------------------------------ KPIs ---------------------------------
st.title("Evasão escolar por município — INEP 2023")
#st.caption("Fonte: camada Gold (Parquet) · métrica derivada e testada no pipeline dbt")

c1, c2, c3 = st.columns(3)
c1.metric("Municípios", len(df))
c2.metric(
    "Evasão média (%)",
    f"{validos['abandono_combinado'].mean():.2f}".replace(".", ",")
    if len(validos) else "—",
)
c3.metric(
    "Evasão máxima (%)",
    f"{validos['abandono_combinado'].max():.2f}".replace(".", ",")
    if len(validos) else "—",
)

# ----------------------------- gráficos ------------------------------
col_a, col_b = st.columns(2)

with col_a:
    st.subheader("Evasão média por região")
    por_regiao = (
        validos.groupby("regiao")["abandono_combinado"]
        .mean().round(2).sort_values(ascending=False)
    )
    st.bar_chart(por_regiao)

with col_b:
    st.subheader("Evasão média por UF")
    por_uf = (
        validos.groupby("uf")["abandono_combinado"]
        .mean().round(2).sort_values(ascending=False)
    )
    st.bar_chart(por_uf)

st.subheader("Fundamental x Médio (evasão média por região)")
etapas = (
    validos.groupby("regiao")
    .agg(
        fundamental=("taxa_abandono_fund", "mean"),
        medio=("taxa_abandono_med", "mean"),
    )
)
# média das duas colunas por região
etapas = (
    validos.groupby("regiao")[["taxa_abandono_fund", "taxa_abandono_med"]]
    .mean().round(2)
    .rename(columns={"taxa_abandono_fund": "Fundamental", "taxa_abandono_med": "Médio"})
    .sort_values("Médio", ascending=False)
)
st.bar_chart(etapas)

# ------------------------- rodapé didático ---------------------------
st.divider()
#st.caption(
#    "⚙️ Este dashboard tem ZERO regra de negócio: a vírgula decimal, a UF "
#    "órfã e a taxa implausível foram decididas no pipeline — uma vez, para "
#    "todos. Troque este Streamlit por Power BI ou Metabase e o número será "
#    "o mesmo. **Essa é a função da Gold.**"
#)
