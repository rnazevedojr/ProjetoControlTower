#!/usr/bin/env bash
# Dá ao app minha-torre acesso de leitura à gold e à silver do lakehouse_vertice.
#
# O app é um usuário do Unity Catalog (um service principal) e nasce sem acesso:
# sem estes GRANTs o BUILD do app falha no typegen com INSUFFICIENT_PERMISSIONS.
# Rode depois do 1º `databricks bundle deploy` do app (é ele que cria o service principal).
#
# Uso:  bash scripts/conceder-acesso.sh <perfil> [app] [warehouse_id]
#   ex: bash scripts/conceder-acesso.sh DEFAULT
set -euo pipefail
# No Git Bash (Windows), "/api/2.0/..." viraria um caminho de disco: desliga a conversão.
export MSYS_NO_PATHCONV=1

PERFIL="${1:?informe o perfil: bash scripts/conceder-acesso.sh <perfil> [app] [warehouse_id]}"
APP="${2:-minha-torre}"
WAREHOUSE="${3:-}"
CATALOGO="lakehouse_vertice"

# lê um campo de texto de um JSON (sem depender de jq nem python)
campo() { grep -o "\"$1\": *\"[^\"]*\"" | head -1 | sed 's/.*: *"\(.*\)"/\1/'; }

SP=$(databricks apps get "$APP" --profile "$PERFIL" -o json | campo service_principal_client_id)
[ -n "$SP" ] || { echo "o app $APP não tem service principal: rode o bundle deploy do app antes"; exit 1; }
echo "app $APP → service principal $SP"

if [ -z "$WAREHOUSE" ]; then
  WAREHOUSE=$(databricks warehouses list --profile "$PERFIL" -o json | campo id)
fi
echo "warehouse $WAREHOUSE"

executar() {
  echo "  $1"
  local resposta
  resposta=$(databricks api post /api/2.0/sql/statements --profile "$PERFIL" --json "{
    \"warehouse_id\": \"$WAREHOUSE\",
    \"statement\": \"$1\",
    \"wait_timeout\": \"30s\"
  }")
  if ! echo "$resposta" | grep -q '"state": *"SUCCEEDED"'; then
    echo "    falhou: $resposta"
    exit 1
  fi
}

executar "GRANT USE CATALOG ON CATALOG $CATALOGO TO \`$SP\`"
for SCHEMA in gold silver; do
  executar "GRANT USE SCHEMA, SELECT ON SCHEMA $CATALOGO.$SCHEMA TO \`$SP\`"
done
echo "pronto: agora, dentro de $APP/, rode  databricks apps deploy --profile $PERFIL"
