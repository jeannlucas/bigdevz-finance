# Handoff — 05/10/2026 (Claude Code CLI, fechamento do checkpoint 1)

## Checkpoint 1: concluído

API, app e banco funcionando localmente e validados contra a API real no
Simulador iOS, no iPhone físico e no emulador Android. Repositório público
https://github.com/jeannlucas/bigdevz-finance, branch padrão `main`, CI verde.
Licença continua em definição.

## Corrigido nesta sessão

- `infra/postgres/init/01-test-database.sql` era ignorado pelo `*.sql` do
  `.gitignore`: um clone novo subiria o Compose sem `bigdevz_finance_test`.
- Teste de integração falhava: o banco de dev acumulou contas e o `ListView`
  preguiçoso não construía a conta nova. O teste agora rola a lista e o menu
  até o item. Nenhum dado apagado; o app não mudou.
- CI falhava em clone limpo: `phpunit.xml` declarava a suíte `tests/Unit`,
  diretório vazio que o Git não versiona. Suíte vazia removida.
- CI: `actions/checkout@v7`, `flutter pub get --enforce-lockfile`, timeouts e
  PostgreSQL do job sem senha (`trust`); o hook de credenciais recusou a senha
  local no workflow e não foi contornado.
- README, ROADMAP, CONTRIBUTING, `docs/checkpoint-1-plan.md` atualizados.

## Testado (comandos executados)

- `make test-domain`: 8 testes. `make test-api`: 19 testes, 246 asserções em
  PostgreSQL 18. `make lint-api`: aprovado. `make smoke-api`: 19 checagens OK
  (idempotência 200, mesma chave com outro valor 409, conta PJ em acordo PF 422).
- `dart format --set-exit-if-changed`: 0 mudanças; `flutter analyze`: limpo;
  `flutter test`: 19 testes.
- `flutter test integration_test` contra a API real, conferido no PostgreSQL
  (conta 100000 + movimentação 50000 centavos, parcela 50000/200000):
  - Simulador iPhone 17 Pro, iOS 26.5: verde.
  - iPhone 17 Pro Max físico, iOS 27.0.1, API em `0.0.0.0` na rede local: verde.
    Roteiro manual também feito pelo usuário: login, conta e acordo fictícios,
    troca PF/PJ, reabertura com sessão restaurada. O recebimento manual saiu
    integral (R$ 2.000,00 na conta padrão); o parcial está coberto pelo teste.
  - Emulador Android 16 (API 36, arm64): `flutter build apk --debug` e teste
    de integração verdes, API por `10.0.2.2`.
- CI no GitHub: verde em `dev` e `main` no commit `34d8519`.

## Pendências e avisos

- `php artisan test` mostra 19 avisos: o phpdotenv tenta ler `apps/api/.env`
  (`@file_get_contents`, suprimido), que não existe por decisão do projeto.
  `vendor/bin/phpunit` sai `OK` sem avisos. O formato compacto para agentes
  (`CLAUDECODE`/`AI_AGENT`) esconde esse aviso; sessões anteriores não o viram.
- iPhone físico: o `flutter test` desinstala o app ao final e o iOS volta a
  pedir rede local na instalação seguinte; instalar e permitir antes (README).
  Mudanças do Xcode no `project.pbxproj` (time pessoal, `objectVersion`) e a
  reordenação do `Info.plist` ficam fora dos commits.
- Aparelho Android físico não testado. Licença pendente.
- `bigdevz-finance-prompt-retomada-claude-cli.md` (já no histórico) cita o
  caminho local do Mac; não é segredo, mantido.

## Retomada após reinício (05/10/2026)

- Containers voltaram sozinhos; `make up` sem recriar, `/up` 200, contagens
  do banco de dev iguais antes e depois (nenhum dado apagado).
- Simulador iPhone 17 Pro ligado, aberto pelo Device Hub, `make run-ios`
  até a tela de login. README: abrir o simulador pelo Device Hub (Xcode 27
  não tem `Simulator.app`, conferido).
- Android: só o AVD `bigdevz_api36`, nenhum emulador ativo; `emulator-5554`
  não é garantido.

## Ambiente

Docker 29.8.1; Compose `bigdevz-finance`, sub-rede `10.88.231.0/24` sem
conflito no host; API de volta em `127.0.0.1`. Flutter 3.47.6 fora do PATH,
usado pelo Makefile. Android SDK em `~/Library/Android/sdk` (cmdline-tools
22.0, build-tools 36.0.0, NDK 28.2.13676358, AVD `bigdevz_api36`). Banco de
dev só com dados fictícios. Desenvolvimento segue no Simulador iOS.
