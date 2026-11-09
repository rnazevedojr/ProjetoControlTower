-- KPIs da carteira em andamento (fotografia de 16/10/2026).
-- Nada do score aqui: ele pode não existir (vem da rota /api/score-estouro).
SELECT
  count(*)                                        AS em_andamento,
  count_if(situacao IN ('atenção', 'crítico'))    AS em_risco,
  count_if(situacao = 'crítico')                  AS criticos,
  count_if(melancia)                              AS melancias,
  CAST(sum(estouro_previsto) AS DOUBLE)           AS estouro_previsto,
  CAST(sum(valor_contrato) AS DOUBLE)             AS carteira
FROM lakehouse_vertice.gold.projeto_situacao_atual
WHERE status = 'em_andamento'
