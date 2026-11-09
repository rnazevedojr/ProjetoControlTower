-- silver.projetos: o cadastro do PMO, e o de-para da integração.
-- Cada projeto diz em qual ferramenta o gerente controla o cronograma
-- (ferramenta) e qual é o código dele lá dentro (codigo_ferramenta).

CREATE OR REFRESH MATERIALIZED VIEW projetos (
  CONSTRAINT data_inicio_valida EXPECT (data_inicio IS NOT NULL) ON VIOLATION FAIL UPDATE,
  CONSTRAINT ferramenta_conhecida EXPECT (ferramenta IN ('excel', 'clickup', 'msproject')) ON VIOLATION FAIL UPDATE
)
COMMENT 'Cadastro dos 60 projetos da Vértice (PMO): cliente, segmento, tipo, gerente, valor do contrato, orçamento de custo, datas de início e fim baseline, situação e a ferramenta onde o cronograma é controlado (excel, clickup ou msproject) com o código do projeto nela. Uma linha por projeto.'
AS SELECT
  projeto_id,
  nome_projeto,
  cliente,
  segmento,
  tipo_projeto,
  gerente_projeto,
  status,

  -- sujeira 2: a ferramenta veio escrita de 8 jeitos (MS Project, Project, Clickup, Planilha...)
  CASE
    WHEN lower(ferramenta) LIKE '%click%'   THEN 'clickup'
    WHEN lower(ferramenta) LIKE '%project%' THEN 'msproject'
    WHEN lower(ferramenta) LIKE '%excel%'
      OR lower(ferramenta) LIKE '%planilha%' THEN 'excel'
  END AS ferramenta,
  ferramenta AS ferramenta_como_veio,

  -- sujeira 3: dois projetos chegaram sem o código na ferramenta
  nullif(trim(codigo_ferramenta), '') AS codigo_ferramenta,

  CAST(valor_contrato  AS DECIMAL(14,2)) AS valor_contrato,
  CAST(orcamento_custo AS DECIMAL(14,2)) AS orcamento_custo,

  -- sujeira 1: 24 dos 60 vieram em dd/MM/yyyy
  coalesce(try_to_date(data_inicio, 'yyyy-MM-dd'), try_to_date(data_inicio, 'dd/MM/yyyy')) AS data_inicio,
  coalesce(try_to_date(data_fim_baseline, 'yyyy-MM-dd'), try_to_date(data_fim_baseline, 'dd/MM/yyyy')) AS data_fim_baseline
FROM lakehouse_vertice.bronze.projetos;
