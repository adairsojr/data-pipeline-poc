{#
  ler_bronze(tabela)
  ---------------------------------------------------------------------
  Devolve uma expressão delta_scan(...) apontando para a tabela Delta
  correspondente no Bronze.

  POR QUE UM MACRO?  O Bronze é Delta Lake, e Delta se lê com a função
  delta_scan() do DuckDB — não com o glob de Parquet (que leria os
  arquivos de TODAS as versões de uma vez, furando o log de transações).
  Centralizar isso num macro evita repetir o caminho em cada staging e
  deixa um ponto único para, no futuro, apontar para outro storage
  (S3/MinIO) sem tocar nos modelos.

  O caminho é RELATIVO ao diretório do projeto dbt (../data/bronze),
  exatamente como os `location` de cada modelo (../data/silver, ...).
  O dbt executa com o diretório de trabalho no projeto, então o caminho
  resolve igual em qualquer máquina (clone limpo, CI, VS Code).
#}
{% macro ler_bronze(tabela) %}
    delta_scan('../data/bronze/{{ tabela }}')
{% endmacro %}
