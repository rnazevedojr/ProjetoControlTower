-- silver.status_semanal e silver.custos.

CREATE OR REFRESH MATERIALIZED VIEW status_semanal (
  CONSTRAINT farol_valido EXPECT (farol IN ('verde', 'amarelo', 'vermelho')) ON VIOLATION FAIL UPDATE
)
COMMENT 'Status semanal que cada gerente reporta toda sexta: % concluído declarado, farol do gerente (verde, amarelo, vermelho) e o texto livre com bloqueios. Uma linha por projeto e sexta-feira. Status sem conteúdo (vazio, N/A, ver ata da reunião) ficam, marcados em status_vazio. É a fonte do histórico do avanço.'
AS SELECT
  projeto_id,
  to_date(data_status)          AS data_status,
  gerente,
  -- sujeira 17: 'Verde', 'VERDE'...
  lower(trim(farol))            AS farol,
  CAST(pct_concluido AS INT)    AS pct_concluido,
  texto_status,
  -- sujeira 18: status sem conteúdo NÃO é descartado, só sinalizado
  coalesce(trim(texto_status), '') IN ('', 'N/A', 'ver ata da reunião') AS status_vazio
FROM lakehouse_vertice.bronze.status_semanal;

CREATE OR REFRESH MATERIALIZED VIEW custos
COMMENT 'Lançamentos de custo real dos projetos (pessoal, consultoria, cloud, licenças, despesas), em reais. Valor líquido: estornos ficam como valor negativo, marcados em estorno. semana é a sexta-feira da semana do lançamento. Uma linha por lançamento.'
AS SELECT
  lancamento_id,
  projeto_id,
  to_date(data)                 AS data,
  -- a sexta da semana (date_trunc('WEEK') devolve a segunda)
  date_add(to_date(date_trunc('WEEK', to_date(data))), 4) AS semana,
  categoria,
  descricao,
  centro_custo,
  -- sujeira 13: 671 valores com vírgula decimal. replace ANTES do CAST:
  -- um try_cast jogaria R$ 5,4 mi fora em silêncio
  CAST(replace(valor, ',', '.') AS DECIMAL(14,2))      AS valor,
  -- sujeira 14: estorno fica (custo é líquido), só sinalizado
  CAST(replace(valor, ',', '.') AS DECIMAL(14,2)) < 0  AS estorno
FROM lakehouse_vertice.bronze.custos;
