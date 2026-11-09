import {
  useAnalyticsQuery,
  Alert,
  AlertDescription,
  AlertTitle,
  Badge,
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyTitle,
  Skeleton,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@databricks/appkit-ui/react';
import { AlertTriangle } from 'lucide-react';
import { fmtIndice, fmtInteiro, fmtPct, fmtReais, fmtReaisCompacto, nomeCausa, num } from '../lib/formatadores';
import { useScoreEstouro } from '../lib/useScoreEstouro';

const FONTE = 'gold.projeto_situacao_atual · fotografia de 16/10/2026';

function Kpi({ titulo, valor, detalhe, carregando }: { titulo: string; valor: string; detalhe: string; carregando: boolean }) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardDescription>{titulo}</CardDescription>
        {carregando ? (
          <Skeleton className="h-8 w-28" />
        ) : (
          <CardTitle className="text-3xl tabular-nums">{valor}</CardTitle>
        )}
      </CardHeader>
      <CardContent className="text-xs text-muted-foreground">{detalhe}</CardContent>
    </Card>
  );
}

function Situacao({ situacao }: { situacao: string }) {
  if (situacao === 'crítico') return <Badge variant="destructive">crítico</Badge>;
  if (situacao === 'atenção')
    return <Badge className="bg-warning text-warning-foreground hover:bg-warning">atenção</Badge>;
  return <Badge variant="secondary">{situacao}</Badge>;
}

function Farol({ farol }: { farol: string }) {
  const cor = farol === 'vermelho' ? 'bg-destructive' : farol === 'amarelo' ? 'bg-warning' : 'bg-success';
  return (
    <span className="inline-flex items-center gap-1.5">
      <span className={`inline-block h-2.5 w-2.5 rounded-full ${cor}`} aria-hidden />
      {farol}
    </span>
  );
}

export function ProjetosRiscoPage() {
  const kpis = useAnalyticsQuery('kpis', {});
  const projetos = useAnalyticsQuery('projetos_risco', {});
  const score = useScoreEstouro();

  const k = kpis.data?.[0];
  const carregandoKpi = kpis.loading;

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <div>
        <h2 className="text-2xl font-semibold text-foreground">Projetos em risco</h2>
        <p className="text-sm text-muted-foreground">
          Quais projetos estão atrasados, de quais clientes, e quanto isso vai custar. SPI ou CPI &lt; 0,9 = atenção,
          &lt; 0,8 = crítico.
        </p>
      </div>

      {kpis.error && (
        <Alert variant="destructive">
          <AlertTriangle className="h-4 w-4" />
          <AlertTitle>Não foi possível ler os KPIs</AlertTitle>
          <AlertDescription>{String(kpis.error)}</AlertDescription>
        </Alert>
      )}

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <Kpi
          titulo="Projetos em risco"
          carregando={carregandoKpi}
          valor={k ? `${fmtInteiro(k.em_risco)} de ${fmtInteiro(k.em_andamento)}` : '—'}
          detalhe={k ? `${fmtInteiro(k.criticos)} críticos · ${fmtInteiro(k.melancias)} melancias 🍉` : FONTE}
        />
        <Kpi
          titulo="Estouro previsto"
          carregando={carregandoKpi}
          valor={k ? fmtReaisCompacto(k.estouro_previsto) : '—'}
          detalhe="EAC − orçamento, só onde é positivo"
        />
        <Kpi
          titulo="Carteira em andamento"
          carregando={carregandoKpi}
          valor={k ? fmtReaisCompacto(k.carteira) : '—'}
          detalhe="soma do valor dos contratos"
        />
        <Kpi
          titulo="Alto risco em 30 dias"
          carregando={score.carregando}
          valor={score.altoRisco === null ? '—' : fmtInteiro(score.altoRisco)}
          detalhe={score.disponivel ? 'modelo: faixa_risco = alto' : 'score do modelo ainda não disponível'}
        />
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Projetos em andamento, do pior para o melhor</CardTitle>
          <CardDescription>
            {FONTE}. Causa: a mais frequente no status semanal dos últimos 90 dias.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {projetos.loading && (
            <div className="space-y-2">
              {Array.from({ length: 8 }, (_, i) => (
                <Skeleton key={i} className="h-8 w-full" />
              ))}
            </div>
          )}
          {projetos.error && (
            <Alert variant="destructive">
              <AlertTriangle className="h-4 w-4" />
              <AlertTitle>Não foi possível ler os projetos</AlertTitle>
              <AlertDescription>{String(projetos.error)}</AlertDescription>
            </Alert>
          )}
          {projetos.data && projetos.data.length === 0 && (
            <Empty>
              <EmptyHeader>
                <EmptyTitle>Nenhum projeto em andamento</EmptyTitle>
                <EmptyDescription>Rode o job vertice_farol para atualizar a gold.</EmptyDescription>
              </EmptyHeader>
            </Empty>
          )}
          {projetos.data && projetos.data.length > 0 && (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Projeto</TableHead>
                  <TableHead>Cliente</TableHead>
                  <TableHead>Situação</TableHead>
                  <TableHead className="text-right">SPI</TableHead>
                  <TableHead className="text-right">CPI</TableHead>
                  <TableHead className="text-right">Estouro previsto</TableHead>
                  <TableHead className="text-right">Atraso proj. (dias)</TableHead>
                  <TableHead>Farol do gerente</TableHead>
                  <TableHead>Farol pelo número</TableHead>
                  <TableHead>Causa (90 dias)</TableHead>
                  <TableHead className="text-right">P(estouro)</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {projetos.data.map((p) => {
                  const s = score.porProjeto.get(p.projeto);
                  return (
                    <TableRow key={p.projeto}>
                      <TableCell className="font-medium" title={p.nome_projeto}>
                        {p.projeto}
                      </TableCell>
                      <TableCell>{p.cliente}</TableCell>
                      <TableCell>
                        <Situacao situacao={p.situacao} />
                      </TableCell>
                      <TableCell className="text-right tabular-nums">{fmtIndice(p.spi)}</TableCell>
                      <TableCell className="text-right tabular-nums">{fmtIndice(p.cpi)}</TableCell>
                      <TableCell className="text-right tabular-nums">
                        {num(p.estouro_previsto) > 0 ? fmtReais(p.estouro_previsto) : '—'}
                      </TableCell>
                      <TableCell className="text-right tabular-nums">
                        {fmtInteiro(Math.max(0, num(p.atraso_projetado_dias)))}
                      </TableCell>
                      <TableCell>
                        <span className="inline-flex items-center gap-1">
                          <Farol farol={p.farol_do_gerente} />
                          {String(p.melancia) === 'true' && <span title="Melancia: verde por fora, vermelho por dentro">🍉</span>}
                        </span>
                      </TableCell>
                      <TableCell>
                        <Farol farol={p.farol_calculado} />
                      </TableCell>
                      <TableCell>
                        {nomeCausa(p.causa_principal)}
                        {num(p.semanas_causa_principal) > 0 && (
                          <span className="text-muted-foreground"> · {fmtInteiro(p.semanas_causa_principal)} sem.</span>
                        )}
                      </TableCell>
                      <TableCell className="text-right tabular-nums">{s ? fmtPct(s.prob_estouro_30d) : '—'}</TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
