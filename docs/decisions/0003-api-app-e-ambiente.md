# 0003 — API, app e ambiente do checkpoint 1

Data: 04/10/2026. Estado: implementado e testado (ver HANDOFF).

## Versões verificadas nesta data

Laravel 13.34.0 (PHP ^8.3) com Sanctum 4; PHP 8.3.31 local; PostgreSQL 18.6
(`postgres:18-alpine`); Flutter 3.47.6 stable / Dart 3.13.5 (canal estável
atual no `releases_macos.json` oficial); provider 6.1.5+1, http 1.6.0,
flutter_secure_storage 11.2.0. Lockfiles: `apps/api/composer.lock`,
`apps/mobile/pubspec.lock`.

## Backend

- Monólito Laravel: núcleo puro em `app/Domain/Receivables` (inalterado no
  comportamento), casos de uso em `app/Actions/Receivables`, HTTP em
  `app/Http`. Sem camada de repositório: Eloquent direto, proporcional ao porte.
- Autenticação por token Sanctum (app móvel, sem cookies). Cada usuário nasce
  com um espaço PF e um PJ.
- Dinheiro no banco: `BIGINT` em centavos com `CHECK` entre 0 e
  99999999999999, **não** `NUMERIC(19,2)`: mantém o contrato da decisão 0002
  sem ampliar o limite. Somas de saldo são feitas pelo PostgreSQL (`SUM` de
  `bigint` retorna `numeric`) e cada gravação recusa saldo acima do limite.
- Integridade no banco: FKs compostas `(id, space_id)` impedem parcela,
  recebimento e conta de espaços diferentes; `CHECK received_cents <=
  amount_cents`; `UNIQUE (space_id, idempotency_key)`; movimentação 1:1 com
  recebimento.
- Recebimento: transação única; `SELECT … FOR UPDATE` na parcela e depois na
  conta (ordem fixa); idempotência conferida depois do lock; incremento
  `received_cents = received_cents + ?` no SQL.
- Restrições deliberadas: saldo inicial não negativo; movimentações só de
  entrada (recebimentos); recebimento anterior ao marco inicial da conta é
  recusado até existir regra de conciliação; idempotência apenas no
  recebimento (criação de conta/acordo depende do bloqueio de duplo toque no app).

## Ambiente e testes

- Compose `bigdevz-finance`: `postgres` (127.0.0.1:5440) e `api`
  (127.0.0.1:8000, `php artisan serve`). Sub-rede fixa `10.88.231.0/24` porque
  os pools padrão do Docker desta máquina estavam esgotados por outros projetos.
- Bancos separados: `bigdevz_finance` (uso manual) e `bigdevz_finance_test`
  (suíte). A suíte recusa rodar fora de banco `_test`, só executa `migrate`
  (nunca `fresh`/`TRUNCATE`), isola testes em transação e, no teste de
  concorrência, apaga somente as linhas que criou.
- Sem `.env` real no repositório nem criado pelo agente: o container gera uma
  `APP_KEY` efêmera em memória quando não há `.env`.

## App Flutter

- MVVM leve conforme o guia oficial de arquitetura: `ChangeNotifier` +
  `provider`; repositórios por funcionalidade sobre um `ApiClient` único;
  navegação com `Navigator` nativo (sem pacote de rotas).
- Token e espaço ativo no Keychain/Keystore (`flutter_secure_storage`).
- Troca PF/PJ: subárvore da tela recriada por chave do espaço e respostas
  antigas descartadas por ticket; cor do tema muda com o espaço.
- Dinheiro como centavos `int`, nunca `double`; máscara BRL própria.
- Chave idempotente gerada por conteúdo do formulário: nova tentativa do mesmo
  conteúdo reaproveita a chave.
- URL da API por `--dart-define=API_BASE_URL`. HTTP liberado só para rede local
  (iOS `NSAllowsLocalNetworking`; Android cleartext apenas no build debug).

## Pendentes

Licença; identidade visual definitiva e ícone; política de produção (HTTPS,
hospedagem); estorno de recebimento; idempotência genérica para outras
operações.
