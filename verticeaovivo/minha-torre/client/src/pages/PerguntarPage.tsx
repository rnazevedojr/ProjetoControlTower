import { useEffect, useState } from 'react';
import { Badge, GenieChat } from '@databricks/appkit-ui/react';

const PERGUNTAS = [
  'Quais projetos estão atrasados, e de quais clientes?',
  'Quanto esse atraso vai me custar?',
  'Tenho gente parada enquanto outro projeto pede gente?',
  'O que vai dar errado no próximo mês?',
];

export function PerguntarPage() {
  const [email, setEmail] = useState<string | null>(null);

  useEffect(() => {
    fetch('/api/whoami')
      .then((r) => (r.ok ? r.json() : null))
      .then((me: { email?: string | null } | null) => setEmail(me?.email ?? null))
      .catch(() => setEmail(null));
  }, []);

  return (
    <div className="space-y-4 w-full max-w-5xl mx-auto">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <h2 className="text-2xl font-semibold text-foreground">Perguntar</h2>
          <p className="text-sm text-muted-foreground">
            Pergunte em português ao agente “Farol · Diretoria”. Dados de 16/10/2026. Por exemplo:{' '}
            {PERGUNTAS.map((p) => `“${p}”`).join(' · ')}
          </p>
        </div>
        <Badge variant="secondary">{email ?? 'usuário conectado'}</Badge>
      </div>

      <div className="h-[600px] rounded-md border">
        <GenieChat alias="default" />
      </div>

      <p className="text-xs text-muted-foreground">
        Respostas geradas por IA (Genie) a partir da gold do lakehouse_vertice. Confira o SQL gerado em cada resposta
        antes de decidir. As consultas rodam com as suas permissões (on-behalf-of), não com as do app.
      </p>
    </div>
  );
}
