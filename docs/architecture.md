# Arquitetura prevista

Este documento descreve a base solicitada, ainda sem aplicações integradas.
O núcleo independente em `apps/api/app/Domain/Receivables` já implementa
valores exatos e geração de parcelas. É PHP puro, sem dependências externas;
será chamado pelo caso de uso Laravel quando o ambiente permitir instalá-lo.

Flutter em `apps/mobile` consumirá exclusivamente a API autenticada Laravel
em `apps/api`. PostgreSQL será acessado somente pelo backend. Docker Compose
terá API e banco de desenvolvimento, com banco de testes separado. Serviços
adicionais só entram quando necessários ao checkpoint.

Cada recurso financeiro terá espaço explícito. A API verificará o vínculo ao
usuário e a compatibilidade de espaço entre acordo, parcela e conta. O Flutter
limpará dados e invalidará respostas anteriores ao trocar PF/PJ.

O compromisso gera parcelas, mas não movimenta contas. Um recebimento confirmado
gera a movimentação na mesma transação. O saldo parte do marco inicial da conta;
recebimentos anteriores ao marco exigem regra de conciliação antes de suporte.
Concorrência e idempotência serão verificadas com PostgreSQL real.

Os detalhes de schema, rotas, bibliotecas e versões dependem da implementação.
Não há endpoints publicados ou contratos implementados nesta preparação.
