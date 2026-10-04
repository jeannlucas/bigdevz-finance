# Handoff — 04/10/2026 (Claude Code CLI, fechamento do checkpoint 1)

## Checkpoint 1: estado

Funcionando localmente e validado no Simulador iOS contra a API real.
**Não concluído**: iPhone físico e Android pendentes (ver abaixo).

## Corrigido nesta sessão

- `infra/postgres/init/01-test-database.sql` era ignorado pelo `*.sql` do
  `.gitignore`: um clone novo subiria o Compose sem `bigdevz_finance_test`.
  Exceção adicionada e arquivo versionado.
- Teste de integração falhava no candidato final: o banco de dev acumulou
  contas de execuções anteriores e o `ListView` preguiçoso não construía a
  conta nova (7ª de 10 na ordem por nome). O teste agora rola a lista e o
  menu de contas até o item. Nenhum dado foi apagado; o app não mudou.
- CI: `actions/checkout@v7`, `flutter pub get --enforce-lockfile`, timeouts,
  PostgreSQL do job sem senha (`trust`), aviso de que Linux não cobre iOS/Android.
- ROADMAP, CONTRIBUTING e `docs/checkpoint-1-plan.md` atualizados ao estado real.
- A formatação Dart pendente foi conferida: além do `dart format`, só há chaves
  em `if` de uma instrução (lint), sem mudança de comportamento.

## Testado nesta sessão (candidato final do código)

- `make test-domain`: 8 testes, 0 falhas.
- `make test-api`: 19 testes, 246 asserções, PostgreSQL 18 real.
- `make lint-api`: Pint aprovado.
- `make smoke-api`: 19 checagens OK (idempotência 200, payload diferente 409,
  conta PJ em acordo PF 422, saldo sem duplicar).
- `dart format --set-exit-if-changed`: 0 alterações. `flutter analyze`: sem
  problemas. `flutter test`: 19 testes verdes.
- `flutter test integration_test -d "iPhone 17 Pro"` (iOS 26.5, API real):
  verde depois da correção do teste. Conferido no PostgreSQL: conta com saldo
  inicial 100000 centavos, movimentação de 50000, parcela 50000/200000.

## Pendências

- GitHub/CI: em andamento nesta sessão.
- Android: command-line tools 22.0 instaladas em `~/Library/Android/sdk`
  (pacote oficial, SHA-256 conferido). Falta o usuário aceitar as licenças;
  depois, plataforma 36, build-tools, NDK 28.2.13676358, emulador arm64.
- iPhone físico: nenhum aparelho conectado na checagem desta sessão.
- Licença: pendente, nenhuma concessão criada.
- `bigdevz-finance-prompt-retomada-claude-cli.md` (já no histórico) cita o
  caminho local do Mac; não é segredo, mantido.

## Ambiente

Docker 29.8.1; Compose `bigdevz-finance` com sub-rede `10.88.231.0/24`,
sem rota ou interface conflitante no host. Flutter 3.47.6 fora do PATH, usado
pelo Makefile. O banco de dev contém apenas dados fictícios de várias
execuções do roteiro e do teste de integração.
