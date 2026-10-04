import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import 'summary.dart';

class SummaryTab extends StatelessWidget {
  const SummaryTab({super.key, required this.space, required this.onOpenTab});

  final Space space;
  final void Function(int tab) onOpenTab;

  @override
  Widget build(BuildContext context) {
    return LoadView<SpaceSummary>(
      load: () => context.read<SummaryRepository>().load(space.id),
      builder: (context, summary, refresh) {
        final theme = Theme.of(context);
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                space.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                color: theme.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Saldo disponível',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 8),
                      MoneyText(
                        summary.balance,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${summary.accountsCount} ${summary.accountsCount == 1 ? 'conta' : 'contas'} · somente valores efetivados',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                      label: 'A receber (previsto)',
                      value: summary.receivableRemaining,
                      icon: Icons.schedule,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Metric(
                      label: 'Já recebido',
                      value: summary.receivedTotal,
                      icon: Icons.check_circle_outline,
                    ),
                  ),
                ],
              ),
              if (summary.overdueInstallments > 0) ...[
                const SizedBox(height: 12),
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: ListTile(
                    leading: Icon(
                      Icons.warning_amber_rounded,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    title: Text(
                      '${summary.overdueInstallments} ${summary.overdueInstallments == 1 ? 'parcela vencida' : 'parcelas vencidas'}',
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    onTap: () => onOpenTab(1),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (summary.accountsCount == 0)
                _Shortcut(
                  icon: Icons.account_balance_outlined,
                  title: 'Cadastre a primeira conta',
                  subtitle: 'Informe o saldo inicial e a data de referência.',
                  onTap: () => onOpenTab(2),
                )
              else
                _Shortcut(
                  icon: Icons.handshake_outlined,
                  title: summary.agreementsCount == 0
                      ? 'Cadastre um acordo a receber'
                      : 'Acordos a receber',
                  subtitle: summary.agreementsCount == 0
                      ? 'Venda parcelada, empréstimo a terceiros…'
                      : '${summary.agreementsCount} cadastrados',
                  onTap: () => onOpenTab(1),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon});

  final String label;
  final Money value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            MoneyText(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}
