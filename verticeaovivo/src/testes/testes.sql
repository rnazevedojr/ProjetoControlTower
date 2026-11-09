-- Testes de qualidade da silver e da gold (sql_task, roda depois do medalhão).
-- Uma linha por teste: o que foi conferido, o que deu e 'ok'.
-- Se algum falhar, raise_error() derruba a tarefa dizendo qual teste e o valor obtido.
-- Um statement só, sem ';' no meio (a sql_task corta o arquivo em todo ';').
WITH testes AS (

  -- 1 · os 60 projetos têm cronograma na silver.tarefas
  SELECT 1 AS n, 'os 60 projetos têm cronograma na silver.tarefas' AS teste,
         count(DISTINCT projeto_id) = 60 AS passou,
         CAST(count(DISTINCT projeto_id) AS STRING) AS obtido
  FROM lakehouse_vertice.silver.tarefas

  UNION ALL
  -- 2 · cada projeto veio de UMA ferramenta, a do cadastro do PMO
  SELECT 2, 'cada projeto veio de uma ferramenta só, a do cadastro do PMO',
         count_if(n_ferramentas <> 1 OR ferramenta_tarefas <> ferramenta_cadastro) = 0,
         concat(count_if(n_ferramentas <> 1 OR ferramenta_tarefas <> ferramenta_cadastro), ' projetos fora da regra')
  FROM (
    SELECT t.projeto_id,
           count(DISTINCT t.ferramenta) AS n_ferramentas,
           min(t.ferramenta)            AS ferramenta_tarefas,
           min(p.ferramenta)            AS ferramenta_cadastro
    FROM lakehouse_vertice.silver.tarefas t
    JOIN lakehouse_vertice.silver.projetos p ON p.projeto_id = t.projeto_id
    GROUP BY t.projeto_id
  )

  UNION ALL
  -- 3 · as horas do Excel na silver = a soma das linhas de TOTAL das planilhas
  SELECT 3, 'horas do Excel na silver = soma das linhas de TOTAL das planilhas',
         abs(silver_h - total_h) < 0.01,
         concat('silver ', silver_h, ' × TOTAL ', total_h)
  FROM (
    SELECT
      (SELECT sum(horas) FROM lakehouse_vertice.silver.tarefas WHERE ferramenta = 'excel') AS silver_h,
      (SELECT sum(CAST(replace(horas_previstas, 'h', '') AS DOUBLE))
         FROM lakehouse_vertice.bronze.excel_tarefas WHERE tarefa = 'TOTAL')              AS total_h
  )

  UNION ALL
  -- 4 · uma linha por pessoa na silver
  SELECT 4, 'uma linha por pessoa na silver.colaboradores',
         count(*) = count(DISTINCT colaborador_id),
         concat(count(*), ' linhas, ', count(DISTINCT colaborador_id), ' pessoas')
  FROM lakehouse_vertice.silver.colaboradores

  UNION ALL
  -- 5 · a CodeForge virou um fornecedor só
  SELECT 5, 'a CodeForge virou um fornecedor só',
         count(DISTINCT fornecedor) = 1,
         concat(count(DISTINCT fornecedor), ' grafia(s)')
  FROM lakehouse_vertice.silver.entregas_fornecedor
  WHERE replace(lower(fornecedor), ' ', '') LIKE '%codeforge%'

  UNION ALL
  -- 6 · a limpeza não mudou o custo total (bronze com replace = silver)
  SELECT 6, 'a limpeza não mudou o custo total (bronze = silver)',
         bronze_v = silver_v,
         concat('bronze ', bronze_v, ' × silver ', silver_v)
  FROM (
    SELECT
      (SELECT sum(CAST(replace(valor, ',', '.') AS DECIMAL(14,2))) FROM lakehouse_vertice.bronze.custos) AS bronze_v,
      (SELECT sum(valor) FROM lakehouse_vertice.silver.custos)                                           AS silver_v
  )

  UNION ALL
  -- 7 · os 60 projetos têm fotografia de hoje
  SELECT 7, 'os 60 projetos têm fotografia de hoje (projeto_situacao_atual)',
         count(*) = 60 AND count(DISTINCT projeto) = 60,
         concat(count(*), ' linhas, ', count(DISTINCT projeto), ' projetos')
  FROM lakehouse_vertice.gold.projeto_situacao_atual

  UNION ALL
  -- 8 · todo projeto em andamento tem SPI e CPI
  SELECT 8, 'todo projeto em andamento tem SPI e CPI',
         count_if(spi IS NULL OR cpi IS NULL) = 0,
         concat(count_if(spi IS NULL OR cpi IS NULL), ' sem SPI ou CPI')
  FROM lakehouse_vertice.gold.projeto_situacao_atual
  WHERE status = 'em_andamento'

  UNION ALL
  -- 9 · o EV de hoje do status semanal bate com o das ferramentas (diferença < 1%, na carteira)
  SELECT 9, 'EV de hoje: status semanal × ferramentas (diferença < 1% na carteira)',
         abs(ev_status - ev_ferramentas) / ev_ferramentas < 0.01,
         concat('diferença de ', round(100 * abs(ev_status - ev_ferramentas) / ev_ferramentas, 2), '%')
  FROM (
    SELECT
      (SELECT sum(ev) FROM lakehouse_vertice.gold.fato_projeto_semana WHERE semana = DATE'2026-10-16') AS ev_status,
      (SELECT sum(ev) FROM lakehouse_vertice.gold.projeto_situacao_atual)                             AS ev_ferramentas
  )

  UNION ALL
  -- 10 · AC de hoje no fato = soma dos lançamentos até hoje
  SELECT 10, 'AC de hoje no fato = soma dos lançamentos até 16/10/2026',
         abs(ac_fato - ac_custos) < 0.01,
         concat('fato ', ac_fato, ' × lançamentos ', ac_custos)
  FROM (
    SELECT
      (SELECT sum(ac) FROM lakehouse_vertice.gold.fato_projeto_semana WHERE semana = DATE'2026-10-16') AS ac_fato,
      (SELECT sum(valor) FROM lakehouse_vertice.silver.custos WHERE data <= DATE'2026-10-16')          AS ac_custos
  )
)
SELECT
  n,
  teste,
  obtido,
  CASE WHEN passou THEN 'ok'
       ELSE raise_error(concat('teste ', n, ' falhou: ', teste, ' (', obtido, ')'))
  END AS resultado
FROM testes
ORDER BY n
