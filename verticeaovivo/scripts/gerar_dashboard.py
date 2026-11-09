#!/usr/bin/env python3
"""Gera o dashboard AI/BI do Projeto Farol: resources/dashboard-portfolio.lvdash.json.

Três páginas, uma pergunta do dono em cada:
  Portfólio     quais projetos estão atrasados, e quanto isso vai custar?
  Pessoas       tenho gente parada enquanto outro projeto pede gente?
  Fornecedores  o que vai dar errado no próximo mês?

As queries da gold usam o nome PURO da tabela: o recurso do bundle diz o catálogo
(dataset_catalog) e o schema (dataset_schema: gold). A silver vai com o nome completo.

Uso:
  python3 scripts/gerar_dashboard.py                    # grava o JSON
  python3 scripts/gerar_dashboard.py --sql-teste pasta  # e um .sql por dataset, com o prefixo da gold, para testar
"""
import argparse, json, pathlib, re

RAIZ = pathlib.Path(__file__).resolve().parent.parent
SAIDA = RAIZ / "resources" / "dashboard-portfolio.lvdash.json"
TABELAS_GOLD = ["projeto_situacao_atual", "fato_projeto_semana", "utilizacao_pessoa_semana", "status_estruturado"]

# Cores da situação (as mesmas em todo o dashboard)
COR_SITUACAO = [
    {"value": "crítico", "color": "#FF5F46"},
    {"value": "atenção", "color": "#F6C344"},
    {"value": "ok",      "color": "#22C2F4"},
]

# Formatos
REAIS = {"type": "number-currency", "currencyCode": "BRL", "abbreviation": "compact",
         "decimalPlaces": {"type": "max", "places": 2}}
INDICE = {"type": "number", "decimalPlaces": {"type": "exact", "places": 2}}
PCT = {"type": "number-percent", "decimalPlaces": {"type": "max", "places": 1}}

# ---------------------------------------------------------------------------
# Datasets: o SQL do dashboard, num lugar só
# ---------------------------------------------------------------------------
DATASETS = {
    "ds_kpis": ("KPIs da carteira", """
SELECT
  SUM(valor_contrato)                                   AS carteira,
  SUM(ev) / SUM(pv)                                     AS spi,
  SUM(ev) / SUM(ac)                                     AS cpi,
  SUM(estouro_previsto)                                 AS estouro_previsto,
  count_if(situacao IN ('atenção', 'crítico'))          AS em_risco,
  count_if(situacao = 'crítico')                        AS criticos,
  count_if(melancia)                                    AS melancias
FROM projeto_situacao_atual
WHERE status = 'em_andamento'
"""),
    "ds_projetos": ("Projetos em andamento", """
SELECT
  projeto,
  nome_projeto,
  cliente,
  gerente_projeto,
  situacao,
  spi,
  cpi,
  estouro_previsto,
  margem_projetada,
  atraso_projetado_dias,
  farol_do_gerente,
  farol_calculado,
  CASE WHEN melancia THEN 'sim' ELSE '' END             AS melancia
FROM projeto_situacao_atual
WHERE status = 'em_andamento'
ORDER BY estouro_previsto DESC, spi
"""),
    "ds_semanal": ("SPI e CPI semanais da carteira", """
SELECT
  f.semana,
  try_divide(SUM(f.ev), SUM(f.pv))                      AS spi,
  try_divide(SUM(f.ev), SUM(f.ac))                      AS cpi
FROM fato_projeto_semana f
JOIN projeto_situacao_atual p ON p.projeto = f.projeto_id
WHERE p.status = 'em_andamento'
  AND f.semana >= DATE'2025-03-07'
GROUP BY f.semana
ORDER BY f.semana
"""),
    "ds_top_parados": ("Top 15 por custo da hora parada", """
SELECT
  concat(nome, ' · ', papel)                            AS pessoa,
  SUM(custo_ocioso)                                     AS custo_ocioso,
  SUM(horas_apontadas) / SUM(horas_disponiveis)         AS utilizacao
FROM utilizacao_pessoa_semana
WHERE semana > DATE'2026-07-24'
GROUP BY nome, papel
ORDER BY custo_ocioso DESC
LIMIT 15
"""),
    "ds_pessoas": ("Utilização por pessoa e projeto (12 semanas)", """
SELECT
  colaborador_id,
  nome,
  papel,
  senioridade,
  projeto_id,
  SUM(horas_disponiveis)                                AS horas_disponiveis,
  SUM(horas_apontadas)                                  AS horas_apontadas,
  SUM(horas_ociosas)                                    AS horas_ociosas,
  SUM(horas_apontadas) / SUM(horas_disponiveis)         AS utilizacao,
  SUM(custo_ocioso)                                     AS custo_ocioso
FROM utilizacao_pessoa_semana
WHERE semana > DATE'2026-07-24'
GROUP BY colaborador_id, nome, papel, senioridade, projeto_id
ORDER BY utilizacao, custo_ocioso DESC
"""),
    "ds_causas": ("Causas de bloqueio (90 dias)", """
SELECT
  projeto_id,
  causa_bloqueio,
  count(*)                                              AS semanas,
  SUM(dias_impacto)                                     AS dias_impacto
FROM status_estruturado
WHERE data_status >= DATE'2026-07-18'
  AND causa_bloqueio NOT IN ('sem_bloqueio', 'nao_reportado')
GROUP BY projeto_id, causa_bloqueio
ORDER BY semanas DESC
"""),
    "ds_fornecedores": ("Fornecedores", """
SELECT
  fornecedor,
  count(DISTINCT fornecedor_como_veio)                  AS grafias,
  count(*)                                              AS entregas,
  SUM(CASE WHEN data_entrega IS NOT NULL THEN prazo_real_dias END)
    / SUM(CASE WHEN data_entrega IS NOT NULL THEN prazo_prometido_dias END) AS real_sobre_prometido,
  count_if(data_entrega <= data_prometida) / count_if(data_entrega IS NOT NULL) AS pct_no_prazo,
  count_if(em_atraso)                                   AS em_atraso_hoje
FROM lakehouse_vertice.silver.entregas_fornecedor
GROUP BY fornecedor
ORDER BY real_sobre_prometido DESC
"""),
    "ds_atrasadas": ("Entregas em atraso hoje", """
SELECT
  entrega_id,
  projeto_id,
  fornecedor,
  item,
  valor,
  data_prometida,
  datediff(DATE'2026-10-16', data_prometida)            AS dias_em_atraso
FROM lakehouse_vertice.silver.entregas_fornecedor
WHERE em_atraso
ORDER BY dias_em_atraso DESC
"""),
}


def dataset(nome):
    titulo, sql = DATASETS[nome]
    linhas = [l + "\n" for l in sql.strip().splitlines()]
    return {"name": nome, "displayName": titulo, "queryLines": linhas}


# ---------------------------------------------------------------------------
# Widgets
# ---------------------------------------------------------------------------
def posicao(x, y, w, h):
    return {"x": x, "y": y, "width": w, "height": h}


def campo(nome, expressao=None):
    return {"name": nome, "expression": expressao or f"`{nome}`"}


def consulta(ds, campos, desagregado=True):
    return [{"name": "main_query",
             "query": {"datasetName": ds, "fields": campos, "disaggregated": desagregado}}]


def moldura(titulo, descricao=None):
    m = {"showTitle": True, "title": titulo}
    if descricao:
        m.update({"showDescription": True, "description": descricao})
    return m


def texto(nome, linhas, pos):
    return {"widget": {"name": nome, "multilineTextboxSpec": {"lines": linhas}}, "position": pos}


def contador(nome, ds, coluna, titulo, formato, pos, descricao=None):
    valor = {"fieldName": coluna, "displayName": titulo}
    if formato:
        valor["format"] = formato
    return {"widget": {
        "name": nome,
        "queries": consulta(ds, [campo(coluna)]),
        "spec": {"version": 2, "widgetType": "counter",
                 "encodings": {"value": valor},
                 "frame": moldura(titulo, descricao)}},
        "position": pos}


def tabela(nome, ds, colunas, titulo, pos, descricao=None):
    """colunas: lista de (campo, rótulo, formato ou None)."""
    cols = []
    for c, rotulo, fmt in colunas:
        col = {"fieldName": c, "displayName": rotulo}
        if fmt:
            col["format"] = fmt
        cols.append(col)
    return {"widget": {
        "name": nome,
        "queries": consulta(ds, [campo(c) for c, _, _ in colunas]),
        "spec": {"version": 2, "widgetType": "table",
                 "encodings": {"columns": cols},
                 "frame": moldura(titulo, descricao)}},
        "position": pos}


def barra_horizontal(nome, ds, categoria, medida, rotulo, titulo, pos, formato=None,
                     cor=None, mapeamento=None, descricao=None):
    """Barra deitada: a medida no x, a categoria no y. cor = coluna que pinta as barras."""
    soma = f"sum({medida})"
    campos = [campo(categoria), campo(soma, f"SUM(`{medida}`)")]
    x = {"scale": {"type": "quantitative"}, "fields": [{"fieldName": soma, "displayName": rotulo}]}
    if formato:
        x["format"] = formato
    enc = {"x": x,
           "y": {"fieldName": categoria, "displayName": categoria,
                 "scale": {"type": "categorical", "sort": {"by": "x-reversed"}}}}
    if cor:
        campos.append(campo(cor))
        escala = {"type": "categorical"}
        if mapeamento:
            escala["mappings"] = mapeamento
        enc["color"] = {"fieldName": cor, "displayName": cor, "scale": escala}
    return {"widget": {
        "name": nome,
        "queries": consulta(ds, campos, desagregado=False),
        "spec": {"version": 3, "widgetType": "bar", "encodings": enc,
                 "frame": moldura(titulo, descricao)}},
        "position": pos}


def barra_empilhada(nome, ds, categoria, medida, cor, rotulo, titulo, pos, descricao=None):
    soma = f"sum({medida})"
    return {"widget": {
        "name": nome,
        "queries": consulta(ds, [campo(categoria), campo(cor), campo(soma, f"SUM(`{medida}`)")],
                            desagregado=False),
        "spec": {"version": 3, "widgetType": "bar",
                 "encodings": {
                     "x": {"fieldName": categoria, "displayName": "projeto",
                           "scale": {"type": "categorical", "sort": {"by": "y-reversed"}}},
                     "y": {"fieldName": soma, "displayName": rotulo, "scale": {"type": "quantitative"}},
                     "color": {"fieldName": cor, "displayName": "causa", "scale": {"type": "categorical"}}},
                 "frame": moldura(titulo, descricao)}},
        "position": pos}


def dispersao(nome, ds, x, y, cor, titulo, pos, descricao=None):
    return {"widget": {
        "name": nome,
        "queries": consulta(ds, [campo(x), campo(y), campo(cor), campo("projeto")]),
        "spec": {"version": 3, "widgetType": "scatter",
                 "encodings": {
                     "x": {"fieldName": x, "displayName": x.upper(), "scale": {"type": "quantitative"},
                           "format": INDICE},
                     "y": {"fieldName": y, "displayName": y.upper(), "scale": {"type": "quantitative"},
                           "format": INDICE},
                     "color": {"fieldName": cor, "displayName": "situação",
                               "scale": {"type": "categorical", "mappings": COR_SITUACAO}}},
                 "annotations": [linha_de_referencia("x", "1.0", "SPI = 1"),
                                 linha_de_referencia("y", "1.0", "CPI = 1")],
                 "frame": moldura(titulo, descricao)}},
        "position": pos}


def linha_de_referencia(eixo, valor, rotulo):
    tipo = "vertical-line" if eixo == "x" else "horizontal-line"
    return {"type": tipo, "encodings": {eixo: {"dataValue": valor, "dataType": "DOUBLE"},
                                        "label": {"value": rotulo},
                                        "color": {"value": "#8A8A99"}}}


def linha_semanal(nome, ds, titulo, pos, descricao=None):
    return {"widget": {
        "name": nome,
        "queries": consulta(ds, [campo("semana"), campo("spi"), campo("cpi")]),
        "spec": {"version": 3, "widgetType": "line",
                 "encodings": {
                     "x": {"fieldName": "semana", "displayName": "semana", "scale": {"type": "temporal"}},
                     "y": {"scale": {"type": "quantitative"}, "format": INDICE,
                           "fields": [{"fieldName": "spi", "displayName": "SPI"},
                                      {"fieldName": "cpi", "displayName": "CPI"}]}},
                 "annotations": [linha_de_referencia("y", "1.0", "meta = 1,0"),
                                 linha_de_referencia("y", "0.9", "atenção < 0,9")],
                 "frame": moldura(titulo, descricao)}},
        "position": pos}


# ---------------------------------------------------------------------------
# Páginas
# ---------------------------------------------------------------------------
def pagina(nome, titulo, layout):
    return {"name": nome, "displayName": titulo, "pageType": "PAGE_TYPE_CANVAS",
            "layoutVersion": "GRID_V1", "layout": layout}


portfolio = pagina("portfolio", "Portfólio", [
    texto("titulo_portfolio", [
        "## Quais projetos estão atrasados, e de quais clientes? Quanto esse atraso vai me custar?\n",
        "\n",
        "Carteira em andamento em 16/10/2026. SPI ou CPI abaixo de 0,9 = atenção, abaixo de 0,8 = crítico."],
        posicao(0, 0, 12, 2)),
    contador("kpi_carteira", "ds_kpis", "carteira", "Carteira em andamento", REAIS, posicao(0, 2, 3, 3)),
    contador("kpi_spi", "ds_kpis", "spi", "SPI da carteira", INDICE, posicao(3, 2, 3, 3),
             "Σ EV ÷ Σ PV. Abaixo de 1 é atraso"),
    contador("kpi_cpi", "ds_kpis", "cpi", "CPI da carteira", INDICE, posicao(6, 2, 3, 3),
             "Σ EV ÷ Σ AC. Abaixo de 1 é estouro"),
    contador("kpi_estouro", "ds_kpis", "estouro_previsto", "Estouro previsto", REAIS, posicao(9, 2, 3, 3),
             "EAC − orçamento, só onde é positivo"),
    contador("kpi_em_risco", "ds_kpis", "em_risco", "Projetos em risco", None, posicao(0, 5, 4, 3),
             "atenção + crítico"),
    contador("kpi_criticos", "ds_kpis", "criticos", "Projetos críticos", None, posicao(4, 5, 4, 3),
             "SPI ou CPI < 0,8"),
    contador("kpi_melancias", "ds_kpis", "melancias", "Melancias", None, posicao(8, 5, 4, 3),
             "farol do gerente verde, mas SPI < 0,9"),
    barra_horizontal("barra_estouro", "ds_projetos", "projeto", "estouro_previsto", "estouro previsto",
                     "Estouro previsto por projeto", posicao(0, 8, 6, 7), formato=REAIS,
                     cor="situacao", mapeamento=COR_SITUACAO),
    dispersao("dispersao_spi_cpi", "ds_projetos", "spi", "cpi", "situacao",
              "SPI × CPI, um ponto por projeto", posicao(6, 8, 6, 7),
              "embaixo e à esquerda: atrasado e estourando"),
    linha_semanal("linha_spi_cpi", "ds_semanal", "SPI e CPI semanais da carteira", posicao(0, 15, 12, 5),
                  "Σ EV ÷ Σ PV e Σ EV ÷ Σ AC por sexta-feira, desde 07/03/2025 (EV do status semanal)"),
    tabela("tabela_projetos", "ds_projetos", [
        ("projeto", "Projeto", None),
        ("cliente", "Cliente", None),
        ("nome_projeto", "Nome", None),
        ("gerente_projeto", "Gerente", None),
        ("situacao", "Situação", None),
        ("farol_do_gerente", "Farol do gerente", None),
        ("farol_calculado", "Farol pelo número", None),
        ("melancia", "Melancia", None),
        ("spi", "SPI", INDICE),
        ("cpi", "CPI", INDICE),
        ("estouro_previsto", "Estouro previsto", REAIS),
        ("margem_projetada", "Margem projetada", PCT),
        ("atraso_projetado_dias", "Atraso projetado (dias)", None),
    ], "Projetos em andamento", posicao(0, 20, 12, 9),
        "o farol que o gerente publica ao lado do farol que o número dá"),
])

pessoas = pagina("pessoas", "Pessoas", [
    texto("titulo_pessoas", [
        "## Tenho gente parada enquanto outro projeto pede gente?\n",
        "\n",
        "Timesheet das últimas 12 semanas (depois de 24/07/2026) e as causas de bloqueio dos últimos 90 dias."],
        posicao(0, 0, 12, 2)),
    barra_horizontal("barra_top_parados", "ds_top_parados", "pessoa", "custo_ocioso", "custo da hora parada",
                     "Top 15 pessoas por custo da hora parada", posicao(0, 2, 6, 8), formato=REAIS,
                     descricao="horas disponíveis − apontadas, × custo por hora"),
    barra_empilhada("barra_causas", "ds_causas", "projeto_id", "semanas", "causa_bloqueio", "semanas com bloqueio",
                    "Causas de bloqueio por projeto (90 dias)", posicao(6, 2, 6, 8),
                    "status semanal estruturado (IA, palavra-chave e regra)"),
    tabela("tabela_utilizacao", "ds_pessoas", [
        ("colaborador_id", "Pessoa", None),
        ("nome", "Nome", None),
        ("papel", "Papel", None),
        ("senioridade", "Senioridade", None),
        ("projeto_id", "Projeto", None),
        ("utilizacao", "Utilização", PCT),
        ("horas_disponiveis", "Horas disponíveis", None),
        ("horas_apontadas", "Horas apontadas", None),
        ("horas_ociosas", "Horas ociosas", None),
        ("custo_ocioso", "Custo da hora parada", REAIS),
    ], "Utilização por pessoa e projeto, da mais parada à mais ocupada", posicao(0, 10, 12, 9)),
])

fornecedores = pagina("fornecedores", "Fornecedores", [
    texto("titulo_fornecedores", [
        "## O que vai dar errado no próximo mês?\n",
        "\n",
        "As entregas das consultorias: a CodeForge entrega 41% depois do prometido, e a Black Friday traz o change freeze."],
        posicao(0, 0, 12, 2)),
    tabela("tabela_fornecedores", "ds_fornecedores", [
        ("fornecedor", "Fornecedor", None),
        ("grafias", "Grafias no cadastro", None),
        ("entregas", "Entregas", None),
        ("real_sobre_prometido", "Prazo real ÷ prometido", INDICE),
        ("pct_no_prazo", "% no prazo", PCT),
        ("em_atraso_hoje", "Em atraso hoje", None),
    ], "Por fornecedor", posicao(0, 2, 12, 5)),
    tabela("tabela_atrasadas", "ds_atrasadas", [
        ("entrega_id", "Entrega", None),
        ("projeto_id", "Projeto", None),
        ("fornecedor", "Fornecedor", None),
        ("item", "Item", None),
        ("valor", "Valor", REAIS),
        ("data_prometida", "Prometida para", None),
        ("dias_em_atraso", "Dias em atraso", None),
    ], "Entregas em atraso hoje (16/10/2026)", posicao(0, 7, 12, 5)),
])

DASHBOARD = {
    "datasets": [dataset(n) for n in DATASETS],
    "pages": [portfolio, pessoas, fornecedores],
    "uiSettings": {"theme": {
        "canvasBackgroundColor": {"light": "#F5F7FB", "dark": "#14141A"},
        "widgetBackgroundColor": {"light": "#FFFFFF", "dark": "#1C1C24"},
        "widgetBorderColor":     {"light": "#FFFFFF", "dark": "#1C1C24"},
        "fontColor":             {"light": "#14141A", "dark": "#E8EAF0"},
        "selectionColor":        {"light": "#0059DB", "dark": "#22C2F4"},
        "visualizationColors": ["#0059DB", "#22C2F4", "#F6C344", "#FF5F46",
                                "#8B5CF6", "#10B981", "#F97316", "#EC4899"],
        "widgetHeaderAlignment": "LEFT",
    }},
}


def sql_com_prefixo(sql):
    """A mesma query, com lakehouse_vertice.gold. na frente das tabelas da gold (para testar fora do dashboard)."""
    padrao = r"\b(FROM|JOIN)\s+(" + "|".join(TABELAS_GOLD) + r")\b"
    return re.sub(padrao, r"\1 lakehouse_vertice.gold.\2", sql)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sql-teste", help="pasta onde gravar um .sql por dataset, com o prefixo da gold")
    args = ap.parse_args()

    SAIDA.write_text(json.dumps(DASHBOARD, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    widgets = sum(len(p["layout"]) for p in DASHBOARD["pages"])
    print(f"gravado: {SAIDA.relative_to(RAIZ)} · {len(DASHBOARD['datasets'])} datasets · "
          f"{len(DASHBOARD['pages'])} páginas · {widgets} widgets")

    if args.sql_teste:
        pasta = pathlib.Path(args.sql_teste)
        pasta.mkdir(parents=True, exist_ok=True)
        for nome, (_, sql) in DATASETS.items():
            (pasta / f"{nome}.sql").write_text(sql_com_prefixo(sql.strip()) + ";\n", encoding="utf-8")
        print(f"queries de teste em {pasta}")


if __name__ == "__main__":
    main()
