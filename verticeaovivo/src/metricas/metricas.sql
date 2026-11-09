-- gold.mv_projetos: a fórmula de cada KPI da carteira num lugar só (metric view).
-- O dashboard, o Genie e o app leem daqui: SPI, CPI, estouro... sempre a mesma conta.
-- Fonte: a fotografia de hoje (16/10/2026), só os projetos em andamento.
-- Razão é SUM/SUM (dividir por último), nunca média de razões.
-- ATENÇÃO: nada de ponto e vírgula dentro do YAML (nem em comment): a sql_task do job
-- corta o arquivo em todo ponto e vírgula, inclusive dentro do bloco $$.
CREATE OR REPLACE VIEW lakehouse_vertice.gold.mv_projetos
WITH METRICS
LANGUAGE YAML
AS $$
version: 1.1
comment: "KPIs governados da carteira de projetos em andamento da Vértice, na fotografia de 16/10/2026. SPI e CPI abaixo de 0,9 = atenção, abaixo de 0,8 = crítico."
source: lakehouse_vertice.gold.projeto_situacao_atual
filter: status = 'em_andamento'

dimensions:
  - name: projeto_id
    expr: projeto
    comment: "Código do projeto, no formato PRJ-000"
    synonyms: ["código do projeto", "id do projeto", "projeto"]
  - name: projeto
    expr: nome_projeto
    comment: "Nome do projeto"
    synonyms: ["nome do projeto"]
  - name: cliente
    expr: cliente
    synonyms: ["empresa cliente", "conta"]
  - name: segmento
    expr: segmento
    comment: "Segmento do cliente (varejo, financeiro, saúde, logística, indústria)"
    synonyms: ["setor", "vertical", "indústria do cliente"]
  - name: ferramenta
    expr: ferramenta
    comment: "Onde o gerente controla o cronograma: excel, clickup ou msproject"
    synonyms: ["ferramenta de gestão", "ferramenta do cronograma"]
  - name: situacao
    expr: situacao
    comment: "ok, atenção (SPI ou CPI abaixo de 0,9) ou crítico (SPI ou CPI abaixo de 0,8)"
    synonyms: ["situação", "status de risco", "risco"]
  - name: farol_do_gerente
    expr: farol_do_gerente
    comment: "Último farol publicado pelo gerente no status semanal (verde, amarelo, vermelho)"
    synonyms: ["farol informado", "farol reportado", "farol do status"]
  - name: farol_calculado
    expr: farol_calculado
    comment: "Farol pela regra do manual da Vértice: verde com SPI a partir de 0,95, amarelo a partir de 0,90, vermelho abaixo"
    synonyms: ["farol pelo número", "farol real", "farol do SPI"]
  - name: gerente_projeto
    expr: gerente_projeto
    comment: "Gerente responsável pelo projeto"
    synonyms: ["gerente", "GP", "gestor do projeto"]

measures:
  - name: projetos
    expr: COUNT(1)
    comment: "Quantidade de projetos em andamento"
    synonyms: ["quantidade de projetos", "número de projetos", "total de projetos"]
  - name: carteira
    expr: SUM(valor_contrato)
    comment: "Soma do valor dos contratos em andamento, em reais"
    synonyms: ["valor da carteira", "valor dos contratos", "receita contratada"]
  - name: spi
    expr: SUM(ev) / SUM(pv)
    comment: "Índice de desempenho de prazo = EV ÷ PV (soma sobre soma). Abaixo de 1 é atraso"
    synonyms: ["SPI", "índice de prazo", "desempenho de prazo"]
  - name: cpi
    expr: SUM(ev) / SUM(ac)
    comment: "Índice de desempenho de custo = EV ÷ AC (soma sobre soma). Abaixo de 1 é estouro"
    synonyms: ["CPI", "índice de custo", "desempenho de custo"]
  - name: eac
    expr: SUM(eac)
    comment: "Custo final previsto (estimate at completion) = orçamento ÷ CPI, somado por projeto, em reais"
    synonyms: ["EAC", "custo final previsto", "estimativa no término"]
  - name: estouro_previsto
    expr: SUM(estouro_previsto)
    comment: "Quanto vai passar do orçamento = EAC − orçamento, só onde é positivo, em reais"
    synonyms: ["estouro", "estouro de orçamento", "quanto o atraso vai custar", "custo do atraso"]
  - name: margem_projetada
    expr: (SUM(valor_contrato) - SUM(eac)) / SUM(valor_contrato)
    comment: "Margem projetada = (valor do contrato − EAC) ÷ valor do contrato, de 0 a 1"
    synonyms: ["margem", "margem prevista"]
  - name: atraso_projetado_medio_dias
    expr: AVG(atraso_projetado_dias)
    comment: "Média do atraso projetado em dias = duração baseline ÷ SPI − duração baseline"
    synonyms: ["atraso médio", "atraso projetado médio", "dias de atraso médio"]
  - name: projetos_em_risco
    expr: COUNT(1) FILTER (WHERE situacao IN ('atenção', 'crítico'))
    comment: "Projetos em atenção ou críticos"
    synonyms: ["projetos em risco", "projetos atrasados", "em risco"]
  - name: projetos_criticos
    expr: COUNT(1) FILTER (WHERE situacao = 'crítico')
    comment: "Projetos com SPI ou CPI abaixo de 0,8"
    synonyms: ["críticos", "projetos críticos"]
  - name: projetos_melancia
    expr: COUNT(1) FILTER (WHERE melancia)
    comment: "Melancia = farol do gerente verde, mas SPI abaixo de 0,9 (verde por fora, vermelho por dentro)"
    synonyms: ["melancias", "farol verde atrasado", "verde mas atrasado"]
$$
