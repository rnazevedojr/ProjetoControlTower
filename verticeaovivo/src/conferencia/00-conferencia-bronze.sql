-- Conferência da bronze, antes da silver.
-- Uma linha por tabela: quantas linhas esperávamos (seed 42) e quantas chegaram.
-- Se alguma divergir, raise_error() derruba a tarefa e o medalhão nem começa.
-- bronze.feriados fica de fora: ela cresce a cada execução da ingestão.
-- Um statement só, sem ';' no meio (a sql_task corta o arquivo em todo ';').
WITH esperado AS (
  SELECT * FROM VALUES
    ('projetos',               60),
    ('status_semanal',       3911),
    ('excel_tarefas',        1663),
    ('clickup_tarefas',      2119),
    ('msproject_tarefas',    1260),
    ('colaboradores',         523),
    ('apontamentos',        30883),
    ('custos',              23640),
    ('entregas_fornecedor',   640)
  AS t(tabela, esperado)
),
obtido AS (
  SELECT 'projetos'            AS tabela, count(*) AS obtido FROM lakehouse_vertice.bronze.projetos
  UNION ALL SELECT 'status_semanal',      count(*) FROM lakehouse_vertice.bronze.status_semanal
  UNION ALL SELECT 'excel_tarefas',       count(*) FROM lakehouse_vertice.bronze.excel_tarefas
  UNION ALL SELECT 'clickup_tarefas',     count(*) FROM lakehouse_vertice.bronze.clickup_tarefas
  UNION ALL SELECT 'msproject_tarefas',   count(*) FROM lakehouse_vertice.bronze.msproject_tarefas
  UNION ALL SELECT 'colaboradores',       count(*) FROM lakehouse_vertice.bronze.colaboradores
  UNION ALL SELECT 'apontamentos',        count(*) FROM lakehouse_vertice.bronze.apontamentos
  UNION ALL SELECT 'custos',              count(*) FROM lakehouse_vertice.bronze.custos
  UNION ALL SELECT 'entregas_fornecedor', count(*) FROM lakehouse_vertice.bronze.entregas_fornecedor
)
SELECT
  e.tabela,
  e.esperado,
  o.obtido,
  CASE
    WHEN o.obtido = e.esperado THEN 'ok'
    ELSE raise_error(concat(
      'bronze.', e.tabela, ': esperado ', e.esperado, ' linhas, obtido ', coalesce(o.obtido, 0),
      '. Olhe a saída da tarefa ingestao_data_lake (download do data lake e read_files).'))
  END AS resultado
FROM esperado e
LEFT JOIN obtido o USING (tabela)
ORDER BY e.tabela
