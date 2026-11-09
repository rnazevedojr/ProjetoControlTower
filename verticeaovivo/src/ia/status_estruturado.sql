-- gold.status_estruturado: o texto livre do status semanal vira coluna.
-- sql_task no warehouse, com o caminho completo das tabelas.
-- Três métodos, do mais barato ao mais caro:
--   regra         status vazio ou sem bloqueio (não precisa de IA)
--   ia            status COM bloqueio dos últimos 90 dias (ai_classify + ai_extract, uns 5 s cada)
--   palavra_chave o histórico mais antigo, por RLIKE
-- A tabela ACUMULA: o MERGE só insere status que ainda não foram classificados,
-- então a IA nunca é refeita para o mesmo status.
-- Atenção: nada de ponto e vírgula dentro de comentário ou string (a sql_task corta o arquivo neles).

-- a) a tabela (CREATE TABLE IF NOT EXISTS, nunca CREATE OR REPLACE)
CREATE TABLE IF NOT EXISTS lakehouse_vertice.gold.status_estruturado (
  projeto_id       STRING    COMMENT 'Código do projeto (PRJ-xxx)',
  data_status      DATE      COMMENT 'Sexta-feira do status semanal',
  farol            STRING    COMMENT 'Farol informado pelo gerente: verde, amarelo ou vermelho',
  causa_bloqueio   STRING    COMMENT 'Causa do bloqueio: change_freeze, falta_sre, dependencia_fornecedor, rotatividade, mudanca_escopo, bug_retrabalho, aprovacao_cliente, sem_bloqueio, nao_reportado (status vazio) ou outro',
  bloqueio         STRING    COMMENT 'O bloqueio relatado, em poucas palavras',
  quem_destrava    STRING    COMMENT 'Quem pode destravar o bloqueio (só preenchido pela IA)',
  dias_impacto     DOUBLE    COMMENT 'Dias de impacto no cronograma declarados no status (1 semana = 7)',
  metodo           STRING    COMMENT 'Como foi classificado: regra, ia ou palavra_chave',
  texto_status     STRING    COMMENT 'Texto original do status semanal',
  _classificado_em TIMESTAMP COMMENT 'Quando a linha foi classificada (carimbo do processamento)'
)
COMMENT 'Status semanal estruturado: para cada projeto e sexta, a causa do bloqueio, o bloqueio, quem destrava e os dias de impacto declarados. Os status com bloqueio dos últimos 90 dias são lidos por IA (ai_classify e ai_extract), o histórico por palavra-chave e os sem bloqueio por regra. Uma linha por projeto e data_status. Tabela incremental (MERGE).';

-- b) só os status novos entram
MERGE INTO lakehouse_vertice.gold.status_estruturado t
USING (
  WITH novos AS (
    SELECT s.*
    FROM lakehouse_vertice.silver.status_semanal s
    LEFT ANTI JOIN lakehouse_vertice.gold.status_estruturado e
      ON e.projeto_id = s.projeto_id
     AND e.data_status = s.data_status
  ),
  com_metodo AS (
    SELECT
      projeto_id,
      data_status,
      farol,
      texto_status,
      status_vazio,
      CASE
        WHEN status_vazio
          OR lower(texto_status) RLIKE 'bloqueios: nenhum|sem bloqueios|nada relevante' THEN 'regra'
        WHEN data_status >= DATE'2026-07-18'                                          THEN 'ia'
        ELSE 'palavra_chave'
      END AS metodo,
      -- dias de impacto pelo texto: 'impacto estimado de N dias' ou 'impacto estimado: 1 semana'
      coalesce(
        CAST(nullif(regexp_extract(lower(texto_status), 'impacto estimado de ([0-9]+) dias', 1), '') AS DOUBLE),
        CASE WHEN lower(texto_status) RLIKE 'impacto estimado: 1 semana' THEN 7.0 END
      ) AS dias_regex
    FROM novos
  ),
  -- a IA roda SÓ nestas linhas (~160)
  via_ia AS (
    SELECT
      *,
      ai_classify(
        texto_status,
        '["change_freeze","falta_sre","dependencia_fornecedor","rotatividade","mudanca_escopo","bug_retrabalho","aprovacao_cliente","sem_bloqueio"]',
        map('version', '2.0')
      ) AS classificacao,
      ai_extract(
        texto_status,
        '{"bloqueio":{"type":"string","description":"o bloqueio relatado no status, em poucas palavras"},"quem_destrava":{"type":"string","description":"quem pode destravar o bloqueio (pessoa, área, cliente ou fornecedor)"},"dias_impacto":{"type":"number","description":"dias de impacto no cronograma declarados no texto. 1 semana = 7"}}',
        map('version', '2.0')
      ) AS extracao
    FROM com_metodo
    WHERE metodo = 'ia'
  ),
  classificados AS (
    SELECT
      projeto_id, data_status, farol,
      classificacao:response[0]::STRING        AS causa_bloqueio,
      extracao:response:bloqueio::STRING       AS bloqueio,
      extracao:response:quem_destrava::STRING  AS quem_destrava,
      extracao:response:dias_impacto::DOUBLE   AS dias_impacto,
      metodo, texto_status
    FROM via_ia

    UNION ALL

    SELECT
      projeto_id, data_status, farol,
      CASE
        WHEN status_vazio      THEN 'nao_reportado'
        WHEN metodo = 'regra'  THEN 'sem_bloqueio'
        WHEN lower(texto_status) RLIKE 'freeze|congelamento|janela de deploy'               THEN 'change_freeze'
        WHEN lower(texto_status) RLIKE 'sre|infraestrutura|ambiente de homologação'         THEN 'falta_sre'
        WHEN lower(texto_status) RLIKE 'forge|consultoria|fornecedor'                       THEN 'dependencia_fornecedor'
        WHEN lower(texto_status) RLIKE 'saída de|rotatividade|onboarding'                   THEN 'rotatividade'
        WHEN lower(texto_status) RLIKE 'escopo|change request|regra de negócio'             THEN 'mudanca_escopo'
        WHEN lower(texto_status) RLIKE 'bugs|regressão|refazendo'                           THEN 'bug_retrabalho'
        WHEN lower(texto_status) RLIKE 'aprovação do cliente|homologação do cliente'        THEN 'aprovacao_cliente'
        ELSE 'outro'
      END                                                               AS causa_bloqueio,
      CASE WHEN metodo = 'palavra_chave'
           THEN nullif(regexp_extract(texto_status, 'Bloqueios: ([^.]*)', 1), '') END AS bloqueio,
      CAST(NULL AS STRING)                                              AS quem_destrava,
      dias_regex                                                        AS dias_impacto,
      metodo, texto_status
    FROM com_metodo
    WHERE metodo <> 'ia'
  )
  SELECT *, current_timestamp() AS _classificado_em
  FROM classificados
) s
ON  t.projeto_id  = s.projeto_id
AND t.data_status = s.data_status
WHEN NOT MATCHED THEN INSERT (
  projeto_id, data_status, farol, causa_bloqueio, bloqueio, quem_destrava,
  dias_impacto, metodo, texto_status, _classificado_em
) VALUES (
  s.projeto_id, s.data_status, s.farol, s.causa_bloqueio, s.bloqueio, s.quem_destrava,
  s.dias_impacto, s.metodo, s.texto_status, s._classificado_em
);

-- c) leitura: quantos status por método e causa
SELECT metodo, causa_bloqueio, count(*) AS status
FROM lakehouse_vertice.gold.status_estruturado
GROUP BY ALL
ORDER BY metodo, status DESC;
