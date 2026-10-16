# BigDev.Z Finance — instruções locais

> **Autoridade Canônica Local:** BigDev.Z Finance<br>
> **Aplica-se a:** Google Antigravity e OpenAI Codex operando no projeto.<br>
> **Governança Global:** Sujeito a [`~/AGENTS.md`](file:///Users/jeannlucasdev/AGENTS.md), [`padroes-engenharia-bigdevz.md`](file:///Users/jeannlucasdev/.agents/governanca/padroes-engenharia-bigdevz.md) e [`padroes-qa-bigdevz.md`](file:///Users/jeannlucasdev/.agents/governanca/padroes-qa-bigdevz.md).

## Estado e modo

DESENVOLVIMENTO ATIVO. Diretrizes permanentes, regras de negócio e convenções
estão consolidadas em `docs/project-guidelines.md`. Leia `docs/ai/HANDOFF.md` (canônico ativo),
`HANDOFF.md` (histórico consolidado) e `docs/project-guidelines.md` antes de intervir. Não trate escopo planejado
como implementado. Respostas, documentação e mensagens de commit em pt-BR.
Sem co-autores (não adicionar linhas Co-Authored-By).

## Arquitetura

Flutter/Dart por funcionalidades em `apps/mobile`; API Laravel como monólito
modular em `apps/api`; PostgreSQL acessível somente pelo backend. Detalhes em
`docs/project-guidelines.md` e `docs/architecture.md`. Não fabricar lockfiles.

## Regras financeiras

- Dinheiro exato, sem float; strings decimais com duas casas, centavos inteiros
  no núcleo e limite `999999999999.99`. Ler decisão 0002 antes de integrar.
- Compromissos previstos não alteram saldo disponível.
- Toda operação verifica usuário, espaço e vínculos entre recursos.
- Recebimento e movimentação na mesma transação; proteger saldo sob concorrência.
- Idempotência por usuário/espaço/operação; conteúdo diferente gera conflito.
- Distribuição determinística dos centavos e preservação do dia de referência.
- Desenvolvimento e testes usam bancos distintos; nenhum reset do banco manual.
- Histórico efetivado preservado; não apagar recebimento para corrigir saldo.

## Segurança e Git

Não criar, editar ou abrir `.env` real; apenas `.env.example` com placeholders.
Não exibir segredos nem publicar dados financeiros reais, PII ou comprovantes.
Não alterar outros projetos, configuração global, volumes ou produção.
Criar Git com `main` conforme o prompt; desenvolver em `dev` após a preparação.
Antes de trabalho em um Git existente, conferir branch/status e executar fetch.
Publicação inicial está autorizada pelo prompt específico; revisar arquivos,
diff preparado e verificações antes de commit/push. Não usar force push.
Licença MIT formalizada ([LICENSE](LICENSE)). Nenhum deploy.

## Onde verificar neste projeto

- `sh scripts/check-environment.sh`: ferramentas/rede/Docker, somente diagnóstico.
- `sh -n scripts/check-environment.sh`: sintaxe do script.
- `make test-domain`: testes do núcleo PHP (dinheiro, cronograma, datas mensais), sem banco ou framework.
- `make test-api`: API em PostgreSQL real (`bigdevz_finance_test`, recusa outro
  banco), inclui concorrência com processos; `make lint-api`: Pint.
- `make analyze-mobile` e `make test-mobile`: análise e testes Dart (API
  simulada; não comprovam persistência nem concorrência).
- `flutter test integration_test -d <simulador>` em `apps/mobile`, contra a API
  local real (README); perdas de resposta só pelo cliente de `integration_test/`.
- Schema: `apps/api/database/migrations`; banco de dev no Compose (porta 5440).
  Logs: `docker compose logs api` e `scheduler`;
  `apps/api/storage/logs/payables-generate.log`.
- CI (`.github/workflows/ci.yml`): domínio, Pint, `php artisan test` com
  PostgreSQL, `dart format`, `flutter analyze` e `flutter test`. Não roda
  integração no simulador.
- Não verificável daqui: iPhone físico (depende do usuário), aparelho Android
  físico, produção (não existe).
- Verificar tudo novamente ao retomar; o diagnóstico atual é específico desta sessão.

## Continuidade

Atualizar README, ROADMAP e `docs/ai/HANDOFF.md` em cada incremento com comandos realmente
executados, resultados, limitações, branch e commit quando disponíveis. O arquivo `HANDOFF.md`
na raiz permanece como registro histórico consolidado.
Não declarar etapa funcional concluída com erros financeiros ou isolamento
sem validação. Não instalar integrações ChatGPT: o fluxo é exclusivamente CLI.


## Ajustes pendentes para a retomada

Antes de iniciar implementação ou infraestrutura, leia [docs/ai/AJUSTES-PARA-RETOMADA.md](docs/ai/AJUSTES-PARA-RETOMADA.md). A lista registra prioridades, evidências, paridade de segurança Mac/VPS e avaliação de material antigo; não autoriza executar toda a fila nem excluir recursos. Preserve alterações preexistentes e worktrees protegidos; as regras globais e a autorização humana permanecem obrigatórias.
