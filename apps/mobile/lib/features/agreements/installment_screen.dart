import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../accounts/account.dart';
import '../accounts/accounts_repository.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import 'agreement.dart';
import 'agreement_screen.dart';
import 'agreements_repository.dart';
import 'pending_receipt_card.dart';
import 'receipt_attempts.dart';
import 'receipt_fix_screen.dart';
import 'receipt_form_screen.dart';
import 'receipt_tile.dart';

class InstallmentScreen extends StatelessWidget {
  const InstallmentScreen({
    super.key,
    required this.space,
    required this.installmentId,
  });

  final Space space;
  final int installmentId;

  Future<(Installment, List<Account>, ReceiptAttempt?)> _load(
    BuildContext context,
  ) async {
    final userId = context.read<SessionController>().user?.id;
    final attempts = context.read<ReceiptAttempts>();
    final results = await Future.wait([
      context.read<AgreementsRepository>().installment(space.id, installmentId),
      context.read<AccountsRepository>().list(space.id),
      if (userId != null)
        attempts.pending(userId, space.id, installmentId)
      else
        Future.value(),
    ]);
    return (
      results[0] as Installment,
      results[1] as List<Account>,
      results[2] as ReceiptAttempt?,
    );
  }

  Future<void> _openFix(
    BuildContext context,
    Installment installment,
    Receipt receipt,
    List<Account> accounts, {
    required bool correction,
  }) async {
    final outcome = await Navigator.of(context).push<ReceiptAttemptOutcome>(
      spaceRoute(
        isPf: space.isPf,
        child: ReceiptFixScreen(
          space: space,
          installment: installment,
          original: receipt,
          accounts: accounts,
          correction: correction,
        ),
      ),
    );
    if (outcome != null && context.mounted) _settled(context, outcome);
  }

  /// Resultado confirmado ou recusado: avisa e recarrega pela API.
  void _settled(BuildContext context, ReceiptAttemptOutcome outcome) {
    final result = outcome.result;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == null
              ? outcome.message
              : '${outcome.message} Saldo da conta: ${result.accountBalance.brl}.',
        ),
      ),
    );
    context.read<SessionController>().dataChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parcela')),
      body: LoadView<(Installment, List<Account>, ReceiptAttempt?)>(
        load: () => _load(context),
        builder: (context, data, refresh) {
          final (installment, accounts, pending) = data;
          final theme = Theme.of(context);
          final accountNames = {
            for (final account in accounts) account.id: account.name,
          };
          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              padding: const EdgeInsets.all(AppTokens.p16),
              children: [
                SpaceBadge(space),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.p20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Parcela ${installment.number}/${installment.installmentCount ?? '?'}',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            installmentStatusChip(installment),
                          ],
                        ),
                        if (installment.agreementDescription != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            installment.agreementDescription!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          'Vencimento ${formatDateBr(installment.dueDate)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const Divider(height: 28),
                        _Row(
                          label: 'Valor da parcela',
                          child: MoneyText(installment.amount),
                        ),
                        _Row(
                          label: 'Recebido',
                          child: MoneyText(installment.received),
                        ),
                        _Row(
                          label: 'Falta receber',
                          child: MoneyText(
                            installment.remaining,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: installment.remaining.isZero
                                  ? AppTokens.income
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Tentativa sem confirmação bloqueia novo recebimento nesta
                // parcela até ser verificada.
                if (pending != null)
                  PendingReceiptCard(
                    key: ValueKey(pending.idempotencyKey),
                    attempt: pending,
                    onSettled: (outcome) => _settled(context, outcome),
                  )
                else if (!installment.remaining.isZero)
                  FilledButton.icon(
                    icon: const AppIcon(AppIcons.receipt, size: 18),
                    label: const Text('Registrar recebimento'),
                    onPressed: () async {
                      final outcome = await Navigator.of(context)
                          .push<ReceiptAttemptOutcome>(
                            spaceRoute(
                              isPf: space.isPf,
                              child: ReceiptFormScreen(
                                space: space,
                                installment: installment,
                                accounts: accounts,
                              ),
                            ),
                          );
                      if (outcome != null && context.mounted) {
                        _settled(context, outcome);
                      }
                    },
                  ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const AppIcon(AppIcons.receipt, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Recebimentos',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (installment.receipts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Nenhum recebimento registrado.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  for (final receipt in installment.receipts)
                    ReceiptTile(
                      receipt: receipt,
                      accountName: accountNames[receipt.accountId] ?? 'Conta',
                      // Operação pendente na parcela bloqueia estorno e
                      // correção até ser verificada.
                      onCorrect: pending != null || receipt.isReversed
                          ? null
                          : () => _openFix(
                              context,
                              installment,
                              receipt,
                              accounts,
                              correction: true,
                            ),
                      onReverse: pending != null || receipt.isReversed
                          ? null
                          : () => _openFix(
                              context,
                              installment,
                              receipt,
                              accounts,
                              correction: false,
                            ),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        child,
      ],
    ),
  );
}
