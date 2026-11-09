import { useMemo, useState } from 'react';
import {
  useAnalyticsQuery,
  Alert,
  AlertDescription,
  AlertTitle,
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyTitle,
  Input,
  Label,
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
  Skeleton,
} from '@databricks/appkit-ui/react';
import { AlertTriangle } from 'lucide-react';
import { fmtIndice, fmtPct, fmtReais, fmtUmaCasa, nomeCausa, num } from '../lib/formatadores';

const SEMANAS_NO_MES = 4;

function Resultado({ titulo, valor, detalhe, destaque }: { titulo: string; valor: string; detalhe: string; destaque?: 'bom' | 'ruim' }) {
  const cor = destaque === 'bom' ? 'text-success' : destaque === 'ruim' ? 'text-destructive' : 'text-foreground';
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardDescription>{titulo}</CardDescription>
        <CardTitle className={`text-2xl tabular-nums ${cor}`}>{valor}</CardTitle>
      </CardHeader>
      <CardContent className="text-xs text-muted-foreground">{detalhe}</CardContent>
    </Card>
  );
}

export function SimuladorPage() {
  const pessoas = useAnalyticsQuery('pessoas_ociosas', {});
  const projetos = useAnalyticsQuery('projetos_risco', {});

  const [pessoaId, setPessoaId] = useState<string>('');
  const [destinoId, setDestinoId] = useState<string>('');
  const [horasOnboarding, setHorasOnboarding] = useState<number>(40);

  const listaPessoas = useMemo(() => pessoas.data ?? [], [pessoas.data]);
  const pessoa = listaPessoas.find((p) => p.colaborador_id === pessoaId) ?? listaPessoas[0];
  const ehSre = pessoa?.papel === 'sre';
  const causa = ehSre ? 'falta_sre' : 'rotatividade';

  // Destinos: só projetos em atenção ou crítico. Para SRE, quem mais sofre com falta de SRE primeiro.
  const destinos = useMemo(() => {
    const emRisco = (projetos.data ?? []).filter(
      (p) => (p.situacao === 'atenção' || p.situacao === 'crítico') && p.projeto !== pessoa?.projeto_origem,
    );
    const dias = (p: (typeof emRisco)[number]) => num(ehSre ? p.dias_falta_sre : p.dias_rotatividade);
    return [...emRisco].sort((a, b) => dias(b) - dias(a));
  }, [projetos.data, pessoa?.projeto_origem, ehSre]);
  const destino = destinos.find((p) => p.projeto === destinoId) ?? destinos[0];

  const carregando = pessoas.loading || projetos.loading;
  const erro = pessoas.error ?? projetos.error;

  // A conta do simulador
  const custoHora = num(pessoa?.custo_hora);
  const horasMes = num(pessoa?.horas_paradas_semana) * SEMANAS_NO_MES;
  const ociosidadeEvitada = horasMes * custoHora;
  const diasImpacto90 = num(ehSre ? destino?.dias_falta_sre : destino?.dias_rotatividade);
  const diasRecuperados = (diasImpacto90 / 90) * 30;
  const mobilizacao = horasOnboarding * custoHora;
  const saldo = ociosidadeEvitada - mobilizacao;

  return (
    <div className="space-y-6 w-full max-w-5xl mx-auto">
      <div>
        <h2 className="text-2xl font-semibold text-foreground">Simulador de realocação</h2>
        <p className="text-sm text-muted-foreground">
          Tenho gente parada enquanto outro projeto pede gente? Escolha uma pessoa ociosa (utilização &lt; 20% nas
          últimas 12 semanas) e um projeto em risco.
        </p>
      </div>

      {erro && (
        <Alert variant="destructive">
          <AlertTriangle className="h-4 w-4" />
          <AlertTitle>Não foi possível ler os dados</AlertTitle>
          <AlertDescription>{String(erro)}</AlertDescription>
        </Alert>
      )}

      {carregando && <Skeleton className="h-40 w-full" />}

      {!carregando && !erro && listaPessoas.length === 0 && (
        <Empty>
          <EmptyHeader>
            <EmptyTitle>Ninguém parado</EmptyTitle>
            <EmptyDescription>Nenhuma pessoa com utilização abaixo de 20% nas últimas 12 semanas.</EmptyDescription>
          </EmptyHeader>
        </Empty>
      )}

      {!carregando && pessoa && (
        <>
          <Card>
            <CardContent className="pt-6 grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="space-y-2">
                <Label htmlFor="pessoa">Pessoa ociosa</Label>
                <Select value={pessoa.colaborador_id} onValueChange={(v) => { setPessoaId(v); setDestinoId(''); }}>
                  <SelectTrigger id="pessoa">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {listaPessoas.map((p) => (
                      <SelectItem key={`${p.colaborador_id}-${p.projeto_origem}`} value={p.colaborador_id}>
                        {p.colaborador_id} · {p.nome} ({p.papel}, {p.projeto_origem}) · uso {fmtPct(p.utilizacao)}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label htmlFor="destino">Projeto destino (atenção ou crítico)</Label>
                <Select value={destino?.projeto ?? ''} onValueChange={setDestinoId}>
                  <SelectTrigger id="destino">
                    <SelectValue placeholder="nenhum projeto em risco" />
                  </SelectTrigger>
                  <SelectContent>
                    {destinos.map((p) => (
                      <SelectItem key={p.projeto} value={p.projeto}>
                        {p.projeto} · {p.situacao} · SPI {fmtIndice(p.spi)}
                        {ehSre ? ` · ${fmtUmaCasa(p.dias_falta_sre)} dias de falta de SRE` : ''}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label htmlFor="onboarding">Horas de onboarding</Label>
                <Input
                  id="onboarding"
                  type="number"
                  min={0}
                  value={horasOnboarding}
                  onChange={(e) => setHorasOnboarding(Math.max(0, Number(e.target.value)))}
                />
              </div>
            </CardContent>
          </Card>

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4">
            <Resultado
              titulo="Horas no mês"
              valor={`${fmtUmaCasa(horasMes)} h`}
              detalhe={`${fmtUmaCasa(pessoa.horas_paradas_semana)} h paradas/semana × ${SEMANAS_NO_MES}`}
            />
            <Resultado
              titulo="Ociosidade que deixa de ser paga"
              valor={fmtReais(ociosidadeEvitada)}
              detalhe={`horas no mês × ${fmtReais(custoHora)}/h`}
            />
            <Resultado
              titulo="Dias de cronograma recuperados"
              valor={fmtUmaCasa(diasRecuperados)}
              detalhe={destino ? `${fmtUmaCasa(diasImpacto90)} dias de ${nomeCausa(causa).toLowerCase()} em 90 dias no ${destino.projeto}` : '—'}
              destaque={diasRecuperados > 0 ? 'bom' : undefined}
            />
            <Resultado
              titulo="Mobilização"
              valor={fmtReais(mobilizacao)}
              detalhe={`${horasOnboarding} h de onboarding × custo/hora`}
            />
            <Resultado
              titulo="Saldo"
              valor={fmtReais(saldo)}
              detalhe="ociosidade evitada − mobilização"
              destaque={saldo >= 0 ? 'bom' : 'ruim'}
            />
          </div>

          <details className="rounded-md border p-4 text-sm text-muted-foreground">
            <summary className="cursor-pointer font-medium text-foreground">Como a conta é feita</summary>
            <ul className="mt-3 list-disc pl-5 space-y-1">
              <li>
                <strong>Horas no mês</strong> = horas paradas médias por semana nas últimas 12 semanas (horas disponíveis −
                apontadas, de gold.utilizacao_pessoa_semana) × {SEMANAS_NO_MES} semanas.
              </li>
              <li>
                <strong>Ociosidade que deixa de ser paga</strong> = horas no mês × custo/hora da pessoa. A Vértice já paga
                essas horas: alocadas no projeto destino, elas viram entrega.
              </li>
              <li>
                <strong>Dias de cronograma recuperados</strong> = dias de impacto que o status semanal declarou para a
                causa nos últimos 90 dias (gold.status_estruturado) ÷ 90 × 30. A causa é falta de SRE quando a pessoa é
                SRE, e rotatividade nos outros papéis.
              </li>
              <li>
                <strong>Mobilização</strong> = horas de onboarding (editável, padrão 40) × custo/hora.
              </li>
              <li>
                <strong>Saldo</strong> = ociosidade evitada − mobilização, no primeiro mês.
              </li>
            </ul>
          </details>
        </>
      )}
    </div>
  );
}
