import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../ui/app_brand.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import 'summary.dart';

class SummaryTab extends StatelessWidget {
  const SummaryTab({super.key, required this.space, required this.onOpenTab});

  final Space space;
  final void Function(int tab, {String? filter}) onOpenTab;

  @override
  Widget build(BuildContext context) {
    return LoadView<SpaceSummary>(
      load: () => context.read<SummaryRepository>().load(space.id),
      builder: (context, summary, refresh) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.p16,
              vertical: AppTokens.p20,
            ),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    space.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.6,
                      ),
                      borderRadius: BorderRadius.circular(AppTokens.r8),
                    ),
                    child: Text(
                      'Espaço ${space.kind}',
                      style: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Cartão principal de Saldo Disponível com destaque visual elegante e marca d'água
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: AppTokens.cardGradientFor(isPf: space.isPf),
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppTokens.r20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          (space.isPf
                                  ? const Color(0xFF1E40AF)
                                  : const Color(0xFF065F46))
                              .withValues(alpha: isDark ? 0.35 : 0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.r20),
                  child: Stack(
                    children: [
                      // Luz decorativa no canto superior esquerdo para consistência com o AccountCard
                      Positioned(
                        top: -40,
                        left: -40,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                      const BrandWatermark(
                        size: 150,
                        opacity: 0.07,
                        color: Colors.white,
                      ),
                      Padding(
                        padding: const EdgeInsets.all(AppTokens.p20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Saldo disponível',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(
                                      AppTokens.r12,
                                    ),
                                  ),
                                  child: const AppIcon(
                                    AppIcons.wallet,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            MoneyText(
                              summary.balance,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Área de rodapé com altura e estrutura consistentes entre PF e PJ
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minHeight: 32,
                                    ),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        summary.archivedAccountsCount == 0
                                            ? '${summary.accountsCount} ${summary.accountsCount == 1 ? 'conta' : 'contas'} · somente valores efetivados'
                                            : '${summary.accountsCount} contas (${summary.archivedAccountsCount} arquivada${summary.archivedAccountsCount == 1 ? '' : 's'}, incluída${summary.archivedAccountsCount == 1 ? '' : 's'} no saldo) · somente valores efetivados',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 2),
                                  child: CardBrandSignature(
                                    color: Colors.white60,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Métricas de A Receber
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      label: 'A receber (previsto)',
                      value: summary.receivableRemaining,
                      icon: AppIcons.clock,
                      color: AppTokens.brandPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricCard(
                      label: 'Já recebido',
                      value: summary.receivedTotal,
                      icon: AppIcons.check,
                      color: AppTokens.income,
                    ),
                  ),
                ],
              ),
              if (summary.overdueInstallments > 0) ...[
                const SizedBox(height: 12),
                Material(
                  color: isDark
                      ? const Color(0xFF3B1818)
                      : const Color(0xFFFEF2F2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTokens.r12),
                    side: BorderSide(
                      color: isDark
                          ? const Color(0xFF7F1D1D)
                          : const Color(0xFFFECACA),
                      width: 1,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppTokens.r12),
                    onTap: () => onOpenTab(1, filter: 'overdue'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          const AppIcon(
                            AppIcons.alert,
                            color: AppTokens.expense,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${summary.overdueInstallments} ${summary.overdueInstallments == 1 ? 'parcela vencida' : 'parcelas vencidas'} a receber',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppTokens.expense,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const AppIcon(
                            AppIcons.forward,
                            size: 16,
                            color: AppTokens.expense,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // Cartão de A Pagar com previsto × realizado
              _PayablesCard(
                payables: summary.payables,
                onTap: () => onOpenTab(2),
              ),
              const SizedBox(height: 20),
              // Atalho de onboarding ou resumo
              if (summary.accountsCount == 0)
                _ShortcutCard(
                  icon: AppIcons.accounts,
                  title: 'Cadastre a primeira conta',
                  subtitle: 'Informe o saldo inicial e a data de referência.',
                  onTap: () => onOpenTab(3),
                )
              else
                _ShortcutCard(
                  icon: AppIcons.receivables,
                  title: summary.agreementsCount == 0
                      ? 'Cadastre uma conta a receber'
                      : 'Contas a receber',
                  subtitle: summary.agreementsCount == 0
                      ? 'Venda parcelada, empréstimo a terceiros…'
                      : '${summary.agreementsCount} ${summary.agreementsCount == 1 ? 'cadastrada' : 'cadastradas'}',
                  onTap: () => onOpenTab(1),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final Money value;
  final List<List<dynamic>> icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.p16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTokens.r8),
              ),
              child: AppIcon(icon, size: 18, color: color),
            ),
            const SizedBox(height: 10),
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
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final List<List<dynamic>> icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppTokens.r12),
        ),
        child: AppIcon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: const AppIcon(AppIcons.forward, size: 18),
      onTap: onTap,
    ),
  );
}

/// A pagar no resumo: previsto (em aberto, vencido, próximos 30 dias) separado
/// do realizado (pago líquido). Não reduz o saldo bancário.
class _PayablesCard extends StatelessWidget {
  const _PayablesCard({required this.payables, required this.onTap});

  final PayablesSummary payables;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget line(String label, Money value, {bool alert = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: alert
                  ? AppTokens.expense
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: alert ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          MoneyText(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: alert ? AppTokens.expense : null,
            ),
          ),
        ],
      ),
    );

    return Card(
      key: const ValueKey('summary-payables'),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.r16),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.p16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTokens.expense.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppTokens.r8),
                        ),
                        child: const AppIcon(
                          AppIcons.payables,
                          size: 16,
                          color: AppTokens.expense,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'A pagar (previsto)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const AppIcon(AppIcons.forward, size: 16),
                ],
              ),
              const SizedBox(height: 12),
              line('Em aberto', payables.openTotal),
              line(
                'Vencido (${payables.overdueCount})',
                payables.overdueTotal,
                alert: payables.overdueCount > 0,
              ),
              line('Próximos 30 dias', payables.dueNext30DaysTotal),
              const Divider(height: 20),
              line('Pago (líquido, realizado)', payables.paidTotal),
              if (payables.awaitingAmountCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${payables.awaitingAmountCount} '
                    '${payables.awaitingAmountCount == 1 ? 'fatura' : 'faturas'} '
                    'com valor a informar (fora dos totais)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTokens.warning,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'Obrigações não reduzem o saldo; só pagamentos.',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
