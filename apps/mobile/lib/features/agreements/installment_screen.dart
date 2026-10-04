import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../accounts/account.dart';
import '../accounts/accounts_repository.dart';
import '../auth/auth_models.dart';
import 'agreement.dart';
import 'agreement_screen.dart';
import 'agreements_repository.dart';
import 'receipt_form_screen.dart';

class InstallmentScreen extends StatelessWidget {
  const InstallmentScreen({
    super.key,
    required this.space,
    required this.installmentId,
  });

  final Space space;
  final int installmentId;

  Future<(Installment, List<Account>)> _load(BuildContext context) async {
    final results = await Future.wait([
      context.read<AgreementsRepository>().installment(space.id, installmentId),
      context.read<AccountsRepository>().list(space.id),
    ]);
    return (results[0] as Installment, results[1] as List<Account>);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parcela')),
      body: LoadView<(Installment, List<Account>)>(
        load: () => _load(context),
        builder: (context, data, refresh) {
          final (installment, accounts) = data;
          final theme = Theme.of(context);
          final accountNames = {
            for (final account in accounts) account.id: account.name,
          };
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
                                'Parcela ${installment.number}/${installment.installmentCount ?? '?'}',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            installmentStatusChip(installment),
                          ],
                        ),
                        if (installment.agreementDescription != null)
                          Text(
                            installment.agreementDescription!,
                            style: theme.textTheme.bodyMedium,
                          ),
                        const SizedBox(height: 4),
                        Text(
                          'Vencimento ${formatDateBr(installment.dueDate)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const Divider(height: 32),
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
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (!installment.remaining.isZero)
                  FilledButton.icon(
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Registrar recebimento'),
                    onPressed: () async {
                      final result = await Navigator.of(context)
                          .push<ReceiptResult>(
                            spaceRoute(
                              isPf: space.isPf,
                              child: ReceiptFormScreen(
                                space: space,
                                installment: installment,
                                accounts: accounts,
                              ),
                            ),
                          );
                      if (result != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${result.replayed ? 'Recebimento já estava registrado' : 'Recebimento confirmado'}. '
                              'Saldo da conta: ${result.accountBalance.brl}.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                const SizedBox(height: 24),
                Text('Recebimentos', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (installment.receipts.isEmpty)
                  Text(
                    'Nenhum recebimento registrado.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  for (final receipt in installment.receipts)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.south_west),
                        title: MoneyText(receipt.amount),
                        subtitle: Text(
                          '${formatDateBr(receipt.receivedOn)} · ${accountNames[receipt.accountId] ?? 'Conta'}',
                        ),
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
      children: [
        Expanded(child: Text(label)),
        child,
      ],
    ),
  );
}
