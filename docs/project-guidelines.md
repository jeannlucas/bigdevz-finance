# BigDev.Z Finance — Diretrizes do Projeto (Project Guidelines)

Este documento consolida as diretrizes permanentes, princípios arquiteturais, regras financeiras, padrões de engenharia, convenções do design system e políticas de colaboração do BigDev.Z Finance. Serve como referência canônica para desenvolvedores, agentes autônomos e colaboradores.

---

## 1. Princípios do Produto

- **Objetivo**: Aplicação de gestão financeira pessoal e empresarial, desenhada para fornecer controle absoluto de fluxo de caixa, compromissos futuros e histórico contábil.
- **Separação Rígida PF e PJ**: Finanças pessoais e empresariais coexistem na mesma conta de usuário, mas operam em **espaços lógicos totalmente isolados**. Uma conta bancária, cartão ou compromisso pertence a exatamente um espaço. Não há mistura de saldos, lançamentos ou transferências implícitas entre PF e PJ.
- **Integridade Financeira Inegociável**: Dinheiro é exato. Arredondamentos não perdem centavos, operações são determinísticas e transações concorrentes são rigorosamente controladas.
- **Experiência Fintech Profissional**: Interface de usuário moderna, fluida e clara, com contraste refinado, tipografia estruturada, sem jargões confusos e com forte suporte à acessibilidade visual e motora.
- **Preservação do Histórico Contábil**: Operações financeiras efetivadas são imutáveis no histórico. Não se apaga um registro para corrigir um saldo; realizam-se estornos, compensações ou ajustes auditáveis com registro de motivo e data.
- **Desenvolvimento Público e Open Source**: O projeto é desenvolvido com intenção pública e código aberto, exigindo higiene estrita de segurança, ausência de credenciais reais ou dados pessoais (PII) e documentação transparente.

---

## 2. Arquitetura do Sistema

O sistema é estruturado como um cliente mobile conectado a uma API backend com persistência relacional:

```
[ apps/mobile (Flutter/Dart) ]
               │
               ▼ HTTP REST (JSON) + Bearer Token (Sanctum)
[ apps/api (Laravel Modular) ]
               │
               ▼ Conexão direta isolada (sem acesso externo)
[ PostgreSQL 18 (Bancos dev e test independentes) ]
```

### 2.1. Backend (`apps/api`)
- **Framework**: Laravel 13.34 (`^13.17`) / PHP 8.3 (64-bit).
- **Estrutura**: Monólito modular organizado por domínios de negócio (`Receivables`, `Payables`, `Accounts`, `Auth`).
- **Lógica de Domínio Pura**: Regras de cálculo monetário, cronogramas de parcelas e datas mensais residem no domínio puro PHP (`apps/api/app/Domain`), sem dependência direta de framework ou banco de dados, sendo testáveis isoladamente.
- **Actions e Transações**: Operações que alteram estado financeiro são implementadas em Actions dedicadas (`app/Actions`), executadas dentro de transações de banco com locks explícitos (`lockForUpdate`).

### 2.2. Frontend Mobile (`apps/mobile`)
- **Framework**: Flutter (canal stable) / Dart 3.x.
- **Estrutura por Funcionalidades**: Código organizado em `lib/features/` (`accounts`, `agreements`, `payables`, `auth`, `home`, `summary`) e componentes de design system em `lib/ui/`.
- **Armazenamento Local Mínimo**: O aplicativo **não replica nem armazena dados financeiros localmente**. Apenas o token de sessão e o espaço ativo selecionado são guardados de forma segura via Keychain (iOS) ou Keystore (Android) (`SecureSessionStorage`).
- **Gerenciamento de Estado**: State management enxuto e previsível via `Provider` e `ChangeNotifier` (`SessionController`).
- **Suporte Multiplataforma**: Execução nativa homologada em **iOS** e **Android**. Configuração de endpoints via `--dart-define=API_BASE_URL=...` (`127.0.0.1` no iOS e `10.0.2.2` no emulador Android). Instruções completas em [docs/mobile-development.md](mobile-development.md).

### 2.3. Banco de Dados e Infraestrutura
- **PostgreSQL 18**: Banco relacional robusto. Acesso externo bloqueado em produção; em desenvolvimento local, exposto via porta mapeada no Docker Compose.
- **Isolamento de Bancos**:
  - `bigdevz_finance`: banco de desenvolvimento para interação manual.
  - `bigdevz_finance_test`: banco isolado exclusivo para testes automatizados. A suíte de testes recusa terminantemente qualquer banco que não termine em `_test`.
- **Docker Compose**: Define os serviços da API, scheduler e PostgreSQL em sub-rede controlada sem colisão de portas.

---

## 3. Regras Financeiras Fundamentais

Todas as implementações financeiras devem obedecer estritamente aos princípios consolidados nas decisões de arquitetura ([`docs/decisions/`](decisions/)):

### 3.1. Representação Exata de Dinheiro (Sem Float)
- **Regra**: Valores monetários são manipulados internamente como **centavos inteiros (`int`)**.
- **Interface e API**: Na API e nos formulários, dinheiro é representado exclusivamente como string decimal canônica com ponto e duas casas decimais (ex.: `"1250.50"`), variando de `"0.00"` a `"999999999999.99"`.
- **Proibições**: É proibido o uso de números de ponto flutuante (`float`/`double`) para valores monetários. Formatos com vírgula, mais de duas casas ou notação científica são rejeitados com erro de validação (`422 Unprocessable Entity`).
- *Referência técnica*: Decisão [0002 — Dinheiro e geração de parcelas](decisions/0002-dinheiro-e-parcelas.md).

### 3.2. Distribuição Determinística de Centavos e Vencimentos
- **Divisão de Parcelas**: Quando o valor total não divide exatamente pelo número de parcelas, a fração excedente de centavos é distribuída obrigatoriamente nas primeiras parcelas (1 centavo por parcela inicial), garantindo que a soma exata das parcelas seja idêntica ao total contratado.
- **Preservação do Dia de Referência**: Vencimentos em dias 29, 30 ou 31 preservam o dia original. Se um mês seguinte tiver menos dias (ex.: fevereiro com 28 ou 29 dias), o vencimento ocorre no último dia do mês curto, mas nos meses subsequentes mais longos (ex.: março), o dia 31 volta a ser utilizado como referência.
- *Referência técnica*: [`MonthlyDate.php`](../apps/api/app/Domain/Receivables/MonthlyDate.php) e Decisão [0002](decisions/0002-dinheiro-e-parcelas.md).

### 3.3. Saldo Disponível vs. Valores Previstos
- **Saldo Disponível**: Reflete exclusivamente a soma algébrica das movimentações financeiras efetivamente liquidadas (`AccountMovement`).
- **Valores Previstos**: Contas a pagar pendentes, parcelas futuras e compromissos recorrentes geram previsão de fluxo de caixa, mas **nunca afetam o saldo disponível da conta bancária** até que o pagamento seja registrado e efetivado.
- **Contas Arquivadas**: Contas desativadas não aparecem para novos lançamentos, mas seu saldo permanece computado no saldo total patrimonial do espaço.
- *Referência técnica*: Decisão [0005 — Editar, corrigir abertura e arquivar contas](decisions/0005-editar-e-arquivar-contas.md).

### 3.4. Idempotência e Concorrência
- **Chave de Idempotência**: Toda mutação financeira crítica (recebimentos, pagamentos, cadastros) exige uma chave de idempotência vinculada ao escopo `(usuário, espaço, operação)`.
- **Reenvio Idêntico**: Repetições de requisições com a mesma chave e idêntico payload retornam o resultado da operação original (`200 OK` com `replayed: true`), protegendo o cliente contra duplicações em quedas de rede.
- **Conflito de Payload**: O reuso da mesma chave com dados distintos resulta em conflito (`409 Conflict`).
- **Proteção contra Concorrência**: Atualizações de saldo e lançamentos concorrentes utilizam bloqueio pessimista (`SELECT FOR UPDATE`) para evitar condições de corrida em requisições paralelas.

### 3.5. Estornos, Correções e Auditoria
- **Imutabilidade**: Registros financeiros efetivados nunca são excluídos (`DELETE`).
- **Estorno**: Um estorno gera uma contra-movimentação de sinal oposto vinculada à transação original, restaurando o saldo e o restante da obrigação.
- **Correção de Destino**: Caso um lançamento tenha sido direcionado para a conta errada, a correção movimenta os fundos entre as contas sem alterar o status da obrigação nem inflar o faturamento.
- *Referência técnica*: Decisão [0004 — Estorno e correção de recebimentos](decisions/0004-estorno-e-correcao.md).

### 3.6. Módulo de Contas a Pagar (`Payables`)
- **Modalidades**:
  - *Avulsa*: compromisso pontual de parcela única.
  - *Parcelada*: obrigação dividida em número fixo de parcelas calculadas determinística e cronologicamente.
  - *Recorrente*: compromissos periódicos contínuos (mensalidades, assinaturas), com geração antecipada de ocorrências e suporte a término opcional.
  - *Faturas de Cartão*: obrigações vinculadas a cartões com possibilidade de valor inicial indefinido até o fechamento.
- *Referência técnica*: Decisão [0006 — A pagar](decisions/0006-a-pagar.md).

---

## 4. Padrões de Desenvolvimento e Engenharia

### 4.1. Código e Tipagem
- **Laravel / PHP**:
  - Código aderente às PSRs com formatação obrigatória via Laravel Pint (`vendor/bin/pint --test`).
  - Uso estrito de tipagem em métodos, parâmetros e retornos (`declare(strict_types=1)` onde aplicável).
  - Tratamento de exceções com respostas JSON padronizadas e códigos HTTP semânticos (200, 201, 400, 401, 403, 404, 409, 422).
- **Flutter / Dart**:
  - Formatação estrita com `dart format --output=none --set-exit-if-changed`.
  - Zero warnings em `flutter analyze`.
  - Não utilizar `double` para cálculos financeiros; utilizar a classe utilitária `Money`.

### 4.2. Estratégia de Testes
O projeto possui pirâmide de testes bem definida e obrigatória:
1. **Testes de Domínio Puro (`apps/api/tests/domain.php`)**: Testes PHP puros sem banco de dados, validando centavos, divisões, limites e calendários em frações de segundo (`make test-domain`).
2. **Testes de Feature e Concorrência da API (`apps/api/tests/Feature/`)**: Testes executados contra o PostgreSQL real (`bigdevz_finance_test`), incluindo simulação de processos concorrentes paralelos (`worker` PHP) e rollback automático por transação (`make test-api`).
3. **Testes de Smoke da API (`scripts/smoke-api.sh`)**: Roteiro HTTP executado contra os endpoints do container Docker em execução (`make smoke-api`).
4. **Testes de Widgets e Unidade Mobile (`apps/mobile/test/`)**: Testes rápidos com mock das APIs, cobrindo regras de UI, cálculo de tela, insets e formulários (`make test-mobile`).
5. **Testes de Integração Mobile (`apps/mobile/integration_test/`)**: Testes de ponta a ponta executados no simulador contra a API real, incluindo geração de capturas oficiais e auditoria de fluxos.

---

## 5. Design System e Identidade Visual

A identidade visual foi desenhada e aprovada para transmitir segurança, autoridade e elegância fintech.

### 5.1. Marca e Logotipo
- **Símbolo Oficial**: Gorila geométrico da BigDev.Z em duas variações oficiais:
  - Tema Claro: [`assets/brand/gorilla_dark.png`](../apps/mobile/assets/brand/gorilla_dark.png) (gorila escuro para fundos claros).
  - Tema Escuro: [`assets/brand/gorilla_white.png`](../apps/mobile/assets/brand/gorilla_white.png) (gorila claro para fundos escuros).
- **Componente**: [`BrandHeader`](../apps/mobile/lib/ui/app_brand.dart), exibindo a marca com proporções compactas no topo do app.

### 5.2. Paleta de Cores e Temas
- **Espaço PF (Pessoal)**:
  - Cor primária: Azul Marinho Profundo (`#0A192F` / `#1E3A8A`).
  - Cartão: gradiente azul escuro com efeito translúcido da marca.
- **Espaço PJ (Empresarial)**:
  - Cor primária: Verde Esmeralda Rico (`#064E3B` / `#047857`).
  - Cartão: gradiente verde escuro alinhado verticalmente com o cartão PF.
- **Temas**: Suporte completo a Modo Claro (*Light*) e Modo Escuro (*Dark*), orquestrado dinamicamente via [`buildTheme(brightness, seed)`](../apps/mobile/lib/ui/theme.dart).

### 5.3. Tipografia e Tokens
- **Escala de Espaçamento**: Padronizada em [`AppTokens`](../apps/mobile/lib/ui/app_tokens.dart) (`p4`, `p8`, `p12`, `p16`, `p20`, `p24`, `p32`, raios de borda `r8`, `r12`, `r16`, `r24`).
- **Ícones**: Biblioteca Hugeicons (estilo Stroke Rounded) abstraída e padronizada em [`AppIcons`](../apps/mobile/lib/ui/app_icons.dart).

### 5.4. Acessibilidade e Responsividade
- **SafeArea Rigorosa**: AppBar e componentes de tela devem sempre respeitar os insets da barra de status, Dynamic Island e home indicator.
- **Textos Ampliados (150% e 200%)**:
  - Proibido o uso de `TextOverflow.ellipsis` em rótulos essenciais de formulários.
  - Componente [`AccessibleFieldWrapper`](../apps/mobile/lib/ui/widgets.dart): renderiza rótulos acima do campo em `Text` multilinhas quando o fator de escala do texto for maior que 1.2x.
  - Seletor de modalidade adaptativo (`_KindSelector`): adota disposição vertical com botões de no mínimo 48pt de altura sob textos ampliados, prevenindo quebras de layout.
  - Formulários mantêm rolagem livre até as ações finais mesmo sob teclado virtual aberto.

---

## 6. Governança, Git e Colaboração

- **Autorização para Ações no Git**:
  - **Proibido** realizar `git add`, `git commit`, `git push`, `git merge`, `pull request` ou troca de branch sem instrução expressa e inequívoca do usuário.
  - **Proibido** executar comandos destrutivos (`git reset --hard`, `git clean -fd`, `git stash drop`).
- **Preservação de Alterações Locais de Máquina**:
  - Arquivos de configuração de assinatura e tooling (`project.pbxproj`, `Info.plist`, `devtools_options.yaml`) devem ser protegidos e analisados antes de qualquer publicação para não vazar times de desenvolvimento (`DEVELOPMENT_TEAM`) específicos do Mac local.
- **Convenção de Commits**:
  - Mensagens de commit em **português do Brasil (pt-BR)** seguindo Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `chore:`).
  - **Não adicionar linhas `Co-Authored-By`**, conforme preferência estabelecida do mantenedor.
- **Proteção contra Vazamento de Dados**:
  - Nunca commitar arquivos `.env` reais (apenas `.env.example`).
  - Não commitar chaves privadas, certificados, logs, dumps SQL ou dados financeiros reais.

---

## 7. Catálogo Oficial de Evidências Visuais

As evidências visuais aprovadas comprovam o estado funcional e de acessibilidade do aplicativo e estão catalogadas em [`prints/`](../prints/):

1. `dark_01_resumo_pf.png` — Resumo financeiro PF em tema escuro.
2. `dark_02_resumo_pj.png` — Resumo financeiro PJ em tema escuro.
3. `dark_03_carteira_pf.png` — Carteira de contas PF com cartão azul e alinhamento estável.
4. `dark_04_carteira_pj.png` — Carteira de contas PJ com cartão verde esmeralda.
5. `dark_05_a_pagar_pf.png` — Lista de contas a pagar em tema escuro.
6. `dark_06_cadastro_pagar_recorrente.png` — Cadastro de conta recorrente em tema escuro.
7. `light_01_resumo_pf.png` — Resumo financeiro PF em tema claro.
8. `light_02_resumo_pj.png` — Resumo financeiro PJ em tema claro.
9. `light_03_carteira_pf.png` — Carteira de contas PF em tema claro com cartão azul e dados PF.
10. `light_04_carteira_pj.png` — Carteira de contas PJ em tema claro com dados PJ.
11. `light_05_a_pagar_pf.png` — Lista de contas a pagar em tema claro.
12. `light_06_cadastro_pagar_recorrente.png` — Cadastro de conta recorrente em tema claro.
13. `a11y_375px_scale_150_seletor.png` — Formulário em largura 375pt com texto em 150%, SafeArea preservada e seletor vertical.
14. `a11y_375px_scale_200_seletor.png` — Formulário em largura 375pt com texto em 200%, rótulos multilinhas e sem truncamento.
15. `a11y_iphone17pro_scale_200_seletor.png` — Formulário na largura do iPhone 17 Pro com texto em 200%.
