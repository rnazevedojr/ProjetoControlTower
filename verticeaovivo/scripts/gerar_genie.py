#!/usr/bin/env python3
"""Gera o Genie "Farol · Diretoria" como código: resources/farol.geniespace.json.

O JSON é o serialized_space (versão 2) que o recurso do bundle
(resources/genie.genie_space.yml) publica no deploy. Não edite o JSON à mão:
mude este script e gere de novo.

O score do modelo (gold.score_estouro_30d) entra SÓ se a tabela existir
(databricks tables exists). Sem ela, nenhuma instrução nem exemplo fala de score.

Uso:
  python3 scripts/gerar_genie.py --profile DEFAULT
"""
import argparse, json, pathlib, subprocess

RAIZ = pathlib.Path(__file__).resolve().parent.parent
SAIDA = RAIZ / "resources" / "farol.geniespace.json"
C = "lakehouse_vertice"

TABELAS = [
    f"{C}.gold.fato_projeto_semana",
    f"{C}.gold.projeto_situacao_atual",
    f"{C}.gold.status_estruturado",
    f"{C}.gold.utilizacao_pessoa_semana",
    f"{C}.silver.entregas_fornecedor",
]
TABELA_SCORE = f"{C}.gold.score_estouro_30d"
METRIC_VIEWS = [f"{C}.gold.mv_projetos"]

PERGUNTAS_DO_DONO = [
    "Quais projetos estão atrasados, e de quais clientes?",
    "Quanto esse atraso vai me custar?",
    "Tenho gente parada enquanto outro projeto pede gente?",
    "O que vai dar errado no próximo mês?",
]

# ---------------------------------------------------------------------------
# Instruções de texto (o Genie aceita UM item, com várias linhas)
# ---------------------------------------------------------------------------
INSTRUCOES = [
    "QUEM PERGUNTA: o dono da Vértice Tecnologia e a diretoria. Responda em português, direto, com números em R$ e índices com 2 casas decimais.",
    "HOJE é 2026-10-16 (sexta-feira). Nunca use current_date(): escreva DATE'2026-10-16'. "
    "'Últimos 90 dias' = data_status >= DATE'2026-07-18'. 'Últimas 12 semanas' = semana > DATE'2026-07-24'. "
    "'Próximo mês' = de 2026-10-17 a 2026-11-16.",
    "FÓRMULAS: SPI = EV ÷ PV (abaixo de 1 é atraso). CPI = EV ÷ AC (abaixo de 1 é estouro). EAC = orçamento ÷ CPI. "
    "Estouro previsto = EAC − orçamento, só quando positivo. Margem projetada = (valor do contrato − EAC) ÷ valor do contrato. "
    "Atraso projetado (dias) = duração baseline ÷ SPI − duração baseline.",
    "REGRAS DE CORTE: SPI ou CPI < 0,9 = atenção, < 0,8 = crítico. A coluna situacao já traz isso: 'ok', 'atenção', 'crítico' "
    "(com acento) ou 'concluído'. 'Projetos atrasados' ou 'em risco' = situacao IN ('atenção', 'crítico').",
    "QUAL TABELA: para TOTAIS da carteira de hoje (SPI, CPI, estouro previsto, carteira, margem, quantos críticos/em risco/melancias) "
    "use a metric view gold.mv_projetos com MEASURE() (ela já filtra status = 'em_andamento'). "
    "Para RANKING, listas e um projeto específico use gold.projeto_situacao_atual com WHERE status = 'em_andamento' "
    "(o código do projeto está na coluna projeto, ex.: 'PRJ-011'). SPI ou CPI de UM projeto: ROUND(spi, 2) da projeto_situacao_atual.",
    "HISTÓRICO: gold.fato_projeto_semana tem uma linha por projeto e sexta-feira (coluna semana). PV, EV e AC são ACUMULADOS: "
    "nunca some semanas. Para o valor de uma semana, filtre semana = a sexta pedida e leia spi/cpi direto.",
    "FAROL E MELANCIA: farol_do_gerente é o que o gerente publicou; farol_calculado é a regra do manual (verde com SPI >= 0,95, "
    "amarelo >= 0,90, vermelho abaixo). Melancia = farol do gerente verde e SPI < 0,9: use a coluna booleana melancia "
    "(WHERE melancia). 'Farol verde mas atrasado' é melancia.",
    "POR QUE O PROJETO X ATRASOU: use gold.status_estruturado dos últimos 90 dias (data_status >= DATE'2026-07-18'), "
    "sem causa_bloqueio IN ('sem_bloqueio', 'nao_reportado'), agrupe por causa_bloqueio e ordene por COUNT(*) DESC "
    "(a principal causa é a de maior contagem), com SUM(dias_impacto). Traga junto o SPI de hoje do projeto. "
    "Se a causa for falta_sre, mostre também os SREs ociosos (gente parada com papel = 'sre').",
    "GENTE PARADA: utilização < 20% nas últimas 12 semanas, calculada por pessoa como SUM(horas_apontadas) / SUM(horas_disponiveis) "
    "em gold.utilizacao_pessoa_semana com semana > DATE'2026-07-24', agrupando por colaborador_id (papel = 'sre' quando perguntarem de SRE). "
    "'Outro projeto pede gente' = projetos em atenção/crítico cuja causa no status é falta_sre ou rotatividade.",
    "FORNECEDOR: o desempenho é prazo real ÷ prometido em silver.entregas_fornecedor: AVG(prazo_real_dias / prazo_prometido_dias) "
    "por fornecedor (acima de 1 = atrasa). Entrega em atraso hoje = coluna em_atraso (em aberto e data_prometida antes de 2026-10-16).",
    "O QUE VAI DAR ERRADO NO PRÓXIMO MÊS: junte (1) as entregas de consultoria em atraso hoje (silver.entregas_fornecedor WHERE em_atraso, "
    "com fornecedor e projeto) e (2) o change freeze de varejo da Black Friday, de 01/11/2026 a 10/01/2027, que trava deploys "
    "nos projetos de e-commerce em andamento: tipo_projeto com 'commerce', 'checkout' ou 'marketplace' "
    "(lower(tipo_projeto) LIKE '%commerce%' OR LIKE '%checkout%' OR LIKE '%marketplace%'). Diga o que fazer: cobrar o fornecedor, "
    "antecipar entregas antes do freeze e realocar gente parada para os projetos críticos.",
    "QUAIS CLIENTES: devolva cada cliente UMA vez (SELECT DISTINCT cliente).",
    "FERRAMENTA: ferramenta é 'excel', 'clickup' ou 'msproject' (minúsculas).",
]

INSTRUCOES_SCORE = [
    "SCORE DO MODELO: gold.score_estouro_30d traz a chance de cada projeto terminar o próximo mês com SPI abaixo de 0,9 "
    "(prob_estouro_30d de 0 a 1, faixa_risco 'alto' >= 0,5, 'medio' >= 0,2, 'baixo'). Use sempre a data_referencia mais recente. "
    "No 'o que vai dar errado no próximo mês', acrescente os projetos com situacao = 'ok' hoje e faixa_risco 'alto' ou 'medio', "
    "com principais_fatores.",
]

# ---------------------------------------------------------------------------
# Um exemplo de SQL para cada pergunta do dono
# ---------------------------------------------------------------------------
G = f"{C}.gold"
EXEMPLOS = [
    (PERGUNTAS_DO_DONO[0], f"""SELECT projeto, nome_projeto, cliente, situacao, ROUND(spi, 2) AS spi, ROUND(cpi, 2) AS cpi,
       ROUND(estouro_previsto, 2) AS estouro_previsto, farol_do_gerente, melancia
FROM {G}.projeto_situacao_atual
WHERE status = 'em_andamento' AND situacao IN ('atenção', 'crítico')
ORDER BY CASE situacao WHEN 'crítico' THEN 1 ELSE 2 END, LEAST(spi, cpi)"""),
    (PERGUNTAS_DO_DONO[1], f"""SELECT ROUND(MEASURE(estouro_previsto), 2) AS estouro_previsto,
       ROUND(MEASURE(margem_projetada), 4) AS margem_projetada,
       ROUND(MEASURE(spi), 2) AS spi, ROUND(MEASURE(cpi), 2) AS cpi,
       MEASURE(projetos_em_risco) AS projetos_em_risco
FROM {G}.mv_projetos"""),
    (PERGUNTAS_DO_DONO[2], f"""WITH parados AS (
  SELECT colaborador_id, nome, papel, projeto_id AS projeto_origem,
         SUM(horas_apontadas) / SUM(horas_disponiveis) AS utilizacao,
         SUM(horas_ociosas) / COUNT(DISTINCT semana) AS horas_paradas_semana,
         SUM(custo_ocioso) AS custo_ocioso_12_semanas
  FROM {G}.utilizacao_pessoa_semana
  WHERE semana > DATE'2026-07-24'
  GROUP BY colaborador_id, nome, papel, projeto_id
  HAVING SUM(horas_apontadas) / SUM(horas_disponiveis) < 0.2
),
pedindo AS (
  SELECT projeto_id, causa_bloqueio, COUNT(*) AS semanas, SUM(dias_impacto) AS dias_impacto
  FROM {G}.status_estruturado
  WHERE data_status >= DATE'2026-07-18' AND causa_bloqueio IN ('falta_sre', 'rotatividade')
  GROUP BY projeto_id, causa_bloqueio
)
SELECT p.colaborador_id, p.nome, p.papel, p.projeto_origem, ROUND(p.utilizacao, 3) AS utilizacao,
       ROUND(p.custo_ocioso_12_semanas, 2) AS custo_ocioso_12_semanas,
       d.projeto_id AS projeto_pedindo_gente, d.causa_bloqueio, d.semanas, d.dias_impacto
FROM parados p
LEFT JOIN pedindo d ON (p.papel = 'sre' AND d.causa_bloqueio = 'falta_sre')
                    OR (p.papel <> 'sre' AND d.causa_bloqueio = 'rotatividade')
ORDER BY p.custo_ocioso_12_semanas DESC, d.dias_impacto DESC"""),
    (PERGUNTAS_DO_DONO[3], f"""SELECT 'entrega de consultoria em atraso' AS risco, e.projeto_id AS projeto, e.fornecedor AS detalhe,
       e.item, e.data_prometida, DATEDIFF(DATE'2026-10-16', e.data_prometida) AS dias_em_atraso
FROM {C}.silver.entregas_fornecedor e
WHERE e.em_atraso
UNION ALL
SELECT 'change freeze de varejo (01/11/2026 a 10/01/2027)' AS risco, p.projeto, p.cliente AS detalhe,
       p.tipo_projeto AS item, DATE'2026-11-01' AS data_prometida, NULL AS dias_em_atraso
FROM {G}.projeto_situacao_atual p
WHERE p.status = 'em_andamento'
  AND (lower(p.tipo_projeto) LIKE '%commerce%' OR lower(p.tipo_projeto) LIKE '%checkout%'
       OR lower(p.tipo_projeto) LIKE '%marketplace%')"""),
]

EXEMPLO_SCORE = ("Qual a chance de o PRJ-024 estourar?", f"""SELECT projeto_id, ROUND(prob_estouro_30d, 2) AS prob_estouro_30d,
       faixa_risco, ranking, principais_fatores, data_referencia
FROM {TABELA_SCORE}
WHERE projeto_id = 'PRJ-024'
  AND data_referencia = (SELECT MAX(data_referencia) FROM {TABELA_SCORE})""")


def tabela_existe(nome: str, perfil: str) -> bool:
    r = subprocess.run(["databricks", "tables", "exists", nome, "--profile", perfil, "-o", "json"],
                       capture_output=True, text=True)
    return r.returncode == 0 and json.loads(r.stdout or "{}").get("table_exists", False)


def ids(prefixo: str):
    """Ids de 32 caracteres hex, únicos e em ordem: <prefixo><contador>."""
    n = 0
    while True:
        n += 1
        yield f"{prefixo}{n:0{32 - len(prefixo)}x}"


def linhas(texto: str) -> list[str]:
    """O Genie guarda SQL como lista de linhas (cada uma terminando em \\n)."""
    partes = texto.strip().split("\n")
    return [p + "\n" for p in partes[:-1]] + [partes[-1]]


def gerar(com_score: bool) -> dict:
    tabelas = TABELAS + ([TABELA_SCORE] if com_score else [])
    exemplos = EXEMPLOS + ([EXEMPLO_SCORE] if com_score else [])
    instrucoes = INSTRUCOES + (INSTRUCOES_SCORE if com_score else [])
    id_pergunta, id_exemplo, id_instrucao = ids("a1"), ids("b2"), ids("c3")
    return {
        "version": 2,
        "config": {"sample_questions": [{"id": next(id_pergunta), "question": [q]} for q in PERGUNTAS_DO_DONO]},
        "data_sources": {
            "tables": [{"identifier": t} for t in sorted(tabelas)],
            "metric_views": [{"identifier": m} for m in sorted(METRIC_VIEWS)],
        },
        "instructions": {
            "text_instructions": [{"id": next(id_instrucao), "content": [l + "\n" for l in instrucoes]}],
            "example_question_sqls": [
                {"id": next(id_exemplo), "question": [q], "sql": linhas(s)} for q, s in exemplos
            ],
        },
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", required=True)
    a = ap.parse_args()
    com_score = tabela_existe(TABELA_SCORE, a.profile)
    espaco = gerar(com_score)
    SAIDA.write_text(json.dumps(espaco, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"gravado: {SAIDA.relative_to(RAIZ)} · {len(espaco['data_sources']['tables'])} tabelas + "
          f"{len(espaco['data_sources']['metric_views'])} metric view · "
          f"{len(espaco['instructions']['example_question_sqls'])} exemplos · "
          f"score {'incluído' if com_score else 'AUSENTE (gold.score_estouro_30d não existe)'}")


if __name__ == "__main__":
    main()
