-- silver.entregas_fornecedor: o prometido × o entregue pelas consultorias.
-- data_entrega vazia = entrega em aberto (não é sujeira).
-- O "hoje" do dataset é DATE'2026-10-16'.

CREATE OR REFRESH MATERIALIZED VIEW entregas_fornecedor
COMMENT 'Entregas das consultorias contratadas: fornecedor (nome normalizado), item, valor, datas do pedido, prometida e de entrega, prazo prometido e real em dias, dias de atraso, e as flags em_aberto e em_atraso (em aberto com data prometida antes de 16/10/2026). Uma linha por entrega.'
AS WITH base AS (
  SELECT
    entrega_id,
    projeto_id,
    -- sujeira 15: a CodeForge vem escrita de 4 jeitos
    CASE WHEN replace(lower(fornecedor), ' ', '') LIKE '%codeforge%'
         THEN 'CodeForge Consultoria Ltda'
         ELSE fornecedor END                    AS fornecedor,
    fornecedor                                  AS fornecedor_como_veio,
    item,
    CAST(valor AS DECIMAL(14,2))                AS valor,
    status,
    CAST(prazo_contratado_dias AS INT)          AS prazo_contratado_dias,
    to_date(data_pedido)                        AS data_pedido,
    to_date(data_prometida)                     AS data_prometida,
    to_date(nullif(trim(data_entrega), ''))     AS data_entrega
  FROM lakehouse_vertice.bronze.entregas_fornecedor
)
SELECT
  *,
  datediff(data_prometida, data_pedido)          AS prazo_prometido_dias,
  datediff(data_entrega, data_pedido)            AS prazo_real_dias,
  datediff(data_entrega, data_prometida)         AS dias_de_atraso_na_entrega,
  data_entrega IS NULL                           AS em_aberto,
  data_entrega IS NULL AND data_prometida < DATE'2026-10-16' AS em_atraso
FROM base;
