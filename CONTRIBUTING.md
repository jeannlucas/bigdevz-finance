# Contribuição

Projeto em desenvolvimento ativo; distribuído sob a licença MIT ([LICENSE](LICENSE)). Antes de alterar,
leia `docs/project-guidelines.md`, o handoff canônico em `docs/ai/HANDOFF.md` (e o histórico consolidado `HANDOFF.md`), `AGENTS.md` e as decisões arquiteturais em
`docs/decisions/`. Todas as regras mandatórias do projeto estão contidas dentro deste repositório.

## Ambiente

`sh scripts/check-environment.sh` diagnostica as ferramentas locais.
`make up` sobe PostgreSQL e API (ver `README.md`). O Compose cria dois bancos:
`bigdevz_finance` (uso manual) e `bigdevz_finance_test` (suíte automatizada).
A suíte recusa qualquer banco que não termine em `_test` e nunca recria nem
esvazia o banco.

## Antes de propor uma mudança

```bash
make test        # núcleo PHP + API em PostgreSQL real
make lint-api    # Pint (linter backend)
make analyze-mobile && make test-mobile # análise e testes unitários/widgets mobile
(cd apps/mobile && dart format --output=none --set-exit-if-changed .) # formatação Dart
```

A CI (`.github/workflows/ci.yml`) roda o mesmo conjunto em Linux. Ela não
comprova build nem execução em iOS ou Android: mudanças no app exigem o teste
de integração em simulador/emulador contra a API real (detalhes no `README.md` e
em `docs/mobile-development.md`).

Comportamento alterado exige teste que falhe antes e passe depois. Não remova
proteções (transação, lock, constraint) para obter teste verde.

## Fluxo de Contribuição e Pull Requests

1. **Fork & Branch**: Crie um *fork* do repositório no GitHub e uma branch de trabalho no seu fork a partir da branch `dev` (ex.: `feat/sua-feature` ou `fix/seu-ajuste`).
2. **Qualidade e Testes**: Certifique-se de que todos os comandos da seção anterior passem localmente com zero erros ou alertas de lint.
3. **Padrão de Commits**: Mensagens em português do Brasil, seguindo Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`), em tom imperativo e até 72 caracteres no título.
4. **Pull Request**: Abra o PR tendo a branch `dev` do repositório oficial como destino. Descreva as mudanças, motivação e comandos de teste executados.
5. **Revisão de Código e Integração**: Todo PR passa pelos checks automatizados da CI no GitHub Actions e revisão manual do mantenedor antes do merge na branch `dev`. A integração entre as branches `dev` e `main` é realizada exclusivamente pelo mantenedor através de Pull Request formal com validação completa da suíte de CI.

> [!NOTE]
> As restrições de autorização pontual por checkpoint descritas em `AGENTS.md` aplicam-se a agentes automatizados que intervêm diretamente no repositório canônico do mantenedor. Contribuidores externos são encorajados a desenvolver livremente em seus *forks* e submeter suas contribuições via Pull Request.

## Regras de Segurança e Integridade

Não execute comandos destrutivos para contornar falhas. Nunca use produção ou
dados financeiros reais em testes. Não inclua segredos, `.env`, dumps ou
comprovantes. Atualize README, ROADMAP e `docs/ai/HANDOFF.md` a cada incremento funcional relevante.
Desenvolvimento ativo ocorre na branch `dev`; a branch `main` é reservada para releases estáveis validadas.
Não há fluxo de deploy em produção nesta etapa.
