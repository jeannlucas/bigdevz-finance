# BigDev.Z Finance — instruções locais

## Estado e modo

DESENVOLVIMENTO ATIVO, checkpoint 1 bloqueado na preparação do ambiente.
Leia `HANDOFF.md` e o documento original antes de retomar. Não trate o escopo
como implementação. Respostas, documentação e mensagens de commit em pt-BR.

## Arquitetura prevista

Flutter/Dart por funcionalidades em `apps/mobile`; API Laravel como monólito
modular em `apps/api`; PostgreSQL acessível somente pelo backend. Estes
diretórios ainda não contêm aplicações. Escolher versões depois de conferir
compatibilidade real e documentação oficial. Não fabricar lockfiles.

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
Licença pendente; não criar LICENSE sem escolha do usuário. Nenhum deploy.

## Onde verificar neste projeto

- `sh scripts/check-environment.sh`: ferramentas/rede/Docker, somente diagnóstico.
- `sh -n scripts/check-environment.sh`: sintaxe do script.
- `make test-domain`: oito testes do núcleo PHP, sem banco ou framework.
- Não há suíte de integração API/Flutter, análise estática ou CI implementadas.
- Não há schema, migrations, endpoints, banco ou logs de aplicação.
- Builds iOS/Android, isolamento PF/PJ, concorrência, persistência e saldos ainda
  não são verificáveis a partir deste projeto.
- Verificar tudo novamente ao retomar; o diagnóstico atual é específico desta sessão.

## Continuidade

Atualizar README, ROADMAP e HANDOFF em cada incremento com comandos realmente
executados, resultados, limitações, branch e commit quando disponíveis.
Não declarar etapa funcional concluída com erros financeiros ou isolamento
sem validação. Não instalar integrações ChatGPT: o fluxo é exclusivamente CLI.
