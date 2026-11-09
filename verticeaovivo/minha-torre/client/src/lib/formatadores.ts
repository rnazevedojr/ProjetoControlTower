// O warehouse devolve número como texto: tudo passa por Number() antes de formatar.

const reais = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });
const reaisCompacto = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
  notation: 'compact',
  maximumFractionDigits: 1,
});
const indice = new Intl.NumberFormat('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const inteiro = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 });
const umaCasa = new Intl.NumberFormat('pt-BR', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const pct = new Intl.NumberFormat('pt-BR', { style: 'percent', maximumFractionDigits: 1 });

export const num = (v: unknown): number => Number(v ?? 0);
export const fmtReais = (v: unknown): string => reais.format(num(v));
export const fmtReaisCompacto = (v: unknown): string => reaisCompacto.format(num(v));
export const fmtIndice = (v: unknown): string => indice.format(num(v));
export const fmtInteiro = (v: unknown): string => inteiro.format(num(v));
export const fmtUmaCasa = (v: unknown): string => umaCasa.format(num(v));
export const fmtPct = (v: unknown): string => pct.format(num(v));

// Rótulos das causas de bloqueio (status_estruturado)
export const CAUSAS: Record<string, string> = {
  change_freeze: 'Change freeze',
  falta_sre: 'Falta de SRE',
  dependencia_fornecedor: 'Dependência de fornecedor',
  rotatividade: 'Rotatividade',
  mudanca_escopo: 'Mudança de escopo',
  bug_retrabalho: 'Bug / retrabalho',
  aprovacao_cliente: 'Aprovação do cliente',
  sem_bloqueio: 'Sem bloqueio',
  outro: 'Outro',
};
export const nomeCausa = (c: string): string => CAUSAS[c] ?? c;
