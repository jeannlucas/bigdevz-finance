# Handoff — 04/10/2026

## Retomada — estado atual

As seções posteriores preservam o diagnóstico da primeira execução. Esta seção
registra o incremento posterior e prevalece para o estado atual.

### Implementado

- Núcleo PHP puro `Money` e `InstallmentSchedule`, em
  `apps/api/app/Domain/Receivables`, sem dependências externas.
- Valores decimais canônicos e cálculo em centavos inteiros; cronograma mensal
  exato, centavos extras nas primeiras parcelas e referência do dia preservada.
- Validação de formato, limites, datas inexistentes e parcelas zeradas.
- `make test-domain`, testes CLI e decisão 0002. Plano em
  `docs/checkpoint-1-plan.md`. Nenhum dado real, segredo ou `.env` criado.

### Testado

- Testes escritos antes da implementação: primeira execução retornou código 1,
  com oito falhas pelas classes ainda ausentes. Depois, oito testes passaram,
  código 0, via `php apps/api/tests/domain.php`.
- R$ 24.000,00 em 12 parcelas de R$ 2.000,00; R$ 100,00 em três parcelas;
  fevereiro comum/bissexto, virada de ano, numeração e entrada inválida.
- A geração não persiste dados; o teste de saldo inicial do cenário 1 ainda
  não foi realizado. Os cenários 8 e 9 foram cobertos no núcleo, sem integração.
- Reexecutado diagnóstico completo: mesmas oito falhas de ambiente.
- Repetidos `git init -b main`, `gh auth status` e `gh api user`: mesmos bloqueios.
- Verificação final `make test-domain`: oito testes, zero falhas, código 0.
  `php -l` passou nas duas classes e no teste; PHP_INT_SIZE=8 confirmou 64 bits.
  `sh -n scripts/check-environment.sh` passou. O script obrigatório
  `~/.claude/scripts/paridade-ia.sh` retornou `PARIDADE OK`, código 0.

### Restrições da sessão e ferramentas

Git, PHP, Composer, Docker CLI, Compose e Xcode estão disponíveis. A escrita
em `.git` e o acesso ao socket Docker foram negados; não são ferramentas ausentes.
DNS CLI falhou para Packagist, Flutter SDK e GitHub. Não há prova de falha de
internet da máquina fora desta sessão. Flutter/Dart/adb/sdkmanager não estão
no PATH; ausência global no disco não comprovada. Não recomendar novo login
GitHub antes de repetir a checagem com conectividade disponível.

O usuário pediu as permissões técnicas pelo mecanismo de aprovação. A política
vigente desta sessão tem `sandbox_approval`, `rules` e `skill_approval`
desabilitados; não há pedido de execução fora do sandbox habilitado. Nenhuma
solicitação foi enviada ou rejeição automática disparada. Retomar com perfil
que permita os acessos é necessário para essas operações; a autorização de
criação do repositório público já existe e não precisa ser repetida.

### Ainda não implementado nem testado

Laravel, PostgreSQL, autenticação, autorização, contas, persistência de acordos,
recebimentos, saldos, rollback, idempotência, concorrência e Flutter. Nenhuma
validação iOS/Android. Nenhum Git local, proprietário remoto confirmado,
repositório remoto criado, commit ou push. Licença continua pendente.

Próximo passo: liberar rede/socket/escrita Git e instalar ferramentas faltantes;
integrar o núcleo ao Laravel e comprovar os cenários com PostgreSQL separado.

## Checkpoint

Preparação parcial; checkpoint 1 **bloqueado, não funcional**. Documento original
preservado. Foram criados documentação inicial, `.gitignore` e diagnóstico CLI.
Não houve scaffolding de aplicações, instalação de dependências, registro de
credenciais, migrations, containers, commit, push ou deploy.

## O que foi verificado

- `pwd` confirmou `/Users/jeannlucasdev/Documents/Projetos/BigDev.Z Finance`.
- `ls -la` inicialmente mostrou apenas o documento original.
- `git rev-parse --show-toplevel` e `git status` responderam que a pasta e seus
  pais não pertencem a repositório Git.
- `git init -b main` falhou com `.git: Operation not permitted`.
- `command -v` não encontrou Flutter, Dart, adb ou sdkmanager.
- SDKs/cache Flutter não encontrados nos caminhos convencionais inspecionados;
  isso não é uma varredura completa do disco. Android SDK ausente em
  `~/Library/Android/sdk`; `.pub-cache` ausente.
- Cache Composer contém pacotes Laravel, mas nenhum pacote `laravel/laravel`
  foi encontrado na listagem inspecionada. Não foram reaproveitados projetos vizinhos.
- `docker info --format '{{.ServerVersion}}'` falhou com permissão negada no
  socket `~/.docker/run/docker.sock`. Não foi possível confirmar o daemon.
- `curl -I` falhou com código 6 para `repo.packagist.org` e
  `storage.googleapis.com`: não resolveu os hosts.
- `gh auth status` informou token inválido, enquanto `gh api user` informou
  erro de conexão. A validade real da credencial **não foi confirmada**,
  porque a comunicação também falhou. Nenhum token foi exibido.
- Xcode 27.0, build 27A266a; caminho selecionado `/Applications/Xcode.app/Contents/Developer`.

## Diagnóstico

Esta sessão não permite preparar e comprovar a integração exigida: escrita Git,
downloads CLI e acesso Docker estão bloqueados. A consulta web à documentação
funcionou, mas não fornece downloads CLI nem acesso ao socket local. A política
da sessão não permite solicitar execução fora do sandbox. Não confundir estas
falhas com ausência de internet no Mac ou defeito comprovado do Docker.

Não há proprietário GitHub verificado, URL remota, branch criada ou commit enviado.
Não foi consultada a existência de `bigdevz-finance`, porque falta identidade
confirmada. A autorização para criar e publicar o projeto permanece registrada.

## Validação e limitações

Não há testes do produto, PostgreSQL ou Flutter executados. Nenhum simulador,
iPhone ou Android foi testado. Não há credenciais fictícias criadas nem roteiro
manual executável do fluxo financeiro. O script de ambiente é apenas diagnóstico.
`sh -n scripts/check-environment.sh` passou com código 0. A execução completa
de `sh scripts/check-environment.sh` terminou com código 1 e oito falhas:
Flutter, Dart, adb, sdkmanager, acesso Docker e rede para Packagist, Flutter SDK
e GitHub API. Isso confirma os bloqueios de preparação, não comportamento
financeiro do produto.

## Retomada concreta

1. Retomar em sessão CLI com acesso permitido ao Git local, rede e Docker.
2. Executar `sh scripts/check-environment.sh` e resolver apenas as falhas reais.
3. Instalar Flutter stable pelo fluxo oficial e executar `flutter doctor -v`.
   Configurar Android SDK; não registrar o app nas lojas nesta etapa.
4. Repetir `gh auth status` e `gh api user --jq '.login'` com rede disponível.
   Somente se autenticação continuar inválida, o usuário executa
   `gh auth login --hostname github.com` no fluxo oficial, sem enviar token no chat.
5. Inicializar `main`, preparar `dev` e consultar o destino na conta verificada.
   Não substituir remotes nem interpretar erro de conexão como repositório ausente.
6. Implementar API/PostgreSQL e testes dos onze cenários de aceitação; depois
   conectar Flutter e validar troca de espaço, sessão e recebimento pela API.
7. Gerar lockfiles, comandos de execução, seed fictício, contrato API e CI
   a partir das aplicações reais. Revisar e publicar a branch conforme autorização.

## Decisões pendentes

Versões finais, contrato monetário, autenticação, estado Flutter e desenho
visual serão registrados após configurar as aplicações. Licença em definição.
Próximo incremento: concluir o próprio checkpoint 1, antes de despesas ou obra.
