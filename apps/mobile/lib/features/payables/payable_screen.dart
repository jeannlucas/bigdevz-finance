import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../accounts/account.dart';
import '../accounts/accounts_repository.dart';
import '../agreements/pending_receipt_card.dart';
import '../agreements/receipt_attempts.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import 'payable.dart';
import 'payable_edit_screen.dart';
import 'payables_repository.dart';
import 'payables_tab.dart' show payableStatusChip;
import 'payment_fix_screen.dart';
import 'payment_form_screen.dart';

/// Detalhe da obrigação: valores, pagamentos (com estornos e correções),
/// histórico e ações. Operação de pagamento sem confirmação bloqueia as
/// demais nesta obrigação até ser verificada.
class PayableScreen extends StatelessWidget {
  const PayableScreen({
    super.key,
    required this.space,
    required this.payableId,
  });

  final Space space;
  final int payableId;

  Future<(Payable, List<Account>, ReceiptAttempt?)> _load(
    BuildContext context,
  ) async {
    final userId = context.read<SessionController>().user?.id;
    final results = await Future.wait([
      context.read<PayablesRepository>().find(space.id, payableId),
      context.read<AccountsRepository>().list(space.id),
      if (userId != null)
        context.read<ReceiptAttempts>().pendingPayment(
          userId,
          space.id,
          payableId,
        )
      else
        Future.value(),
    ]);
    return (
      results[0] as Payable,
      results[1] as List<Account>,
      results[2] as ReceiptAttempt?,
    );
  }

  void _notify(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  void _settled(BuildContext context, ReceiptAttemptOutcome outcome) {
    final balance = outcome.payment?.accountBalance;
    _notify(
      context,
      balance == null
          ? outcome.message
          : '${outcome.message} Saldo da conta: ${balance.brl}.',
    );
    context.read<SessionController>().dataChanged();
  }

  Future<void> _push(BuildContext context, Widget child) async {
    final result = await Navigator.of(context)
        .push<Object>(spaceRoute(isPf: space.isPf, child: child));
    if (!context.mounted || result == null) return;
    if (result is ReceiptAttemptOutcome) {
      _settled(context, result);
    } else if (result is String) {
      _notify(context, result);
    }
  }

  Future<void> _cancel(BuildContext context, Payable payable) async {
    final reason = await _askText(
      context,
      title: 'Cancelar conta a pagar?',
      message:
          'A obrigação sai dos totais em aberto e fica no histórico como '
          'cancelada. Nenhum dinheiro é movimentado.',
      label: 'Motivo',
      confirm: 'Cancelar conta',
    );
    if (reason == null || !context.mounted) return;
    try {
      await context.read<PayablesRepository>().cancel(
        space.id,
        payable.id,
        reason,
      );
      if (!context.mounted) return;
      context.read<SessionController>().dataChanged();
      _notify(context, 'Conta a pagar cancelada.');
    } on ApiException catch (error) {
      if (context.mounted) _notify(context, error.message);
    }
  }

  Future<void> _editFuture(BuildContext context, Payable payable) async {
    final value = await _askText(
      context,
      title: 'Alterar ocorrências futuras',
      message:
          'Vale para as ocorrências com vencimento de hoje em diante, sem '
          'pagamento, não canceladas e não editadas individualmente. Pagas, '
          'parciais e vencidas ficam como estão.',
      label: 'Novo valor mensal',
      confirm: 'Aplicar às futuras',
      money: true,
    );
    if (value == null || !context.mounted) return;
    try {
      await context.read<PayablesRepository>().updateRecurrence(
        space.id,
        payable.recurrenceId!,
        {'amount': Money.fromInput(value)!.toApi()},
      );
      if (!context.mounted) return;
      context.read<SessionController>().dataChanged();
      _notify(context, 'Ocorrências futuras atualizadas.');
    } on ApiException catch (error) {
      if (context.mounted) _notify(context, error.message);
    }
  }

  Future<void> _endRecurrence(BuildContext context, Payable payable) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Encerrar recorrência?'),
        content: Text(
          'Encerra em ${formatDateBr(payable.dueDate)}: ocorrências seguintes '
          'sem pagamento são canceladas e não serão geradas novas. Pagamentos, '
          'parciais e débitos vencidos continuam.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Encerrar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<PayablesRepository>().endRecurrence(
        space.id,
        payable.recurrenceId!,
        payable.dueDate,
      );
      if (!context.mounted) return;
      context.read<SessionController>().dataChanged();
      _notify(context, 'Recorrência encerrada.');
    } on ApiException catch (error) {
      if (context.mounted) _notify(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conta a pagar')),
      body: LoadView<(Payable, List<Account>, ReceiptAttempt?)>(
        load: () => _load(context),
        builder: (context, data, refresh) {
          final (payable, accounts, pending) = data;
          final theme = Theme.of(context);
          final names = {for (final a in accounts) a.id: a.name};
          final free = pending == null;
          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SpaceBadge(space),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                payable.description,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            payableStatusChip(payable),
                          ],
                        ),
                        Text(
                          '${payable.kindLabel} · vence ${formatDateBr(payable.dueDate)}'
                          '${payable.payee == null ? '' : '\n${payable.payee}'}',
                        ),
                        if (payable.cancelReason != null)
                          Text('Cancelada: ${payable.cancelReason}'),
                        const Divider(height: 32),
                        _Line(
                          'Valor',
                          payable.amount == null
                              ? const Text('Valor a informar')
                              : MoneyText(payable.amount!),
                        ),
                        _Line('Pago (líquido)', MoneyText(payable.paid)),
                        _Line(
                          'Falta pagar',
                          payable.remaining == null
                              ? const Text('—')
                              : MoneyText(
                                  payable.remaining!,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (pending != null)
                  PendingReceiptCard(
                    key: ValueKey(pending.idempotencyKey),
                    attempt: pending,
                    onSettled: (outcome) => _settled(context, outcome),
                  ),
                if (free && payable.canPay)
                  FilledButton.icon(
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Registrar pagamento'),
                    onPressed: () => _push(
                      context,
                      PaymentFormScreen(
                        space: space,
                        payable: payable,
                        accounts: accounts,
                      ),
                    ),
                  ),
                if (free && !payable.isCancelled) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(
                      payable.isCardBill
                          ? 'Informar total da fatura'
                          : 'Editar esta conta',
                    ),
                    onPressed: () => _push(
                      context,
                      PayableEditScreen(space: space, payable: payable),
                    ),
                  ),
                ],
                if (free && !payable.isCancelled && payable.paid.isZero) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.block),
                    label: const Text('Cancelar conta a pagar'),
                    onPressed: () => _cancel(context, payable),
                  ),
                ],
                if (payable.recurrenceId != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.update),
                    label: const Text('Alterar ocorrências futuras'),
                    onPressed: () => _editFuture(context, payable),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event_busy),
                    label: const Text('Encerrar recorrência aqui'),
                    onPressed: () => _endRecurrence(context, payable),
                  ),
                ],
                const SizedBox(height: 24),
                Text('Pagamentos', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (payable.payments.isEmpty)
                  Text(
                    'Nenhum pagamento registrado.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                for (final payment in payable.payments)
                  _PaymentTile(
                    payment: payment,
                    accountName: names[payment.accountId] ?? 'Conta',
                    onCorrect: free && !payment.isReversed
                        ? () => _push(
                            context,
                            PaymentFixScreen(
                              space: space,
                              payable: payable,
                              original: payment,
                              accounts: accounts,
                              correction: true,
                            ),
                          )
                        : null,
                    onReverse: free && !payment.isReversed
                        ? () => _push(
                            context,
                            PaymentFixScreen(
                              space: space,
                              payable: payable,
                              original: payment,
                              accounts: accounts,
                              correction: false,
                            ),
                          )
                        : null,
                  ),
                if (payable.changes.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('Histórico', style: theme.textTheme.titleMedium),
                  for (final change in payable.changes)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.history),
                      title: Text(change.label),
                      subtitle: change.reason == null
                          ? null
                          : Text('Motivo: ${change.reason}'),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Pede um texto (motivo) ou valor numa caixa de diálogo; nulo se cancelado.
Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String message,
  required String label,
  required String confirm,
  bool money = false,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              prefixText: money ? r'R$ ' : null,
            ),
            keyboardType: money ? TextInputType.number : null,
            inputFormatters: money ? [MoneyInputFormatter()] : null,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(),
          child: const Text('Voltar'),
        ),
        FilledButton(
          onPressed: () {
            final text = controller.text.trim();
            final valid = money
                ? (Money.fromInput(text)?.cents ?? 0) > 0
                : text.length >= 3;
            if (valid) Navigator.of(dialog).pop(text);
          },
          child: Text(confirm),
        ),
      ],
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        value,
      ],
    ),
  );
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({
    required this.payment,
    required this.accountName,
    this.onCorrect,
    this.onReverse,
  });

  final Payment payment;
  final String accountName;
  final VoidCallback? onCorrect;
  final VoidCallback? onReverse;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      key: ValueKey('payment-${payment.id}'),
      child: ListTile(
        leading: Icon(
          payment.isReversed ? Icons.undo : Icons.north_east,
          color: payment.isReversed ? muted : null,
        ),
        title: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            MoneyText(
              payment.amount,
              style: payment.isReversed
                  ? TextStyle(
                      color: muted,
                      decoration: TextDecoration.lineThrough,
                    )
                  : null,
            ),
            if (payment.isReversed)
              StatusChip(
                label: payment.isCorrected ? 'Corrigido' : 'Estornado',
                tone: StatusTone.neutral,
              ),
          ],
        ),
        subtitle: Text(
          [
            '${formatDateBr(payment.paidOn)} · $accountName',
            if (payment.replacesPaymentId != null)
              'Substitui um pagamento corrigido',
            if (payment.reversalReason != null)
              'Motivo: ${payment.reversalReason}',
          ].join('\n'),
        ),
        isThreeLine: payment.isReversed || payment.replacesPaymentId != null,
        trailing: onCorrect == null && onReverse == null
            ? null
            : PopupMenuButton<VoidCallback>(
                tooltip: 'Ações do pagamento',
                onSelected: (action) => action(),
                itemBuilder: (_) => [
                  if (onCorrect != null)
                    PopupMenuItem(
                      value: onCorrect,
                      child: const Text('Corrigir pagamento'),
                    ),
                  if (onReverse != null)
                    PopupMenuItem(
                      value: onReverse,
                      child: const Text('Estornar pagamento'),
                    ),
                ],
              ),
      ),
    );
  }
}
