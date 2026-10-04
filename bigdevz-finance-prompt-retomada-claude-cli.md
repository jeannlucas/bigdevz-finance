# BigDev.Z Finance — prompt de retomada para Claude Code CLI

Você é o Claude Code CLI e vai continuar o desenvolvimento do BigDev.Z Finance iniciado no Codex. A troca de ferramenta ocorreu porque o limite do Codex foi atingido. Trabalhe via terminal na mesma pasta e preserve o que já existe.

Pasta local informada: `/Users/jeannlucasdev/Documents/Projetos/BigDev.Z Finance`. Confirme o diretório real antes de modificar arquivos. Se ele for diferente, identifique o projeto pelos arquivos e não crie uma segunda cópia por engano.

Seu objetivo é concluir o checkpoint 1: login, espaços PF/PJ separados, contas com saldo inicial, acordo a receber parcelado, recebimentos totais/parciais persistidos e interface Flutter integrada à API Laravel/PostgreSQL.

## 1. Recupere o contexto e confira o estado real

Leia as instruções aplicáveis e, quando existirem:

- `AGENTS.md`, `CLAUDE.md` e instruções específicas dos diretórios envolvidos.
- `HANDOFF.md`, começando pela seção mais recente.
- `financeiro-pf-pj-escopo-e-prompt-inicial.md` por inteiro; a seção 7 define o checkpoint e seus critérios de aceitação.
- `docs/checkpoint-1-plan.md`, `docs/architecture.md` e `docs/decisions/0002-dinheiro-e-parcelas.md`.
- `README.md`, `ROADMAP.md`, `Makefile` e `scripts/check-environment.sh`.
- As classes e os testes existentes em `apps/api`.

O código e os arquivos locais precisam confirmar o relato abaixo. Se houver progresso posterior, preserve-o e atualize o diagnóstico. Não interprete uma funcionalidade descrita no escopo como funcionalidade implementada.

Último estado relatado pelo Codex em 04/10/2026, ainda a verificar nesta sessão:

| Item | Estado relatado |
| --- | --- |
| Núcleo PHP | `apps/api/app/Domain/Receivables/Money.php` e `InstallmentSchedule.php` implementados. |
| Testes do núcleo | `apps/api/tests/domain.php`; `make test-domain` passou com 8 testes e zero falhas. |
| Cobertura relatada | Divisão exata, distribuição de centavos, meses curtos, dia 31, ano bissexto e entradas inválidas. |
| Contrato monetário | Strings decimais de duas casas nas fronteiras e centavos inteiros no núcleo; limite documentado de `999999999999.99`; PHP de 64 bits. |
| Aplicações | Laravel e Flutter ainda sem aplicações integradas; PostgreSQL, autenticação e recebimentos persistidos pendentes. |
| Regras ainda sem validação integrada | Isolamento PF/PJ, autorização entre usuários, idempotência, concorrência e atomicidade. |
| Ambiente anterior | Git, PHP, Composer, Docker CLI e Xcode disponíveis; escrita em `.git`, daemon Docker e rede bloqueados naquela sessão. |
| Ferramentas móveis | Flutter/Dart e ferramentas Android não encontrados no PATH; ausência no disco inteiro não confirmada. |
| GitHub | Nenhum repositório, commit ou push criado segundo o relato. Proprietário ainda não verificado. |
| Dispositivos | iPhone e Android ainda não validados. |
| Documentação | README, AGENTS, HANDOFF, roadmap, arquitetura, decisões e plano atualizados. |

Execute os testes existentes para obter uma referência inicial. Diferencie os oito testes relatados dos testes que você realmente executar.

## 2. Reavalie o ambiente do Claude CLI

As restrições descritas pertenciam à sessão anterior do Codex. A nova sessão pode ter permissões diferentes; não presuma nem que continua bloqueada nem que a troca resolveu tudo.

Faça uma verificação curta e objetiva:

1. Confirme sistema, diretório, ferramentas e versões compatíveis. Verifique o Git da pasta e se existe uma raiz Git herdada de outro projeto.
2. Inspecione o script de ambiente antes de executá-lo. Confira o acesso efetivo ao daemon Docker, além da presença do cliente.
3. Verifique conectividade com os serviços necessários a Composer, Flutter e GitHub usando requisições curtas, sem baixar instaladores por tentativa.
4. Verifique `gh auth status` e, quando a rede permitir, `gh api user --jq '.login'`. Erro de rede não comprova ausência de autenticação.
5. Se Flutter/Dart ou Android SDK não estiverem no PATH, procure de forma limitada nos locais de instalação usuais e na configuração do projeto. Não faça varredura indiscriminada dos arquivos pessoais.
6. Separe os resultados em: disponível; instalado mas inacessível/configurado incorretamente; não localizado; bloqueado por permissão ou rede.

Use o mecanismo de aprovação do próprio Claude Code quando um comando necessário exigir autorização. Não use flags ou comandos de configuração do Codex no Claude.

Uma autorização escrita neste prompt não elimina uma restrição técnica. Se uma política ou um hook bloquear uma ação, informe qual ação, a evidência e a origem identificável. Não altere políticas, hooks ou configurações globais para contornar bloqueios; não desative as proteções da sessão.

Prepare as dependências locais necessárias quando permitido, usando documentação oficial e versões compatíveis. Se precisar de autenticação interativa, senha administrativa, aceite ou assinatura Apple, solicite apenas a ação concreta necessária. Continue as tarefas independentes enquanto isso. Não peça credenciais no chat.

Depois de identificar um bloqueio persistente, não repita os mesmos comandos sem mudança no ambiente. A falta do SDK Android não impede o backend; a falta do GitHub não impede o desenvolvimento local.

## 3. Continue a implementação preservando o núcleo

Apresente um plano curto baseado no que encontrou e execute-o. O escopo completo e as regras financeiras continuam sendo os do documento original.

### Backend e banco

- Integre o Laravel ao conteúdo existente de `apps/api`. A pasta já contém código e testes: não a apague nem execute uma inicialização que os sobrescreva. Se o gerador exigir uma pasta vazia, gere a estrutura em um diretório temporário isolado e integre os arquivos de forma controlada.
- Preserve `Money`, `InstallmentSchedule` e seus comportamentos. Adapte autoload, namespaces ou estrutura somente quando necessário. Mantenha as verificações existentes funcionando; ao migrá-las para o runner da aplicação, preserve os cenários e documente a mudança.
- Confira a decisão 0002 antes de integrar valores. Garanta consistência entre centavos, strings, validações da API e PostgreSQL; não aceite valores acima do limite documentado nem permita overflow em somas. Uma proposta antiga de tipo de coluna não autoriza ampliar silenciosamente esse contrato.
- Configure Docker Compose com API e PostgreSQL, migrations, dados fictícios e banco de testes separado. Não use bancos ou volumes de outros projetos.
- Implemente autenticação, espaços PF/PJ, contas, saldo inicial com data de referência, acordos, parcelas, recebimentos e consulta de saldos.
- Cada recurso pertence ao espaço apropriado. A autorização deve ser validada no servidor, inclusive ao consultar ou informar IDs de outro usuário.
- O recebimento e a movimentação da conta devem ser gravados em uma única transação. Previsões não alteram saldo disponível.
- Aceite pagamentos parciais. Impeça recebimentos acima do valor restante, também sob concorrência.
- Implemente idempotência: repetir a mesma operação não duplica dinheiro; reutilizar a chave com conteúdo diferente gera conflito explícito.
- Preserve histórico e regras de datas e arredondamento. Não amplie agora para todos os módulos futuros.

### Flutter

- Prepare `apps/mobile` para iOS e Android com identidade BigDev.Z Finance e API real.
- Implemente login, seleção PF/PJ, resumo, contas, acordos, parcelas e recebimento.
- Use interface moderna e consistente, temas claro/escuro, valores em BRL e formulários claros.
- Trate carregamento, vazio, erros, validações, autenticação e atualização dos dados após recebimento ou troca PF/PJ.
- Configure a URL da API por ambiente. Documente acesso por simulador, emulador e aparelho físico.
- Não apresente telas estáticas ou respostas simuladas como integração concluída. Diferencie build, teste automatizado e teste em dispositivo.

## 4. Valide o fluxo com dados fictícios

Além dos testes do núcleo, execute os critérios da seção 7.E do documento original. O cenário principal deve comprovar:

| Ação | Resultado esperado |
| --- | --- |
| Conta PF com saldo inicial de R$ 1.000,00; cadastrar acordo de R$ 24.000,00 em 12 parcelas | 12 parcelas de R$ 2.000,00; saldo da conta continua R$ 1.000,00. |
| Receber R$ 2.000,00 da primeira parcela | Conta em R$ 3.000,00; acordo com R$ 22.000,00 pendentes. |
| Receber R$ 500,00 da segunda parcela | Conta em R$ 3.500,00; parcela com R$ 1.500,00 pendentes; acordo com R$ 21.500,00 pendentes. |
| Reenviar o mesmo recebimento | Nenhuma duplicação nem nova alteração do saldo. |
| Usar conta PJ para receber acordo PF ou acessar recurso alheio | Rejeição sem gravação parcial ou vazamento. |
| Falha durante gravação ou duas quitações simultâneas | Rollback consistente e ausência de recebimento acima do devido. |
| Trocar PF/PJ e reabrir o app | Dados do espaço correto, recuperados pela API. |

Verifique também a soma exata de R$ 100,00 em três parcelas, o dia 31 em meses curtos e conflito de chave idempotente com payload diferente.

Use PostgreSQL real nos testes que dependem de transações, locks e integridade. Testes PHP isolados não comprovam essas propriedades. Registre testes não executados como pendentes, sem inventar aprovação.

## 5. GitHub autorizado e continuidade entre IAs

A criação do repositório público `bigdevz-finance` e a publicação inicial dos arquivos pertinentes já estão autorizadas. Siga a seção 7.F do documento original.

Verifique proprietário autenticado, existência do repositório e remotes antes de agir. Preserve alterações anteriores, revise o que será versionado, crie commits coerentes e faça o push quando os acessos e as verificações pertinentes permitirem. Não use force push. Não publique dados financeiros reais, credenciais, dumps ou certificados.

A licença continua pendente. Isso não bloqueia o desenvolvimento ou a criação autorizada do repositório público. Registre a pendência sem escolher uma licença em nome do usuário.

Leia `AGENTS.md` explicitamente nesta retomada. Preserve `CLAUDE.md` e as convenções locais existentes. Se for necessário adaptar o carregamento automático de instruções à versão instalada do Claude Code, mantenha AGENTS como fonte comum e use uma referência/importação curta, sem duplicar regras nem alterar configurações globais. Não trate ajuste de documentação entre IAs como substituto da implementação.

Atualize `HANDOFF.md`, README, roadmap e decisões afetadas ao terminar cada incremento. Execute verificações locais de paridade quando forem exigidas pelas instruções aplicáveis e estiverem disponíveis.

## 6. Entrega final

Apresente separadamente:

1. Implementado nesta sessão, incluindo arquivos principais e comportamento entregue.
2. Testado nesta sessão, com comandos, resultados e falhas remanescentes.
3. Não testado ou não implementado, com motivo concreto.
4. Comandos que realmente funcionam para executar e demonstrar o fluxo.
5. GitHub: URL real, branch e commit enviados, ou impedimento específico.
6. Próximo passo exato registrado no HANDOFF.

Continue até concluir o fluxo ou esgotar o trabalho útil permitido por um bloqueio concreto. Se precisar de intervenção do usuário, explique a ação mínima e o erro que a justifica. Não declare o checkpoint concluído apenas por haver estrutura, documentação ou oito testes do núcleo aprovados.

Comece agora pela leitura das instruções e do handoff, reexecute os testes existentes, revalide o ambiente do Claude CLI e prossiga com a integração.

---

Referências oficiais para conferir o funcionamento do Claude Code CLI, consultadas em 04/10/2026:

- [CLI e início de sessão](https://code.claude.com/docs/en/cli-reference)
- [Permissões](https://code.claude.com/docs/en/permissions)
- [Instruções em CLAUDE.md e AGENTS.md](https://code.claude.com/docs/en/memory)

