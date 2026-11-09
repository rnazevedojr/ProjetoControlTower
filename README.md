# 🗼 Projeto Farol: Torre de Controle de Projetos no Databricks

Torre de controle de portfólio construída de ponta a ponta no **Databricks**, desde a ingestão dos dados até o app web, passando pelo lakehouse em camadas, testes de qualidade, IA, métricas governadas, dashboard e agente de perguntas em linguagem natural. Tudo está versionado como código, em um **Databricks Asset Bundle**.

Projeto desenvolvido na **Imersão Jornada de Dados** (outubro/2026) com VS Code, Databricks CLI e Claude Code.

## 🎯 O problema de negócio

A **Vértice Tecnologia** (empresa fictícia) toca 60 projetos, com 520 pessoas e R$ 305 milhões de carteira. Cada gerente controla o projeto em uma ferramenta diferente (20 em planilhas **Excel**, 25 no **ClickUp** e 15 no **MS Project**), e ninguém consegue dizer quais projetos estão atrasados.

A torre responde às quatro perguntas do dono:

1. **Quais projetos estão atrasados, e de quais clientes?** (SPI, CPI, situação)
2. **Quanto esse atraso vai custar?** (EAC, estouro previsto, margem projetada)
3. **Tenho gente parada enquanto outro projeto pede gente?** (utilização do timesheet e causa no status)
4. **O que vai dar errado no próximo mês?** (entregas de fornecedores atrasadas e bloqueios recorrentes)

## 🏗️ Arquitetura

```
 job vertice_farol · toda segunda às 6h (America/Sao_Paulo)

 ingestao_feriados ──┐
  (BrasilAPI)        ├── conferencia_bronze ── medalhao (pipeline Lakeflow) ──┬── testes_de_qualidade ──┐
 ingestao_data_lake ─┘      (sql_task)         silver ×7  →  gold ×3          └── status_com_ia ─────────┴── metricas_governadas
  (S3 · boto3)                                                                  (ai_classify/ai_extract)    (metric view)

 Consumo: Dashboard AI/BI · Genie "Farol · Diretoria" · App minha-torre (React + AppKit)
```

| Camada | O que faz |
|---|---|
| **Bronze** | Ingestão da BrasilAPI (feriados) e de um data lake S3 (Supabase Storage via `boto3`): CSV, JSON do ClickUp, XML do MS Project e planilhas Excel |
| **Silver** | Limpeza e padronização com **Lakeflow Declarative Pipelines** (SQL, serverless). A integração das três ferramentas acontece em `silver.tarefas` |
| **Gold** | `fato_projeto_semana`, `projeto_situacao_atual` e `utilizacao_pessoa_semana`, com os KPIs de valor agregado (SPI, CPI, EAC, estouro e margem) |
| **IA** | `ai_classify` e `ai_extract` transformam o texto livre do status semanal em causas de bloqueio estruturadas (`gold.status_estruturado`) |
| **Métricas** | Metric view `gold.mv_projetos`, com a fórmula de cada KPI definida em um só lugar |

## 🧹 Qualidade dos dados

Os dados de origem têm sujeira proposital, e tratar isso é o centro do projeto:

- datas em formatos diferentes, como texto, número de série do Excel e milissegundos;
- percentuais escritos como `'45%'`, `'10,5%'` ou `0.45`, alguns acima de 100;
- linhas de TOTAL no fim das planilhas e tarefas-resumo do MS Project que somariam as horas duas vezes;
- nome da ferramenta escrito de 8 jeitos e status do ClickUp escrito de 12 jeitos;
- colaboradores duplicados e códigos de projeto vazios.

Cada camada tem **expectations** (`CONSTRAINT ... EXPECT ... ON VIOLATION FAIL UPDATE`), e o job roda **10 testes de qualidade** que interrompem a execução se algo não bater. Um dos testes confere se a soma das horas na silver é igual às linhas de TOTAL das planilhas.

## 📊 KPIs

| KPI | Fórmula |
|---|---|
| SPI | EV ÷ PV (abaixo de 1 indica atraso) |
| CPI | EV ÷ AC (abaixo de 1 indica estouro de custo) |
| EAC | Orçamento ÷ CPI |
| Estouro previsto | EAC − orçamento, quando positivo |
| Margem projetada | (contrato − EAC) ÷ contrato |
| Farol calculado | Verde com SPI ≥ 0,95, amarelo com SPI ≥ 0,90 e vermelho abaixo disso |
| **Melancia** 🍉 | O farol do gerente está verde, mas o SPI está abaixo de 0,9: o projeto parece bem por fora e está mal por dentro |

Regras de corte: SPI ou CPI abaixo de 0,9 indica **atenção**, e abaixo de 0,8 indica **crítico**.

## 📈 Produtos de dados

- **Dashboard AI/BI "Projeto Farol · Portfólio"**: carteira, SPI e CPI semanais, estouro por projeto, projetos melancia, custo da hora parada, causas de bloqueio e entregas de fornecedores em atraso.
- **Genie "Farol · Diretoria"**: um agente que responde perguntas em português sobre a carteira de projetos. Ele é gerado como código por `scripts/gerar_genie.py`.
- **App `minha-torre`** (Databricks Apps com React, TypeScript e AppKit): tem as páginas *Projetos em risco*, *Simulador* de realocação de pessoas e *Perguntar*, que é integrada ao Genie.

## 📂 Estrutura

```
verticeaovivo/
├── databricks.yml          # Bundle "vertice": variáveis e targets dev/prod
├── resources/              # Job, pipeline, dashboard e Genie como código
├── src/
│   ├── ingestao/           # Notebooks de ingestão (BrasilAPI e S3/boto3)
│   ├── conferencia/        # Conferência da bronze
│   ├── silver/             # Limpeza e integração (pipeline declarativo)
│   ├── gold/               # Fatos e KPIs
│   ├── ia/                 # Status estruturado com funções de IA
│   ├── testes/             # Testes de qualidade
│   └── metricas/           # Metric view (métricas governadas)
├── scripts/                # Geradores do dashboard e do Genie, utilitários SQL
├── minha-torre/            # App web (bundle próprio)
├── llm/                    # Prompts usados com o Claude Code
└── tests/
```

## 🛠️ Tecnologias

Databricks (Unity Catalog, Lakeflow Declarative Pipelines, Jobs, SQL Warehouse, AI Functions, Metric Views, AI/BI Dashboards, Genie, Databricks Apps) · Databricks Asset Bundles · SQL · Python (boto3, requests) · React e TypeScript · VS Code · Claude Code

## ▶️ Como executar

Pré-requisitos: [Databricks CLI](https://docs.databricks.com/dev-tools/cli/install) autenticada (`databricks configure`) e o catálogo `lakehouse_vertice` criado, com os schemas `bronze`, `silver` e `gold` e o volume `bronze.raw`.

As chaves do data lake **não ficam no repositório**. Crie o arquivo `verticeaovivo/.databricks/bundle/dev/variable-overrides.json`:

```json
{
  "s3_access_key_id": "SUA_CHAVE",
  "s3_secret_access_key": "SEU_SEGREDO"
}
```

Depois, faça o deploy e rode o job:

```bash
cd verticeaovivo
databricks bundle deploy --target dev
databricks bundle run vertice_farol
```

Para o app, veja `verticeaovivo/minha-torre/README.md` e `scripts/conceder-acesso.sh`.

## 👤 Autor

**Railson Nogueira**: [GitHub](https://github.com/rnazevedojr) · [LinkedIn](https://www.linkedin.com/in/railson-nogueira-analista-ciencia-dados/)
