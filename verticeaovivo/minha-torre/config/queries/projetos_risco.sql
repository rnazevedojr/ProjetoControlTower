-- Projetos em andamento, do pior para o melhor, com a causa de bloqueio
-- mais frequente nos últimos 90 dias (desde 18/07/2026) e os dias de impacto
-- declarados por falta de SRE e por rotatividade (usados no simulador).
WITH causas AS (
  SELECT projeto_id, causa_bloqueio, count(*) AS semanas, sum(dias_impacto) AS dias
  FROM lakehouse_vertice.gold.status_estruturado
  WHERE data_status >= DATE'2026-07-18'
    AND causa_bloqueio NOT IN ('sem_bloqueio', 'nao_reportado')
  GROUP BY projeto_id, causa_bloqueio
),
por_projeto AS (
  SELECT
    projeto_id,
    max_by(causa_bloqueio, semanas)                                    AS causa_principal,
    max(semanas)                                                       AS semanas_causa_principal,
    coalesce(sum(CASE WHEN causa_bloqueio = 'falta_sre' THEN dias END), 0)    AS dias_falta_sre,
    coalesce(sum(CASE WHEN causa_bloqueio = 'rotatividade' THEN dias END), 0) AS dias_rotatividade
  FROM causas
  GROUP BY projeto_id
)
SELECT
  p.projeto,
  p.nome_projeto,
  p.cliente,
  p.gerente_projeto,
  p.situacao,
  CAST(p.spi AS DOUBLE)                         AS spi,
  CAST(p.cpi AS DOUBLE)                         AS cpi,
  CAST(p.estouro_previsto AS DOUBLE)            AS estouro_previsto,
  CAST(p.atraso_projetado_dias AS DOUBLE)       AS atraso_projetado_dias,
  p.farol_do_gerente,
  p.farol_calculado,
  p.melancia,
  coalesce(c.causa_principal, 'sem_bloqueio')   AS causa_principal,
  coalesce(c.semanas_causa_principal, 0)        AS semanas_causa_principal,
  CAST(coalesce(c.dias_falta_sre, 0) AS DOUBLE)    AS dias_falta_sre,
  CAST(coalesce(c.dias_rotatividade, 0) AS DOUBLE) AS dias_rotatividade
FROM lakehouse_vertice.gold.projeto_situacao_atual p
LEFT JOIN por_projeto c ON c.projeto_id = p.projeto
WHERE p.status = 'em_andamento'
ORDER BY
  CASE p.situacao WHEN 'crítico' THEN 1 WHEN 'atenção' THEN 2 ELSE 3 END,
  least(p.spi, p.cpi),
  p.projeto
