# Contribuição

Projeto em preparação; licença em definição. Ainda não há ambiente de aplicação
ou pipeline para validar contribuições. Antes de alterar, leia `AGENTS.md`,
`HANDOFF.md` e o documento de escopo.

Execute `sh scripts/check-environment.sh` para diagnosticar ferramentas locais.
Não execute comandos destrutivos para contornar falhas. Nunca use produção ou
dados financeiros reais em testes. Não inclua segredos, dumps ou comprovantes.

Comportamento alterado exige teste que falhe antes e passe depois. A futura
suíte de integração deve usar PostgreSQL próprio para testes. Testes Dart não
substituem builds e validação iOS/Android. Atualize o estado real em README,
ROADMAP e HANDOFF a cada incremento.

Commits em português, Conventional Commits, imperativo e até 72 caracteres.
Revisar o diff preparado antes da publicação. Não há fluxo de deploy nesta etapa.
