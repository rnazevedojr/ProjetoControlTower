-- Pessoas com utilização abaixo de 20% nas últimas 12 semanas (sextas depois de 24/07/2026),
-- por pessoa e projeto de origem, com horas paradas e custo ocioso MÉDIOS por semana.
SELECT
  u.colaborador_id,
  u.nome,
  u.papel,
  u.senioridade,
  u.projeto_id                                                        AS projeto_origem,
  CAST(c.custo_hora AS DOUBLE)                                        AS custo_hora,
  count(DISTINCT u.semana)                                            AS semanas,
  CAST(sum(u.horas_apontadas) / sum(u.horas_disponiveis) AS DOUBLE)   AS utilizacao,
  CAST(sum(u.horas_ociosas) / count(DISTINCT u.semana) AS DOUBLE)     AS horas_paradas_semana,
  CAST(sum(u.custo_ocioso) / count(DISTINCT u.semana) AS DOUBLE)      AS custo_ocioso_semana
FROM lakehouse_vertice.gold.utilizacao_pessoa_semana u
JOIN lakehouse_vertice.silver.colaboradores c ON c.colaborador_id = u.colaborador_id
WHERE u.semana > DATE'2026-07-24'
GROUP BY u.colaborador_id, u.nome, u.papel, u.senioridade, u.projeto_id, c.custo_hora
HAVING sum(u.horas_apontadas) / sum(u.horas_disponiveis) < 0.2
ORDER BY custo_ocioso_semana DESC
