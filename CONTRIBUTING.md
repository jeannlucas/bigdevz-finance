# Contribuição

Projeto em desenvolvimento ativo; distribuído sob a licença MIT ([LICENSE](LICENSE)). Antes de alterar,
leia `AGENTS.md`, `HANDOFF.md`, `docs/project-guidelines.md` e as decisões em
`docs/decisions/`.

## Ambiente

`sh scripts/check-environment.sh` diagnostica as ferramentas locais.
`make up` sobe PostgreSQL e API (ver `README.md`). O Compose cria dois bancos:
`bigdevz_finance` (uso manual) e `bigdevz_finance_test` (suíte automatizada).
A suíte recusa qualquer banco que não termine em `_test` e nunca recria nem
esvazia o banco.

## Antes de propor uma mudança

```bash
make test        # núcleo PHP + API em PostgreSQL real
make lint-api    # Pint
make analyze-mobile && make test-mobile
```

A CI (`.github/workflows/ci.yml`) roda o mesmo conjunto em Linux. Ela não
comprova build nem execução em iOS ou Android: mudanças no app exigem o teste
de integração em simulador/emulador contra a API real (comando no `README.md`).

Comportamento alterado exige teste que falhe antes e passe depois. Não remova
proteções (transação, lock, constraint) para obter teste verde.

## Regras

Não execute comandos destrutivos para contornar falhas. Nunca use produção ou
dados financeiros reais em testes. Não inclua segredos, `.env`, dumps ou
comprovantes. Atualize README, ROADMAP e HANDOFF a cada incremento.

Commits em português, Conventional Commits, imperativo e até 72 caracteres.
Desenvolvimento na branch `dev`; `main` avança só por fast-forward.
Não há fluxo de deploy nesta etapa.
