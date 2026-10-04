# BigDev.Z Finance — fechar o checkpoint 1 no Claude Code CLI

Continue o BigDev.Z Finance na pasta atual. A API e o app já foram implementados; o objetivo desta sessão é finalizar as pendências do checkpoint 1, preservar os comportamentos financeiros e entregar evidências atuais de funcionamento.

## Contexto da retomada

Segundo o último relatório de 04/10/2026, a confirmar nos arquivos:

- Laravel com Sanctum, PostgreSQL e Flutter funcionam localmente. Login, espaços PF/PJ, contas, acordos, parcelas e recebimentos estão integrados.
- Money e InstallmentSchedule foram preservados; o contrato financeiro usa centavos inteiros e o limite da decisão 0002.
- Passaram 8 testes do núcleo, 19 testes da API com 246 asserções em PostgreSQL, smoke HTTP e 19 testes Flutter.
- O teste de integração passou no Simulador iOS contra a API real. A formatação final do Dart ocorreu depois desse teste; falta validar o estado final.
- Há teste de concorrência com dois processos PHP. Um problema de UPDATE absoluto foi corrigido usando incremento SQL. Preserve as proteções por transação, locks e constraints.
- iPhone físico e Android pendentes. Android Studio instalado, SDK ainda ausente segundo o relatório.
- CI escrita e ainda não executada no GitHub.
- Três commits na dev, sem push; documentação, CI, formatação e script de ambiente ainda sem commit.
- gh autenticado como jeannlucas e jeannlucas/bigdevz-finance inexistente na última checagem. Revalide ambos.
- O classificador do modo automático do Claude bloqueou a criação do repositório e alterações em ROADMAP.md, CONTRIBUTING.md e docs/checkpoint-1-plan.md.
- Compose usa sub-rede 10.88.231.0/24 devido ao esgotamento dos pools padrão. Flutter está em ~/development/flutter, usado pelo Makefile.
- Licença ainda pendente. Não adicione licença definitiva sem escolha do usuário.

Esse relato é uma referência de retomada. O estado atual do código, os testes desta sessão e os arquivos locais determinam o que você poderá declarar.

## 1. Reconhecimento e permissões

Leia AGENTS.md, CLAUDE.md e as instruções aplicáveis; HANDOFF.md, documento original de escopo, decisões 0002 e 0003, Makefile, README, Compose, CI e plano do checkpoint. Confira diretório, status, histórico, branches e remotes Git. Preserve alterações existentes.

Esta sessão deve permitir revisão humana dos comandos necessários. Se estiver no modo automático e o classificador voltar a negar uma ação, solicite ao usuário mudar para o modo Manual/default pelo mecanismo oficial. Não tente executar a mesma ação por outro comando, ferramenta ou script para escapar da negativa.

Criação e publicação inicial do repositório público continuam autorizadas conforme o escopo. Solicite somente aprovações técnicas que a ferramenta exigir; não reinicie uma discussão sobre essa autorização.

Se uma regra explícita, hook ou política gerenciada continuar bloqueando a operação no modo Manual, descreva a origem e a ação negada e avance nas tarefas independentes. Não desative políticas nem use bypass de permissões.

## 2. Corrija as pendências locais

Revise as alterações não commitadas e os scripts que serão executados. Faça ajustes necessários, mantendo o escopo do checkpoint.

Atualize ROADMAP.md, CONTRIBUTING.md e docs/checkpoint-1-plan.md, além de README e HANDOFF quando necessário, para refletir o estado real. Diferencie funcionando localmente, validado no simulador, validado em aparelho e pendente. A licença deve permanecer em definição.

Confira que os comandos documentados realmente existem e funcionam, incluindo o caminho do Flutter, variáveis da API por dispositivo e o isolamento dos bancos de desenvolvimento/teste. Não exponha caminhos pessoais desnecessários na documentação pública.

Revise a CI antes de publicar: instalação pelas versões e lockfiles do projeto, PostgreSQL de teste, migrations, variáveis seguras, diretórios corretos, formatação, análise e testes pertinentes. Jobs Linux não comprovam build ou execução iOS.

Não remova redes, volumes ou containers de outros projetos para resolver a configuração Docker. Confira se a sub-rede usada está livre no contexto atual e documente como configurá-la, sem modificar a configuração global do Docker.

## 3. Verifique o estado final

Execute as verificações pertinentes às alterações e ao candidato final. Use os comandos do projeto, sem inventar novos nomes de targets:

- Testes do núcleo e da API em PostgreSQL real.
- Smoke HTTP conforme os cuidados definidos no script, preservando dados de uso manual.
- Formatação/análise/testes Flutter.
- Teste de integração no Simulador iOS contra a API real, depois da última alteração de código ou formatação que afete esse candidato.

Confirme os cenários monetários, idempotência com payload diferente, isolamento PF/PJ e entre usuários, rollback e concorrência. Preserve o teste que detecta ausência de lock; não remova proteção apenas para obter um resultado verde.

Evite rerodar toda a suíte indefinidamente. Depois de validação suficiente, siga para entrega; repita verificações afetadas se corrigir falhas ou mudar o código.

## 4. GitHub e CI

Revise antes de publicar os arquivos atuais, o diff preparado e os commits anteriores que serão enviados. Verifique que o histórico e os arquivos versionados não contêm segredos, dados financeiros reais, certificados, dumps ou configurações pessoais de autenticação. Não imprima valores secretos.

Revalide autenticação gh, proprietário jeannlucas e existência de jeannlucas/bigdevz-finance. Um erro de rede não significa que o repositório não existe. Inspecione remotes antes de criar origin; preserve qualquer conflito.

Se o destino estiver confirmado e ausente, crie o repositório público pelo gh com descrição: Controle financeiro pessoal e empresarial em Flutter, Laravel e PostgreSQL.

Faça commits coerentes das pendências verificadas. Siga as regras de branches existentes. Inspecione a relação entre main e dev antes de qualquer merge; não execute cegamente a sequência sugerida no relatório anterior. Se couber avanço por fast-forward, use-o. Se não couber, preserve o histórico e explique a divergência antes de escolher a integração apropriada. Não use force push, reset destrutivo ou descarte de trabalho.

Publique as branches pertinentes e confirme URL, visibilidade, branch padrão e commits remotos. Não assuma que a branch padrão criada pelo gh é a desejada; ajuste para main somente quando consistente com as instruções e com a branch publicada.

Confira a execução real da CI com gh. Se falhar, leia os logs, corrija a causa, rode os testes afetados e publique a correção. Informe os resultados reais e o commit correspondente; workflow escrito não significa CI aprovada.

Publicar o código no GitHub está autorizado. Deploy de produção, publicação nas lojas e posts em redes sociais ficam fora desta sessão.

## 5. Android e iPhone físico

Continue a preparação dos dispositivos mesmo que a publicação GitHub dependa de uma aprovação.

### Android

Verifique as instalações locais e o SDK. Prefira instalar/configurar as ferramentas oficiais por CLI quando possível, usando versões compatíveis com o Flutter e o projeto. Use o SDK existente se encontrado; não duplique instalações por causa de um PATH incompleto.

Prepare sdkmanager, componentes necessários, licenças e um emulador compatível com Apple Silicon. Aceites interativos precisam ser apresentados ao usuário, sem automatizar a resposta dele.

Execute análise/build e teste de integração do fluxo contra a API real em emulador Android ou aparelho disponível. No emulador, configure a URL correta para alcançar a máquina; não reutilize automaticamente o localhost do simulador iOS.

Registre separadamente instalação do SDK, build e teste funcional. Se o ambiente impedir execução, deixe o comando correto e a dependência específica. Não declare Android validado apenas pelo build.

### iPhone físico

Verifique se há dispositivo conectado e reconhecido, assinatura e configuração do projeto. Prepare a URL da API acessível pelo aparelho e valide a conectividade local sem expor a API à internet.

O usuário possui um iPhone para testar. Solicite apenas as ações que dependem dele: conectar/desbloquear, confiar no Mac, habilitar Developer Mode quando exigido e configurar equipe/assinatura no Xcode quando necessário. Não peça credenciais Apple no chat.

Quando o aparelho estiver disponível, execute e valide login, troca PF/PJ, consulta das contas, cadastro de acordo fictício, recebimento parcial e recuperação dos dados após reabrir o app. Confira o resultado na API/banco.

Se depender de uma ação física, deixe a pergunta/ação clara e continue o trabalho independente. Não substitua a evidência em aparelho por evidência de simulador.

## 6. Encerramento verificável

Atualize HANDOFF, documentação e roadmap conforme os resultados efetivos. Se essa atualização gerar um novo commit, informe se a CI desse commit foi conferida. Use dados fictícios em demonstrações e mantenha o licenciamento pendente explícito.

Apresente um relatório curto contendo:

1. O que foi corrigido e finalizado nesta sessão.
2. Testes executados no candidato final e seus resultados.
3. GitHub: URL real, branches, commit final e CI correspondente.
4. Matriz de plataformas: Simulador iOS, iPhone físico e Android, com ambiente/dispositivo, resultado e pendências.
5. Comandos reais para eu abrir o app e testar, com usuário fictício se ainda existir.
6. Se o checkpoint 1 foi concluído; se não, quais critérios específicos faltam.

Comece pela leitura do handoff e do estado Git, confirme o mecanismo de aprovação, atualize as pendências locais e avance até finalizar as partes disponíveis. Preserve o fluxo financeiro que já funciona.

---

Referência oficial de permissões: https://code.claude.com/docs/en/permission-modes

