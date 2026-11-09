-- gold.projeto_situacao_atual e gold.utilizacao_pessoa_semana.
-- O "hoje" é DATE'2026-10-16'. Nunca current_date().

-- ---------------------------------------------------------------------------
-- A fotografia de hoje: uma linha por projeto, com o cadastro e os KPIs.
-- Aqui o % concluído vem das TAREFAS das ferramentas (o % de hoje), não do status.
-- ---------------------------------------------------------------------------
CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.projeto_situacao_atual (
  CONSTRAINT tem_projeto EXPECT (projeto IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT 'Fotografia de cada um dos 60 projetos em 16/10/2026: cadastro (cliente, segmento, tipo, ferramenta, gerente, valor do contrato, orçamento, datas e duração baseline, status) e os KPIs de valor agregado calculados sobre as tarefas das ferramentas: pv, ev, ac, spi (< 1 é atraso), cpi (< 1 é estouro), eac (custo final previsto), estouro_previsto (eac − orçamento, só quando positivo), margem_projetada, atraso_projetado_dias e termino_projetado. situacao: concluído, crítico (SPI ou CPI < 0,8), atenção (< 0,9) ou ok. farol_do_gerente é o último farol publicado no status; farol_calculado segue o manual da Vértice (verde com SPI >= 0,95, amarelo >= 0,90, vermelho abaixo). melancia: projeto em andamento com farol do gerente verde e SPI < 0,9.'
AS WITH
avanco AS (
  SELECT
    projeto_id,
    sum(horas) AS horas_totais,
    sum(horas * CASE
          WHEN fim_baseline <= inicio_baseline THEN IF(DATE'2026-10-16' >= fim_baseline, 1.0, 0.0)
          ELSE greatest(0.0, least(1.0,
                 datediff(DATE'2026-10-16', inicio_baseline) / datediff(fim_baseline, inicio_baseline)))
        END)                               AS horas_planejadas,
    sum(horas * pct_concluido / 100)       AS horas_agregadas
  FROM tarefas
  GROUP BY projeto_id
),
custo_ate_hoje AS (
  SELECT projeto_id, sum(valor) AS ac
  FROM custos
  WHERE data <= DATE'2026-10-16'
  GROUP BY projeto_id
),
ultimo_status AS (
  SELECT projeto_id, max_by(farol, data_status) AS farol_do_gerente
  FROM status_semanal
  WHERE data_status <= DATE'2026-10-16'
  GROUP BY projeto_id
),
kpis AS (
  SELECT
    p.*,
    datediff(p.data_fim_baseline, p.data_inicio)                        AS duracao_baseline_dias,
    round(p.orcamento_custo * a.horas_planejadas / a.horas_totais, 2)   AS pv,
    round(p.orcamento_custo * a.horas_agregadas  / a.horas_totais, 2)   AS ev,
    round(coalesce(c.ac, 0), 2)                                          AS ac,
    u.farol_do_gerente
  FROM projetos p
  LEFT JOIN avanco         a ON a.projeto_id = p.projeto_id
  LEFT JOIN custo_ate_hoje c ON c.projeto_id = p.projeto_id
  LEFT JOIN ultimo_status  u ON u.projeto_id = p.projeto_id
),
indices AS (
  SELECT
    *,
    round(try_divide(ev, pv), 4) AS spi,
    round(try_divide(ev, ac), 4) AS cpi
  FROM kpis
),
previsao AS (
  SELECT
    *,
    round(try_divide(orcamento_custo, cpi), 2) AS eac
  FROM indices
)
SELECT
  projeto_id                AS projeto,
  nome_projeto,
  cliente,
  segmento,
  tipo_projeto,
  ferramenta,
  gerente_projeto,
  valor_contrato,
  orcamento_custo           AS orcamento,
  data_inicio,
  data_fim_baseline,
  duracao_baseline_dias,
  status,
  pv,
  ev,
  ac,
  spi,
  cpi,
  eac,
  greatest(eac - orcamento_custo, 0)                                   AS estouro_previsto,
  round(try_divide(valor_contrato - eac, valor_contrato), 4)           AS margem_projetada,
  round(try_divide(duracao_baseline_dias, spi) - duracao_baseline_dias) AS atraso_projetado_dias,
  date_add(data_inicio, CAST(try_divide(duracao_baseline_dias, spi) AS INT)) AS termino_projetado,
  CASE
    WHEN status <> 'em_andamento'   THEN 'concluído'
    WHEN spi < 0.8 OR cpi < 0.8     THEN 'crítico'
    WHEN spi < 0.9 OR cpi < 0.9     THEN 'atenção'
    ELSE 'ok'
  END                                                                  AS situacao,
  farol_do_gerente,
  CASE
    WHEN spi >= 0.95 THEN 'verde'
    WHEN spi >= 0.90 THEN 'amarelo'
    ELSE 'vermelho'
  END                                                                  AS farol_calculado,
  coalesce(status = 'em_andamento' AND farol_do_gerente = 'verde' AND spi < 0.9, false) AS melancia
FROM previsao;

-- ---------------------------------------------------------------------------
-- Gente parada × gente pedida: o timesheet por pessoa, projeto e semana.
-- A gold não está no schema padrão do pipeline (silver): lê-se pelo nome completo.
-- ---------------------------------------------------------------------------
CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.utilizacao_pessoa_semana
COMMENT 'Utilização do timesheet por pessoa, projeto e semana (sexta-feira): nome, papel, senioridade, horas disponíveis, apontadas e ociosas, utilizacao (apontadas ÷ disponíveis, de 0 a 1), custo_ocioso (horas ociosas × custo por hora, em reais) e o spi_do_projeto naquela semana. Responde se há gente parada num projeto enquanto outro está atrasado.'
AS SELECT
  a.colaborador_id,
  c.nome,
  c.papel,
  c.senioridade,
  a.projeto_id,
  a.semana,
  a.horas_disponiveis,
  a.horas_apontadas,
  a.horas_disponiveis - a.horas_apontadas                              AS horas_ociosas,
  round(try_divide(a.horas_apontadas, a.horas_disponiveis), 4)          AS utilizacao,
  round((a.horas_disponiveis - a.horas_apontadas) * c.custo_hora, 2)    AS custo_ocioso,
  f.spi                                                                 AS spi_do_projeto
FROM apontamentos a
JOIN colaboradores c
  ON c.colaborador_id = a.colaborador_id
LEFT JOIN lakehouse_vertice.gold.fato_projeto_semana f
  ON f.projeto_id = a.projeto_id
 AND f.semana     = a.semana;
