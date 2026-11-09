import { useEffect, useState } from 'react';
import { z } from 'zod';

// O score vem da rota do servidor (a tabela pode não existir): { disponivel, linhas }.
const respostaScore = z.object({
  disponivel: z.boolean(),
  linhas: z.array(
    z.object({
      projeto_id: z.string(),
      prob_estouro_30d: z.coerce.number(),
      ranking: z.coerce.number(),
      faixa_risco: z.string(),
      principais_fatores: z.string().nullable(),
    }),
  ),
});

export type LinhaScore = z.infer<typeof respostaScore>['linhas'][number];

export function useScoreEstouro() {
  const [carregando, setCarregando] = useState(true);
  const [disponivel, setDisponivel] = useState(false);
  const [porProjeto, setPorProjeto] = useState<Map<string, LinhaScore>>(new Map());

  useEffect(() => {
    let ativo = true;
    fetch('/api/score-estouro')
      .then((r) => r.json())
      .then((json: unknown) => {
        const r = respostaScore.safeParse(json);
        if (!ativo) return;
        if (r.success && r.data.disponivel) {
          setDisponivel(true);
          setPorProjeto(new Map(r.data.linhas.map((l) => [l.projeto_id, l])));
        }
      })
      .catch(() => {
        // sem score: a tela mostra "—"
      })
      .finally(() => {
        if (ativo) setCarregando(false);
      });
    return () => {
      ativo = false;
    };
  }, []);

  const altoRisco = disponivel ? [...porProjeto.values()].filter((l) => l.faixa_risco === 'alto').length : null;
  return { carregando, disponivel, porProjeto, altoRisco };
}
