"""Regenera diagramas/ver-diagramas.html a partir dos arquivos .mmd.

Use depois de editar qualquer .mmd:
    python diagramas/gerar_html.py
"""
import html
import pathlib

AQUI = pathlib.Path(__file__).resolve().parent

TITULOS = {
    "01-modelo-relacional-origem.mmd": (
        "1. O modelo relacional da origem",
        "O sistema que gerou os quatro arquivos de <code>data/raw/</code>: normalizado e "
        "orientado a eventos. Repare que <b>chamado não tem data_fechamento</b> — o "
        'fechamento é uma interação do tipo "Encerramento" — e que <b>a unidade vem via '
        "equipe</b>.",
    ),
    "02-dag-pipeline.mmd": (
        "2. A DAG do pipeline",
        "O grafo que o dbt <b>deduz</b> dos <code>source()</code> e <code>ref()</code>. "
        "Ninguém escreve a ordem de execução. Repare que a fato não aponta para as "
        "dimensões: estrela é modelo lógico, DAG é ordem de construção.",
    ),
    "03-modelo-dimensional.mmd": (
        "3. O modelo dimensional da Gold",
        "O star schema implementado. Grão: uma linha = um chamado (118 linhas, 94 com "
        "medida). Só as chaves de dimensão ganham surrogate key.",
    ),
    "04-jornada-medallion.mmd": (
        "4. A jornada do dado",
        "As sete etapas do mapa da aula, cada uma virando código executável.",
    ),
}


def main():
    blocos = []
    for arq, (tit, desc) in TITULOS.items():
        codigo = (AQUI / arq).read_text(encoding="utf-8")
        blocos.append(
            f'\n  <section>\n    <h2>{tit}</h2>\n    <p class="desc">{desc}</p>\n'
            f'    <div class="mermaid">{html.escape(codigo)}</div>\n'
            f'    <p class="fonte">fonte: <code>diagramas/{arq}</code></p>\n  </section>'
        )

    modelo = (AQUI / "ver-diagramas.html").read_text(encoding="utf-8")
    ini = modelo.index("<section>") - 3
    fim = modelo.index("<script type=\"module\">")
    novo = modelo[:ini] + "".join(blocos) + "\n" + modelo[fim:]
    (AQUI / "ver-diagramas.html").write_text(novo, encoding="utf-8")
    print(f"ver-diagramas.html atualizado com {len(blocos)} diagramas")


if __name__ == "__main__":
    main()
