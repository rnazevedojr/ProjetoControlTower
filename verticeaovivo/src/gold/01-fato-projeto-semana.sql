-- gold.fato_projeto_semana: a curva de valor agregado de cada projeto, semana a semana.
-- Uma linha por projeto e sexta-feira, da semana do início até hoje (DATE'2026-10-16').
-- Excel, ClickUp e Project só guardam o % de HOJE: o histórico do avanço vem do
-- status semanal (o % que o gerente publicou em cada sexta).
-- Armadilha do pipeline: janela dentro de agregação dá erro. Cada janela fica num
-- CTE e cada agregação em outro.

CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.fato_projeto_semana (
  CONSTRAINT pv_nao_negativo EXPECT (pv >= 0) ON VIOLATION FAIL UPDATE,
  CONSTRAINT ev_ate_o_orcamento EXPECT (ev <= orcamento) ON VIOLATION FAIL UPDATE
)
COMMENT 'Valor agregado de cada projeto por semana (sexta-feira), do início até 16/10/2026. pv = valor planejado (orçamento × fração do baseline decorrida, ponderada pelas horas das tarefas); ev = valor agregado (orçamento × % concluído do status semanal daquela sexta; projeto concluído mantém o último %); ac = custo real acumulado até a sexta; spi = ev/pv (< 1 é atraso), cpi = ev/ac (< 1 é estouro), eac = orçamento/cpi. Traz também o último farol publicado pelo gerente e as horas disponíveis, apontadas e ociosas do timesheet na semana. Uma linha por projeto e semana.'
AS WITH
-- 1) a espinha: uma linha por projeto e sexta-feira
semanas AS (
  SELECT
    projeto_id,
    orcamento_custo AS orcamento,
    explode(sequence(
      date_add(to_date(date_trunc('WEEK', data_inicio)), 4),   -- a sexta da semana do início
      DATE'2026-10-16',
      INTERVAL 1 WEEK)) AS semana
  FROM projetos
),

-- 2) PV: quanto do baseline de cada tarefa já devia ter passado naquela sexta
fracao_tarefa AS (
  SELECT
    s.projeto_id,
    s.semana,
    t.horas,
    CASE
      WHEN t.fim_baseline <= t.inicio_baseline THEN IF(s.semana >= t.fim_baseline, 1.0, 0.0)
      ELSE greatest(0.0, least(1.0,
             datediff(s.semana, t.inicio_baseline) / datediff(t.fim_baseline, t.inicio_baseline)))
    END AS fracao_baseline
  FROM semanas s
  JOIN tarefas t ON t.projeto_id = s.projeto_id
),
pv_semana AS (
  SELECT
    projeto_id,
    semana,
    sum(horas * fracao_baseline) / sum(horas) AS fracao_planejada
  FROM fracao_tarefa
  GROUP BY projeto_id, semana
),

-- 3) EV: o % do status daquela sexta. Sem status (projeto concluído não publica
--    mais), vale o último publicado. O mesmo vale para o farol.
status_carregado AS (
  SELECT
    s.projeto_id,
    s.semana,
    last_value(st.pct_concluido, true) OVER (PARTITION BY s.projeto_id ORDER BY s.semana) AS pct_concluido,
    last_value(st.farol, true)         OVER (PARTITION BY s.projeto_id ORDER BY s.semana) AS farol_do_gerente
  FROM semanas s
  LEFT JOIN status_semanal st
    ON st.projeto_id = s.projeto_id
   AND st.data_status = s.semana
),

-- 4) AC: custo real acumulado até a sexta (inclusive)
custo_dia AS (
  SELECT projeto_id, data, sum(valor) AS valor
  FROM custos
  GROUP BY projeto_id, data
),
ac_semana AS (
  SELECT s.projeto_id, s.semana, sum(c.valor) AS ac
  FROM semanas s
  JOIN custo_dia c
    ON c.projeto_id = s.projeto_id
   AND c.data <= s.semana
  GROUP BY s.projeto_id, s.semana
),

-- 5) horas do timesheet na semana
horas_semana AS (
  SELECT
    projeto_id,
    semana,
    sum(horas_disponiveis) AS horas_disponiveis,
    sum(horas_apontadas)   AS horas_apontadas
  FROM apontamentos
  GROUP BY projeto_id, semana
),

-- 6) junta tudo e calcula o valor em reais
valores AS (
  SELECT
    s.projeto_id,
    s.semana,
    s.orcamento,
    round(s.orcamento * coalesce(p.fracao_planejada, 0), 2)           AS pv,
    round(s.orcamento * coalesce(st.pct_concluido, 0) / 100, 2)       AS ev,
    round(coalesce(a.ac, 0), 2)                                        AS ac,
    st.pct_concluido,
    st.farol_do_gerente,
    h.horas_disponiveis,
    h.horas_apontadas,
    h.horas_disponiveis - h.horas_apontadas                           AS horas_ociosas
  FROM semanas s
  LEFT JOIN pv_semana        p  ON p.projeto_id  = s.projeto_id AND p.semana  = s.semana
  LEFT JOIN status_carregado st ON st.projeto_id = s.projeto_id AND st.semana = s.semana
  LEFT JOIN ac_semana        a  ON a.projeto_id  = s.projeto_id AND a.semana  = s.semana
  LEFT JOIN horas_semana     h  ON h.projeto_id  = s.projeto_id AND h.semana  = s.semana
)
SELECT
  projeto_id,
  semana,
  orcamento,
  pv,
  ev,
  ac,
  round(try_divide(ev, pv), 4)                                   AS spi,
  round(try_divide(ev, ac), 4)                                   AS cpi,
  round(try_divide(orcamento, round(try_divide(ev, ac), 4)), 2)  AS eac,
  pct_concluido,
  farol_do_gerente,
  horas_disponiveis,
  horas_apontadas,
  horas_ociosas
FROM valores;
