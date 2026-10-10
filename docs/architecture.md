# Arquitetura

Estado em 04/10/2026: checkpoint 1 implementado (ver HANDOFF para o que foi
validado e o que falta).

```
apps/mobile (Flutter)  --HTTP JSON + token Sanctum-->  apps/api (Laravel)  -->  PostgreSQL
```

Somente a API acessa o banco. O app não guarda dados financeiros localmente:
apenas o token e o espaço ativo, no Keychain/Keystore.

## API (`apps/api`)

| Camada | Local | Papel |
| --- | --- | --- |
| Núcleo puro | `app/Domain/Receivables` | `Money` (centavos/strings), `InstallmentSchedule` e `MonthlyDate` (datas e parcelas). Sem framework. |
| Casos de uso | `app/Actions/Receivables`, `app/Actions/Payables`, `app/Actions/Accounts` | Criação de acordos, recebimentos, estornos, pagamentos, arquivamento e ajustes de abertura (transação, locks, idempotência). |
| HTTP | `app/Http/Controllers/Api`, `app/Http/Resources`, `app/Rules` | Validação, escopo por usuário/espaço, serialização com dinheiro em string. |
| Dados | `app/Models`, `database/migrations` | Eloquent; invariantes repetidas no banco (FKs compostas, CHECKs, UNIQUE). |

Separação PF/PJ: todo recurso tem `space_id`; os controllers resolvem o espaço
a partir do usuário autenticado (`Controller::space`) e buscam o recurso
dentro dele. O banco impede, por FK composta `(id, space_id)`, que um
recebimento ou pagamento ligue obrigações e contas de espaços diferentes.

Fluxo do recebimento (`ReceiveInstallment`) e pagamento (`PayPayable`): trava o recurso,
confere a chave idempotente, trava a conta, valida espaço/data/restante/limite, grava
operação + movimentação na mesma transação. O saldo da conta é o saldo inicial mais
as movimentações; acordos e parcelas pendentes nunca entram no saldo disponível.

## App (`apps/mobile/lib`)

| Pasta | Conteúdo |
| --- | --- |
| `core/` | `ApiClient`, `Money`, datas, configuração da URL, armazenamento seguro. |
| `features/auth` | Login, `SessionController` (sessão, espaço ativo, versão dos dados). |
| `features/summary`, `accounts`, `agreements`, `payables`, `home` | Repositórios, modelos e telas por funcionalidade financeira. |
| `ui/` | Design system da marca (`app_brand`, `app_tokens`, `app_icons`), temas (`theme.dart`), acessibilidade (`widgets.dart`, `date_field.dart`). |

Diretrizes detalhadas de arquitetura e regras financeiras consolidadas: `docs/project-guidelines.md`.

Ao trocar PF/PJ, o `SessionController` incrementa a versão dos dados e a
subárvore da tela é recriada com chave do espaço; respostas atrasadas do
espaço anterior são descartadas. Após um recebimento confirmado pela API, as
telas recarregam.

## Ambiente

`docker-compose.yml` (projeto `bigdevz-finance`) sobe PostgreSQL 18 e a API.
Bancos `bigdevz_finance` (manual) e `bigdevz_finance_test` (suíte). Detalhes e
motivos em `docs/decisions/0003-api-app-e-ambiente.md`.
