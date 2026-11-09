import { createApp, analytics, genie, server, getExecutionContext, getWarehouseId } from '@databricks/appkit';
import { z } from 'zod';

// O score do modelo (gold.score_estouro_30d) é opcional: no repositório do aluno ele
// pode não existir. Por isso ele NÃO fica em config/queries (o typegen do build quebraria)
// e é lido por esta rota, que responde { disponivel: false } quando a tabela falta.
const SQL_SCORE = `
SELECT projeto_id, prob_estouro_30d, ranking, faixa_risco, principais_fatores
FROM lakehouse_vertice.gold.score_estouro_30d
ORDER BY ranking
`;

// O warehouse devolve todo número como texto: z.coerce.number() converte.
const linhaScore = z.object({
  projeto_id: z.string(),
  prob_estouro_30d: z.coerce.number(),
  ranking: z.coerce.number(),
  faixa_risco: z.string(),
  principais_fatores: z.string().nullable(),
});

type LinhaScore = z.infer<typeof linhaScore>;

async function lerScore(): Promise<{ disponivel: boolean; linhas: LinhaScore[] }> {
  const { client } = getExecutionContext();
  const resposta = await client.toLegacyWorkspaceClient().statementExecution.executeStatement({
    warehouse_id: await getWarehouseId(),
    statement: SQL_SCORE,
    wait_timeout: '30s',
  });
  if (resposta.status?.state !== 'SUCCEEDED') {
    // TABLE_OR_VIEW_NOT_FOUND (o modelo ainda não rodou) ou qualquer outra falha
    console.warn('score indisponível:', resposta.status?.error?.message ?? resposta.status?.state);
    return { disponivel: false, linhas: [] };
  }
  const colunas = (resposta.manifest?.schema?.columns ?? []).map((c) => c.name ?? '');
  const linhas = (resposta.result?.data_array ?? []).map((valores) =>
    linhaScore.parse(Object.fromEntries(colunas.map((nome, i) => [nome, valores[i] ?? null]))),
  );
  return { disponivel: true, linhas };
}

createApp({
  // genie() lê DATABRICKS_GENIE_SPACE_ID (app.yaml) e registra o alias 'default'
  plugins: [analytics(), genie(), server()],
  onPluginsReady(appkit) {
    appkit.server.extend((app) => {
      // Quem está perguntando (a tela Perguntar mostra o e-mail): headers que o Databricks injeta.
      app.get('/api/whoami', (req, res) => {
        res.json({ email: req.header('x-forwarded-email') ?? null, user: req.header('x-forwarded-user') ?? null });
      });

      app.get('/api/score-estouro', async (_req, res) => {
        try {
          res.json(await lerScore());
        } catch (erro) {
          console.warn('score indisponível:', erro);
          res.json({ disponivel: false, linhas: [] });
        }
      });
    });
  },
}).catch(console.error);
