# BigDev.Z Finance — prompt completo de inicialização

Atualizado em 04/10/2026 com o nome escolhido e a autorização para criar o repositório.

Você está trabalhando via CLI na pasta local **BigDev.Z Finance**, já criada pelo usuário. Leia este documento por inteiro e execute a seção 7. O objetivo é preparar o projeto, criar ou vincular o repositório público autorizado e implementar o primeiro fluxo funcional. As demais seções preservam o contexto e as regras para que a base permita as próximas entregas.

**Fluxo definido pelo usuário: todo o desenvolvimento e a gestão do repositório serão feitos via CLI na máquina dele.** Use Git, GitHub CLI (`gh`), Flutter/Dart, Docker Compose e as ferramentas locais necessárias. Não dependa de plugins ou conexões do ChatGPT para criar o repositório. Se houver autenticação interativa, assinatura Apple ou instalação de componentes do sistema que exija uma ação do usuário, explique apenas essa dependência e continue o trabalho independente dela.

Não presuma que algo já foi implementado apenas porque este prompt descreve o produto. Inspecione o estado real da pasta antes de agir.

| Identificação | Valor |
| --- | --- |
| Produto | **BigDev.Z Finance** |
| Descrição curta | Controle financeiro pessoal e empresarial. |
| Pasta local existente | `BigDev.Z Finance` — preservar o nome e usar aspas nos comandos com caminhos. |
| Repositório autorizado | `bigdevz-finance`, público, na conta GitHub do usuário devidamente identificada. |
| Nome técnico do pacote Flutter | `bigdevz_finance` |
| Identificadores iOS/Android propostos | `com.bigdevz.finance`, verificar disponibilidade no ambiente antes de eventual registro nas lojas. |
| Nome do projeto Docker Compose | `bigdevz-finance` |
| Idioma e moeda iniciais | Português do Brasil e BRL. |

A criação do repositório público foi explicitamente autorizada. Não peça uma nova confirmação apenas para executar essa ação. Confirme identidade e destino pelo ambiente autenticado; não invente usuário ou organização. A licença permanece uma decisão pendente, sem bloquear a preparação local ou a criação do repositório público.

## 1. Objetivo e necessidades confirmadas

Criar um aplicativo para acompanhar as finanças pessoais e da empresa, com espaços PF e PJ separados. A prioridade é reduzir a manutenção manual de planilhas e manter um histórico confiável do que está previsto, do que foi pago ou recebido e dos compromissos futuros.

O usuário possui contas bancárias PF e PJ e precisa controlar:

- Despesas pessoais e empresariais, fixas, variáveis e parceladas.
- Clientes com mensalidades, projetos avulsos e projetos pagos por etapas.
- Acordos pessoais a receber, como uma venda de carro parcelada.
- Cartões pelo valor total de cada fatura, sem exigir o registro de todas as compras.
- Uma construção: orçamento, compras, serviços, pagamentos e compromissos pendentes.
- Um futuro empréstimo para a construção e seu cronograma de pagamentos.
- O mesmo cadastro acessível em diferentes dispositivos.

O projeto será desenvolvido em público e terá código aberto. Dados financeiros reais ficam em uma instalação privada; demonstrações, testes, documentação pública e exemplos usam dados fictícios.

O usuário quer uma interface moderna, bonita e rápida de usar. Possui um iPhone para testar. iOS e Android devem ser considerados desde o início. O acesso pelo computador via navegador é uma evolução prevista, com prioridade e prazo a definir.

## 2. Base técnica proposta

| Camada | Escolha | Papel |
| --- | --- | --- |
| Aplicativo | Flutter / Dart | Interface para iOS e Android, organizada para permitir adaptação à web. |
| API | Laravel | Autenticação, autorização, regras financeiras e acesso aos dados. |
| Banco | PostgreSQL | Persistência, integridade referencial e transações. |
| Desenvolvimento do backend | Docker Compose | Ambiente reproduzível para API, banco e serviços realmente necessários. |
| Desenvolvimento iOS | Flutter e Xcode no macOS | Compilação, assinatura e testes no simulador e no iPhone. |

Flutter, Docker e PostgreSQL foram sugeridos pelo usuário. Laravel é a recomendação de backend apresentada na conversa, aproveitando sua experiência. Esta é a base para iniciar; mudanças devem ser justificadas e registradas.

O aplicativo acessa a API autenticada. Somente o backend acessa o banco. Credenciais do PostgreSQL não são distribuídas no aplicativo. Em produção, a comunicação deve usar HTTPS.

Organizar o backend como um monólito modular e o Flutter por funcionalidades. Aplicar separação de responsabilidades e regras de domínio testáveis, com abstrações proporcionais ao problema. Fixar versões estáveis e compatíveis após verificar o ambiente e a documentação oficial; não presumir que versões citadas em conversas anteriores sejam as atuais.

## 3. Regras essenciais do produto

### 3.1. PF, PJ e contas bancárias

- Um login pode possuir um espaço pessoal e um espaço empresarial.
- Cada conta, categoria, acordo, lançamento e projeto pertence explicitamente a um espaço.
- A interface identifica o espaço ativo e apresenta apenas seus dados.
- A API verifica o acesso ao espaço e aos recursos relacionados em toda operação. Trocar um identificador na requisição não pode permitir acesso indevido.
- A troca PF/PJ precisa atualizar também caches, filtros e dados em memória.
- Cada espaço aceita múltiplas contas bancárias.
- Cada conta tem um saldo inicial com data de referência. Movimentações efetivadas após esse marco determinam seu saldo atual.
- Contas e recebimentos previstos não modificam o saldo disponível.
- Transferências registram saída e entrada vinculadas, de forma atômica. Quando a transferência for entre PF e PJ do mesmo titular, a origem e o destino precisam ser explicitamente selecionados e autorizados.

### 3.2. Obrigações e pagamentos

- Separar o compromisso financeiro de seus pagamentos ou recebimentos efetivos.
- Uma parcela pode ter vários recebimentos parciais, com valor, data efetiva e conta de destino próprios.
- O valor restante é derivado dos recebimentos válidos, considerando eventuais estornos.
- Estados como pendente, parcial, quitado e vencido devem refletir valores e datas. Um compromisso parcialmente pago pode também estar vencido.
- Vencimentos pendentes continuam visíveis após a mudança de mês.
- Correções de pagamentos preservam o histórico. Preferir estorno vinculado e novo registro a apagar uma movimentação efetivada.
- Prevenir duplicação por clique repetido, reenvio de requisição ou execução duplicada de tarefa.
- Uma requisição inválida não pode deixar metade da atualização gravada.

### 3.3. Valores e datas

- Trabalhar com valores monetários exatos. Proposta: `NUMERIC(19,2)` no PostgreSQL e representação decimal exata na API; definir uma estratégia equivalente no Flutter.
- Não usar ponto flutuante binário para calcular saldos, parcelas ou quitações. Na API, transmitir dinheiro como string decimal ou centavos inteiros, documentando uma única convenção.
- Quando a divisão de um total produzir centavos restantes, distribuí-los de maneira determinística, preservando a soma exata.
- Vencimentos são datas de calendário; eventos de auditoria possuem instante e fuso definidos. A interface usa formato brasileiro e moeda BRL inicialmente.
- Proposta para vencimento no dia 31 em meses curtos: usar o último dia válido daquele mês e preservar o dia de referência para os meses seguintes. Registrar essa decisão.
- Não deslocar vencimentos por feriado ou fim de semana sem uma regra explicitamente configurada.

### 3.4. Acordos parcelados e recorrências

- Um acordo parcelado possui valor combinado, eventual entrada, quantidade de parcelas, primeiro vencimento e término definido.
- Criar todas as parcelas de forma consistente e manter sua vinculação ao acordo.
- Controlar cada parcela individualmente, inclusive atrasos e pagamentos antecipados.
- Uma mensalidade recorrente continua até sua data final ou cancelamento; não é um acordo de quantidade fixa.
- A geração de recorrências deve ser idempotente, com uma ocorrência única por período.
- Alterações em uma recorrência podem afetar ocorrências futuras selecionadas, preservando o histórico realizado.
- Contas variáveis podem aguardar o valor do mês. Não repetir um valor antigo como se já estivesse confirmado.
- Permitir futuramente o cadastro de acordos já em andamento. Pagamentos históricos anteriores ao saldo inicial da conta precisam ser conciliados com o marco inicial, evitando duplicar o dinheiro disponível.

### 3.5. Clientes e projetos de serviço

- Um cliente pode ter simultaneamente mensalidades, projetos avulsos e projetos por etapas.
- Uma etapa tem descrição, valor e condição de liberação para cobrança.
- Separar valor contratado, etapa aguardando liberação, cobrança emitida/liberada e valor recebido.
- Etapas ainda não liberadas precisam ser identificadas separadamente nas projeções.
- Mostrar histórico, próximos vencimentos, pagamentos parciais e valores vencidos.
- Preparar mensagens de cobrança para revisão e envio manual é uma evolução possível; envio automático depende de uma integração específica.

### 3.6. Cartões

- Controlar uma fatura por cartão e período, com vencimento, valor total, pagamentos e estado.
- Não exigir cadastro de cada compra nem implementar automaticamente um segundo controle de compras parceladas no cartão.
- Novas faturas variáveis podem começar aguardando valor.
- Caso uma parte da fatura corresponda à obra, permitir futuramente uma associação/rateio à construção. O gasto associado e o pagamento da fatura não podem gerar duas despesas iguais.
- O detalhamento dessa associação será definido quando o módulo de obra for implementado.

### 3.7. Construção e empréstimo

- A construção é um projeto vinculado ao espaço PF, com categorias e etapas.
- Distinguir orçamento planejado, compromissos assumidos, total pago e valor contratado ainda a pagar. Essas medidas se sobrepõem e não devem ser somadas como despesas independentes.
- Uma compra pode ter entrada e pagamentos posteriores. Ela aparece na obra e nas contas a pagar por meio do mesmo registro financeiro.
- Aceitar comprovantes e documentos privados, com acesso autenticado, na fase correspondente.
- Registrar liberações do empréstimo como entradas de financiamento associadas à dívida, separadas de receitas operacionais e pessoais.
- Acompanhar as parcelas conforme o contrato informado. Não inferir principal, juros ou saldo devedor bancário apenas multiplicando quantidade de parcelas pelo valor da prestação.
- Mostrar separadamente o custo da construção e os pagamentos do financiamento para evitar duplicar custos.

## 4. Interface e experiência

- Seleção PF/PJ sempre acessível e espaço ativo claramente identificado.
- Resumo com saldo atual, contas a pagar, valores a receber e projeções identificadas como previstas.
- Navegação curta: resumo, movimentações, acordos/projetos e contas.
- Formulários com poucos campos por etapa, teclado adequado, máscaras brasileiras e validação próxima ao campo.
- Temas claro e escuro, contraste legível, áreas de toque adequadas e suporte a textos maiores.
- Estados completos de carregamento, erro, ausência de dados, operação em andamento e sucesso.
- Prevenir envio duplicado sem perder a possibilidade de tentar novamente após uma falha.
- Para desktop/web, adaptar navegação e densidade da informação ao espaço disponível.

Existe um conceito visual demonstrado na conversa, com dados fictícios. Ele é referência de organização, não aplicativo Flutter implementado nem design final aprovado. Caso seu arquivo não esteja disponível no ambiente de desenvolvimento, criar a interface a partir destes requisitos sem inventar que o conceito foi inspecionado.

## 5. Entregas sugeridas

| Etapa | Entrega utilizável |
| --- | --- |
| 1 | Entrar, alternar PF/PJ, cadastrar conta e saldo inicial, cadastrar venda parcelada e registrar recebimentos. |
| 2 | Despesas, recorrências, faturas por total, transferências e acompanhamento de empréstimos. |
| 3 | Clientes, mensalidades, projetos avulsos e cobrança por etapas. |
| 4 | Construção, orçamento, compromissos, pagamentos vinculados e comprovantes. |
| 5 | Conferência com extratos, relatórios, exportação e acesso web refinado. |

Construção e empréstimo fazem parte do produto planejado. A ordem pode ser antecipada conforme a data de início da obra. Cada etapa precisa resultar em um fluxo funcional demonstrável.

## 6. Pontos ainda não definidos

- Identidade visual definitiva, logotipo e ícone do aplicativo. O nome BigDev.Z Finance já está definido.
- Licença open source. A criação do repositório público já foi autorizada.
- Bancos efetivamente utilizados como contas PF e PJ.
- Importação de extratos e eventual integração automática com bancos.
- Escrita offline e sincronização entre dispositivos.
- Cronograma e condições reais do empréstimo.
- Distribuição nas lojas, hospedagem e domínio.

Esses pontos não impedem o primeiro checkpoint. Usar o nome BigDev.Z Finance, dados fictícios, registro manual e API como fonte oficial. Apresentar o que depende de confirmação posterior sem transformar suposições em decisões aprovadas.

## 7. Prompt para executar o primeiro checkpoint

Você atuará como desenvolvedor responsável por iniciar o BigDev.Z Finance. Use todo o documento como contexto do produto. Execute a preparação inicial e a primeira entrega: uma venda parcelada com recebimentos persistidos no banco de dados, conectada a uma interface Flutter.

Trabalhe de forma incremental. Apresente decisões e progresso em português, avance com as escolhas técnicas reversíveis e finalize uma entrega utilizável. Não encerre apenas com um plano, uma lista de recomendações ou scaffolding sem integração.

### A. Reconhecimento e plano curto

1. Confirme o diretório atual, o estado do Git, arquivos existentes e instruções como `AGENTS.md`. A pasta esperada é `BigDev.Z Finance`. Preserve trabalho anterior e alterações não relacionadas.
2. Confira se existe um repositório Git herdado de uma pasta superior. Não inicialize nem altere outro projeto por engano. Se a raiz atual corresponder a outro projeto, esclareça apenas esse conflito antes de escrever nele; continue o que puder ser preparado de forma independente.
3. Verifique ferramentas disponíveis via CLI: Flutter/Dart, Docker Compose, Git, GitHub CLI (`gh`), PHP/Composer conforme o fluxo escolhido, Xcode quando estiver em macOS e Android SDK/emulador. Use versões compatíveis e registre a escolha. Não exponha tokens nem imprima arquivos de credenciais.
4. Apresente um plano curto e avance para a implementação dentro deste escopo. Resolva escolhas técnicas reversíveis com bom senso e documente as premissas.
5. Não execute ações destrutivas em bancos, volumes, containers ou arquivos de outros projetos. Não reutilize produção para testes.

### B. Estrutura e ambiente

1. Crie uma estrutura simples, como `apps/mobile`, `apps/api` e `docs`, adaptando-a ao que já existir.
2. Configure Flutter para iOS e Android e API Laravel com PostgreSQL.
3. Prepare Docker Compose para desenvolvimento do backend, incluindo healthcheck, migrations e persistência do banco.
4. Inclua `.env.example` sem segredos e instruções exatas de instalação. Adicione apenas serviços que este checkpoint realmente utilize.
5. Documente o endereço da API para emulador, simulador e aparelho físico. No aparelho físico, `localhost` é o próprio telefone; forneça configuração apropriada para alcançar a máquina de desenvolvimento.
6. Registre as decisões principais, os comandos de execução e eventuais limitações do ambiente. Gere e versione lockfiles adequados às aplicações.
7. Separe desenvolvimento e teste, incluindo banco de testes próprio. Os testes não podem apagar dados de uso manual.
8. Forneça comandos curtos, por exemplo via Makefile ou scripts, para iniciar o backend, aplicar migrations, carregar apenas dados fictícios e executar as verificações. Documente cada comando que realmente funcionar.
9. Use migrations e seeders reproduzíveis. O seed demonstrativo deve ser restrito a desenvolvimento/teste e não pode criar contas com senhas públicas em produção.
10. Prepare análise estática, formatação e testes relevantes. Configure uma CI inicial para a API com PostgreSQL e para análise/testes Flutter. Registre separadamente validação iOS em macOS e Android; não declare uma plataforma validada apenas porque os testes Dart passaram.

Arquivos iniciais esperados, com conteúdo coerente com o que estiver implementado:

| Arquivo ou diretório | Conteúdo |
| --- | --- |
| `README.md` | Apresentação do BigDev.Z Finance, estado real, instalação, execução e demonstração. |
| `AGENTS.md` | Instruções compartilhadas para IAs: comandos, arquitetura, regras financeiras, validação e atualização do handoff. |
| `HANDOFF.md` | Checkpoint, decisões, alterações, testes executados, bloqueios e próximo passo. |
| `ROADMAP.md` | Etapas do produto, distinguindo planejado, em andamento e concluído. |
| `CONTRIBUTING.md` | Como preparar o ambiente, validar alterações e propor contribuições. |
| `docs/architecture.md` | Estrutura, comunicação entre app/API e separação PF/PJ. |
| `docs/decisions/` | Decisões curtas sobre valores, datas, autenticação, estado Flutter e licenciamento pendente. |
| `docs/api.md` ou contrato OpenAPI | Endpoints implementados, autenticação e exemplos fictícios. |
| `.gitignore` | Segredos, arquivos locais, dumps, certificados, artefatos e dependências geradas fora do Git. |
| `.env.example` | Variáveis necessárias e exemplos seguros, sem credenciais reais. |
| `.github/workflows/` | Verificações automatizadas do checkpoint, sem ações de deploy. |

Concentrar instruções comuns em `AGENTS.md`. Caso a ferramenta local precise de um arquivo próprio, verificar sua convenção vigente e criar uma referência curta ao documento central, sem duplicar regras divergentes nem inventar suporte da ferramenta.

### C. Backend funcional

Implemente autenticação e autorização, espaços PF/PJ, contas com saldo inicial, acordos a receber, parcelas, recebimentos e a consulta dos saldos.

O fluxo mínimo precisa permitir:

1. Entrar no aplicativo.
2. Selecionar PF ou PJ.
3. Cadastrar uma conta com saldo inicial e data de referência.
4. Cadastrar um acordo como “Venda de veículo”, com total, quantidade de parcelas e primeiro vencimento.
5. Gerar e listar parcelas com vencimentos válidos, soma exata e numeração consistente.
6. Abrir uma parcela e registrar um recebimento total ou parcial, escolhendo data e conta do mesmo espaço.
7. Atualizar, em uma única transação, o recebimento, a movimentação da conta e as informações derivadas de parcela/acordo.
8. Mostrar quanto foi recebido, quanto falta receber, saldo da parcela e parcelas quitadas.
9. Consultar novamente esses dados após fechar e reabrir o aplicativo.

Use uma chave de idempotência ou mecanismo equivalente para impedir que um recebimento seja duplicado por reenvio. Vincule-a à operação e ao usuário/espaço apropriados; reutilizar uma chave com conteúdo diferente deve gerar conflito explícito. Valide o saldo restante também sob concorrência, usando transação e proteção adequada contra duas quitações simultâneas. Limite a soma recebida ao valor devido nesta entrega; adiantamentos de outras parcelas exigem selecionar explicitamente as parcelas correspondentes.

Dinheiro previsto não entra no saldo atual. Recusar contas de outro espaço. Não oferecer acesso a recursos de outro usuário mediante troca de IDs. Mensagens de erro precisam ser compreensíveis e não expor dados sensíveis.

Organize os contratos da API e documente exemplos de requisições/respostas. Implemente o fluxo real; não substitua persistência e integração por telas estáticas.

### D. Flutter funcional e cuidado visual

Implemente as telas de login, seleção PF/PJ, resumo, contas, acordos, detalhes das parcelas e registro de recebimento.

Escolha uma solução de gerenciamento de estado e navegação adequada, usando versões compatíveis. Separe acesso à API, estado de apresentação e componentes visuais. Evite adicionar bibliotecas para funcionalidades que ainda não existem.

Use um design consistente, com paleta sóbria, hierarquia tipográfica, espaçamento, ícones coerentes, temas claro/escuro e valores legíveis. A seleção PF/PJ deve permanecer clara nas telas de cadastro e confirmação.

Trate loading, falha de rede, validações, ausência de dados e sucesso. Persistir a autenticação em armazenamento adequado à plataforma. Atualizar os dados apresentados após um recebimento e após a troca de espaço.

É aceitável usar dados fictícios no seed e em previews. No fluxo principal, os dados devem vir da API. Não exibir uma ação como concluída antes da confirmação do backend.

### E. Cenários de aceitação obrigatórios

Use dados fictícios. Para o cenário financeiro principal, considere uma conta PF com saldo inicial de R$ 1.000,00, data anterior ao recebimento e nenhuma outra movimentação:

1. Cadastrar R$ 24.000,00 em 12 parcelas gera exatamente 12 parcelas de R$ 2.000,00. Apenas cadastrar o acordo mantém o saldo da conta em R$ 1.000,00.
2. Receber R$ 2.000,00 da primeira parcela eleva o saldo para R$ 3.000,00, deixa uma parcela quitada e R$ 22.000,00 a receber.
3. Receber R$ 500,00 da segunda parcela eleva o saldo para R$ 3.500,00, deixa R$ 1.500,00 nessa parcela e R$ 21.500,00 no acordo. A segunda parcela permanece parcialmente recebida.
4. Reenviar a mesma operação com a mesma identificação não duplica o recebimento nem muda o saldo uma segunda vez.
5. Usar uma conta PJ para receber esse acordo PF é recusado sem gravação parcial.
6. Outro usuário não consegue acessar conta, acordo, parcela ou recebimento alheio alterando os IDs das requisições.
7. Um erro durante a efetivação não deixa recebimento gravado sem a movimentação correspondente, ou vice-versa.
8. Dividir R$ 100,00 em três parcelas preserva o total exato, com distribuição documentada dos centavos.
9. Um acordo com vencimento de referência no dia 31 usa uma data válida em fevereiro e preserva a referência para março.
10. Trocar PF/PJ não mantém dados do espaço anterior na tela. Fechar e reabrir o app permite recuperar os dados efetivados pela API.
11. Duas solicitações simultâneas não podem quitar além do saldo restante. A mesma chave idempotente com outro valor ou outra parcela deve ser rejeitada.

Automatize os testes que validem essas regras, incluindo integração com PostgreSQL onde a integridade do banco é relevante. No Flutter, cubra os comportamentos centrais da tela e a integração possível no ambiente. Não substitua cenários reais por testes que apenas confirmem a existência de componentes.

### F. Git, criação do repositório e preparação para código aberto

O usuário autorizou criar `bigdevz-finance` como repositório público, usando **GitHub CLI na máquina local**. Execute essa parte quando `gh` estiver autenticado e a identidade do proprietário estiver confirmada. A publicação do código inicial pertinente a este projeto está incluída neste fluxo; não publique arquivos alheios, dados reais ou credenciais.

1. Inspecione o Git local. Se esta pasta ainda não for um repositório próprio, inicialize-a com branch principal `main`. Não reescreva histórico existente nem altere configurações globais de identidade do Git.
2. Use `gh auth status` e identifique o usuário com `gh api user --jq '.login'`. Não use comandos que exibam o token. Se houver dúvida sobre a conta correta, resolva a identidade antes da criação remota. Se precisar de login, oriente `gh auth login` e permita que o usuário conclua o fluxo oficial; não solicite senhas ou tokens no chat.
3. Use por padrão a conta pessoal autenticada que corresponde ao usuário; não escolha uma organização apenas por causa do nome BigDev.Z. Não deduza o login do GitHub a partir de nome, e-mail, LinkedIn ou domínio.
4. Consulte a existência de `<proprietario-verificado>/bigdevz-finance`. Diferencie ausência confirmada de falha de rede ou de permissão.
5. Se o repositório não existir, crie-o público com descrição “Controle financeiro pessoal e empresarial em Flutter, Laravel e PostgreSQL.” Se já existir, inspecione conteúdo, proprietário, visibilidade e remotes antes de reutilizá-lo. Não sobrescreva um repositório de finalidade diferente nem altere sua visibilidade automaticamente.
6. Vincule `origin` somente se não houver conflito. Se houver um remoto diferente, preserve-o e esclareça o destino em vez de substituí-lo silenciosamente.
7. Crie commits pequenos e coerentes. Revise explicitamente os arquivos a versionar, o diff preparado e as verificações disponíveis antes do push. Não use force push.
8. Envie a branch correta para o remoto e confira a URL, a visibilidade pública e o commit remoto. Não afirme que o repositório foi criado ou atualizado apenas porque um comando foi planejado.

Exemplo de criação, a executar somente após resolver a identidade e confirmar que o repositório ainda não existe. `finance_owner` deve conter o login verificado; não é um valor para adivinhar:

```bash
finance_owner="$(gh api user --jq '.login')"
gh repo create "$finance_owner/bigdevz-finance" \
  --public \
  --source=. \
  --remote=origin \
  --description 'Controle financeiro pessoal e empresarial em Flutter, Laravel e PostgreSQL.'
```

O push é uma etapa posterior, após commits e revisão. Se não houver GitHub CLI ou sessão autenticada, conclua a estrutura e o desenvolvimento local, documente precisamente o que falta e forneça as instruções oficiais de instalação/autenticação. O login deve ser feito pelo usuário no fluxo apropriado, sem enviar credenciais para o chat. Não trate a falta de acesso remoto como motivo para abandonar a implementação local.

Para o código aberto e o build in public:

- Use apenas dados fictícios em seeds, fixtures, screenshots e gravações; não leve a planilha financeira real para o repositório.
- Exclua segredos, certificados de assinatura, dados financeiros reais, dumps e comprovantes do versionamento.
- Registre a licença como decisão pendente. A licença MIT pode ser apresentada como sugestão para avaliação; não crie uma concessão de licença definitiva em nome do usuário sem essa escolha estar definida.
- Enquanto a licença não for escolhida, descreva o estado como “repositório público em desenvolvimento; licença em definição”, sem afirmar que já possui uma licença open source.
- Atualize README, roadmap e handoff ao concluir cada incremento. Mostre resultados verificáveis e aprendizados nas notas de evolução.
- Não envie posts, mensagens ou cobranças em nome do usuário. Não publique apps nas lojas nem implante infraestrutura de produção neste checkpoint.

### G. Relatório final da execução

Ao concluir, apresente:

1. O que foi implementado e o que ainda não está pronto.
2. Comandos exatos para subir o backend e abrir o aplicativo.
3. Credenciais fictícias de desenvolvimento, somente quando criadas para o ambiente local.
4. Um roteiro de teste manual do cadastro até o recebimento e consulta de saldo.
5. Evidências dos testes executados e limitações encontradas.
6. Como testar no iPhone e no Android, distinguindo instruções preparadas de testes realmente executados.
7. URL real do repositório, proprietário verificado, branch e commit enviados; ou o bloqueio exato que impediu a criação/push.
8. O estado das decisões pendentes, especialmente a licença.
9. O próximo incremento recomendado.

Não afirme que o app foi testado no iPhone se apenas houve build ou instruções para Xcode. Se faltar uma ferramenta ou houver restrição do ambiente, conclua o trabalho independente desse bloqueio e informe precisamente o que falta verificar. Preserve erros financeiros e falhas de isolamento como bloqueadores de conclusão funcional.

Comece pela inspeção do projeto e execute este checkpoint até obter o fluxo utilizável ou encontrar um bloqueio concreto que impeça sua continuidade.

## 8. Referências técnicas

- [Plataformas suportadas pelo Flutter](https://docs.flutter.dev/reference/supported-platforms)
- [Configuração do Flutter para iOS](https://docs.flutter.dev/platform-integration/ios/setup)
- [Build e distribuição Android](https://docs.flutter.dev/deployment/android)
- [Interfaces adaptativas em Flutter](https://docs.flutter.dev/ui/adaptive-responsive)
- [Arquitetura de aplicativos Flutter](https://docs.flutter.dev/app-architecture/guide)
- [Laravel Sanctum](https://laravel.com/docs/sanctum)
- [Laravel e bancos de dados](https://laravel.com/docs/database)
- [Docker Compose](https://docs.docker.com/compose/)
- [Tipos numéricos do PostgreSQL](https://www.postgresql.org/docs/current/datatype-numeric.html)
- [Conta de desenvolvedor Apple e testes pessoais](https://developer.apple.com/help/account/basics/about-your-developer-account)
- [Criação de repositórios com GitHub CLI](https://cli.github.com/manual/gh_repo_create)
- [Licenciamento de um repositório](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)

Consultar a documentação vigente ao configurar o ambiente. Este documento não fixa preços, versões mínimas de dispositivos ou regras de publicação das lojas.
