-- silver.tarefas: AS TRÊS FERRAMENTAS VIRAM UMA.
-- Uma visão temporária por ferramenta, todas com as MESMAS colunas:
--   projeto_id, ferramenta, id_na_ferramenta, fase, tarefa, responsavel,
--   inicio_baseline, fim_baseline, inicio_real, fim_real,
--   pct_como_veio, horas, status_na_ferramenta
-- e no fim um UNION ALL numa materialized view.

-- ---------------------------------------------------------------------------
-- 1) Excel: 20 planilhas, tudo texto
-- ---------------------------------------------------------------------------
CREATE TEMPORARY VIEW tarefas_excel AS
SELECT
  -- de-para pelo nome do arquivo; se não casar (código vazio, ou o arquivo
  -- chegou sem acento), o PRJ-xxx está no próprio nome do arquivo
  coalesce(p.projeto_id, regexp_extract(e.arquivo, 'PRJ-[0-9]{3}', 0)) AS projeto_id,
  'excel'                       AS ferramenta,
  CAST(e.id AS STRING)          AS id_na_ferramenta,
  e.fase,
  e.tarefa,
  e.responsavel,
  -- sujeira 4: data com '/' é dd/MM/yyyy; sem '/' é número de série do Excel
  CASE WHEN e.inicio_previsto  LIKE '%/%' THEN to_date(e.inicio_previsto, 'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(e.inicio_previsto AS INT)) END  AS inicio_baseline,
  CASE WHEN e.termino_previsto LIKE '%/%' THEN to_date(e.termino_previsto, 'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(e.termino_previsto AS INT)) END AS fim_baseline,
  CASE WHEN e.inicio_real      LIKE '%/%' THEN to_date(e.inicio_real, 'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(nullif(trim(e.inicio_real), '') AS INT)) END  AS inicio_real,
  CASE WHEN e.termino_real     LIKE '%/%' THEN to_date(e.termino_real, 'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(nullif(trim(e.termino_real), '') AS INT)) END AS fim_real,
  -- sujeira 5: '45%' e '10,5%' (tira o % e troca a vírgula) ou 0.45 (fração, × 100)
  CASE WHEN contains(e.pct_concluido, '%')
       THEN CAST(replace(replace(e.pct_concluido, '%', ''), ',', '.') AS DOUBLE)
       ELSE CAST(e.pct_concluido AS DOUBLE) * 100 END AS pct_como_veio,
  -- sujeira 7: horas em '40h'
  CAST(replace(e.horas_previstas, 'h', '') AS DOUBLE) AS horas,
  CAST(NULL AS STRING)          AS status_na_ferramenta
FROM lakehouse_vertice.bronze.excel_tarefas e
LEFT JOIN lakehouse_vertice.bronze.projetos p
  ON p.codigo_ferramenta = e.arquivo
-- sujeira 6: a última linha de cada planilha é o TOTAL
WHERE e.tarefa <> 'TOTAL';

-- ---------------------------------------------------------------------------
-- 2) ClickUp: 25 listas, datas em milissegundos e campos dentro de custom_fields
-- ---------------------------------------------------------------------------
CREATE TEMPORARY VIEW tarefas_clickup AS
SELECT
  -- de-para pelo list_id; se o código faltar, o nome da lista é o nome do projeto
  coalesce(p.projeto_id, pn.projeto_id) AS projeto_id,
  'clickup'                     AS ferramenta,
  c.id                          AS id_na_ferramenta,
  filter(c.custom_fields, f -> f.name = 'Fase')[0].value AS fase,
  c.name                        AS tarefa,
  c.assignees[0].username       AS responsavel,
  -- sujeira 8: datas em milissegundos (as do baseline moram em custom_fields)
  to_date(timestamp_millis(CAST(filter(c.custom_fields, f -> f.name = 'Início baseline')[0].value AS BIGINT))) AS inicio_baseline,
  to_date(timestamp_millis(CAST(filter(c.custom_fields, f -> f.name = 'Fim baseline')[0].value AS BIGINT)))    AS fim_baseline,
  to_date(timestamp_millis(CAST(c.start_date AS BIGINT))) AS inicio_real,
  to_date(timestamp_millis(CAST(c.date_done  AS BIGINT))) AS fim_real,
  CAST(filter(c.custom_fields, f -> f.name = 'Progresso (%)')[0].value AS DOUBLE) AS pct_como_veio,
  c.time_estimate / 3600000.0   AS horas,
  -- sujeira 9: status escrito de 12 jeitos
  CASE
    WHEN lower(trim(c.status.status)) IN ('done', 'closed', 'concluído', 'concluido') THEN 'concluida'
    WHEN lower(trim(c.status.status)) IN ('to do', 'backlog', 'a fazer')              THEN 'a_fazer'
    ELSE 'em_andamento'   -- in progress, em andamento, doing, review
  END AS status_na_ferramenta
FROM lakehouse_vertice.bronze.clickup_tarefas c
LEFT JOIN lakehouse_vertice.bronze.projetos p
  ON p.codigo_ferramenta = c.list_id
LEFT JOIN lakehouse_vertice.bronze.projetos pn
  ON p.projeto_id IS NULL
 AND pn.nome_projeto = c.list_name;

-- ---------------------------------------------------------------------------
-- 3) MS Project: 15 XML, com tarefas-resumo e a fase fora da tarefa
-- ---------------------------------------------------------------------------
-- sujeira 11: a fase é a última tarefa-resumo de nível 1 antes da tarefa.
-- A janela fica num CTE; o filtro Summary = 0 vem só depois dela.
CREATE TEMPORARY VIEW tarefas_msproject AS
WITH com_fase AS (
  SELECT
    m.*,
    last_value(CASE WHEN m.OutlineLevel = 1 THEN m.Name END, true)
      OVER (PARTITION BY m.arquivo ORDER BY m.UID) AS fase
  FROM lakehouse_vertice.bronze.msproject_tarefas m
)
SELECT
  p.projeto_id,
  'msproject'                   AS ferramenta,
  CAST(m.UID AS STRING)         AS id_na_ferramenta,
  m.fase,
  m.Name                        AS tarefa,
  CAST(NULL AS STRING)          AS responsavel,
  to_date(m.Baseline.Start)     AS inicio_baseline,
  to_date(m.Baseline.Finish)    AS fim_baseline,
  to_date(m.ActualStart)        AS inicio_real,
  to_date(m.ActualFinish)       AS fim_real,
  CAST(m.PercentComplete AS DOUBLE) AS pct_como_veio,
  -- sujeira 12: horas em 'PT40H0M0S'
  CAST(regexp_extract(m.Work, 'PT([0-9]+)H', 1) AS DOUBLE) AS horas,
  CAST(NULL AS STRING)          AS status_na_ferramenta
FROM com_fase m
LEFT JOIN lakehouse_vertice.bronze.projetos p
  ON p.codigo_ferramenta = m.arquivo
-- sujeira 10: as tarefas-resumo somam as horas de baixo (contaria em dobro)
WHERE m.Summary = 0;

-- ---------------------------------------------------------------------------
-- 4) As três num modelo só
-- ---------------------------------------------------------------------------
CREATE OR REFRESH MATERIALIZED VIEW tarefas (
  CONSTRAINT achou_o_projeto EXPECT (projeto_id IS NOT NULL) ON VIOLATION FAIL UPDATE,
  CONSTRAINT pct_entre_0_e_100 EXPECT (pct_concluido BETWEEN 0 AND 100) ON VIOLATION FAIL UPDATE,
  CONSTRAINT horas_positivas EXPECT (horas > 0) ON VIOLATION FAIL UPDATE
)
COMMENT 'Tarefas dos cronogramas das três ferramentas (Excel, ClickUp e MS Project) num modelo só: projeto, fase, tarefa, responsável, datas baseline e reais, % concluído hoje (limitado a 100, com flag quando veio acima) e horas previstas. Uma linha por tarefa (sem linhas de TOTAL nem tarefas-resumo). É a fotografia de hoje: o histórico do avanço vem de status_semanal.'
AS WITH todas AS (
  SELECT * FROM tarefas_excel
  UNION ALL
  SELECT * FROM tarefas_clickup
  UNION ALL
  SELECT * FROM tarefas_msproject
)
SELECT
  concat_ws('-', projeto_id, ferramenta, id_na_ferramenta) AS tarefa_id,
  projeto_id,
  ferramenta,
  id_na_ferramenta,
  fase,
  tarefa,
  responsavel,
  inicio_baseline,
  fim_baseline,
  inicio_real,
  fim_real,
  pct_como_veio,
  least(pct_como_veio, 100.0) AS pct_concluido,
  pct_como_veio > 100         AS pct_veio_acima_de_100,
  horas,
  status_na_ferramenta
FROM todas;
