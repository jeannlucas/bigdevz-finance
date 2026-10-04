# Plano incremental do checkpoint 1

Especificação: `financeiro-pf-pj-escopo-e-prompt-inicial.md`, seção 7.
Estado de cada passo em 04/10/2026; evidências em `HANDOFF.md`.

1. **Feito.** Ferramentas, Git, rede, Docker e identidade GitHub revalidados.
2. **Feito.** Núcleo puro PHP de valores e cronograma em
   `apps/api/app/Domain/Receivables`: strings decimais com duas casas,
   centavos inteiros, limite R$ 999.999.999.999,99, centavos extras nas
   primeiras parcelas, dia de referência preservado (decisão 0002).
3. **Feito.** Laravel, PostgreSQL de desenvolvimento/teste separados e
   autenticação Sanctum. Recebimento transacional com locks; isolamento,
   idempotência, rollback e concorrência testados em PostgreSQL real.
4. **Parcial.** Flutter integrado (login, PF/PJ, contas, acordo,
   recebimento). Validado no Simulador iOS contra a API real. iPhone físico e
   Android pendentes, cada um com validação própria.
5. **Parcial.** Lockfiles, CI, documentação e publicação no repositório
   público. Licença permanece pendente.

Testes do núcleo e da CI não comprovam os cenários que dependem de
dispositivo. Simulador não substitui aparelho físico; build não substitui
teste funcional.
