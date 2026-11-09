-- silver.colaboradores e silver.apontamentos.

-- sujeira 16: COL0102, COL0257 e COL0433 vieram duas vezes (a cópia em CAIXA ALTA).
-- Fica o cadastro com papel em minúsculas. A janela num CTE, o filtro depois.
CREATE OR REFRESH MATERIALIZED VIEW colaboradores
COMMENT 'As 520 pessoas da Vértice: nome, papel (dev, qa, sre...), senioridade, custo por hora, data de admissão e de desligamento. Uma linha por pessoa (os 3 cadastros duplicados foram resolvidos).'
AS WITH ordenado AS (
  SELECT
    *,
    row_number() OVER (
      PARTITION BY colaborador_id
      ORDER BY CASE WHEN papel = lower(papel) THEN 0 ELSE 1 END
    ) AS ordem
  FROM lakehouse_vertice.bronze.colaboradores
)
SELECT
  colaborador_id,
  nome,
  papel,
  senioridade,
  CAST(custo_hora AS DECIMAL(10,2))  AS custo_hora,
  to_date(data_admissao)             AS data_admissao,
  to_date(nullif(trim(data_desligamento), '')) AS data_desligamento
FROM ordenado
WHERE ordem = 1;

CREATE OR REFRESH MATERIALIZED VIEW apontamentos
COMMENT 'Timesheet semanal: horas disponíveis e horas apontadas por pessoa e projeto. semana é a sexta-feira da semana (semana_inicio é a segunda). Uma linha por pessoa, projeto e semana.'
AS SELECT
  colaborador_id,
  projeto_id,
  to_date(semana_inicio)                   AS semana_inicio,
  date_add(to_date(semana_inicio), 4)      AS semana,
  CAST(horas_disponiveis AS DECIMAL(6,1))  AS horas_disponiveis,
  CAST(horas_apontadas   AS DECIMAL(6,1))  AS horas_apontadas
FROM lakehouse_vertice.bronze.apontamentos;
