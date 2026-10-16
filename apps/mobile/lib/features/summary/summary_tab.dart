import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../ui/app_brand.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import '../settings/preferences_controller.dart';
import 'summary.dart';

class SummaryTab extends StatefulWidget {
  const SummaryTab({super.key, required this.space, required this.onOpenTab});

  final Space space;
  final void Function(int tab, {String? filter}) onOpenTab;

  @override
  State<SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends State<SummaryTab> {
  bool _localObscureBalance = false;

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<PreferencesController?>();
    final obscureBalance = preferences?.obscureValues ?? _localObscureBalance;

    return LoadView<SpaceSummary>(
      load: () => context.read<SummaryRepository>().load(widget.space.id),
      builder: (context, summary, refresh) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final space = widget.space;

        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.p16,
              vertical: AppTokens.p16,
            ),
            children: [
              // Cabeçalho acolhedor com saudação, contexto de espaço e chip semântico
              _DashboardHeader(
                space: space,
                accountsCount: summary.accountsCount,
              ),
              const SizedBox(height: 14),

              // Cartão Master de Saldo Disponível (Hero Fintech Card)
              _BalanceHeroCard(
                space: space,
                summary: summary,
                obscureBalance: obscureBalance,
                isDark: isDark,
                onToggleVisibility: () {
                  if (preferences != null) {
                    preferences.togglePrivacy();
                  } else {
                    setState(() {
                      _localObscureBalance = !_localObscureBalance;
                    });
                  }
                },
              ),
              const SizedBox(height: 18),

              // Grid de Ações Rápidas (Navegação contextual direta para funcionalidades existentes)
              _QuickActionsSection(space: space, onOpenTab: widget.onOpenTab),
              const SizedBox(height: 18),

              // Métricas em Destaque: A Receber (Previsto vs Realizado)
              Text(
                'Recebimentos',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppTokens.darkTextPrimary
                      : AppTokens.lightTextPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _FintechMetricCard(
                      label: 'A receber (previsto)',
                      value: summary.receivableRemaining,
                      obscure: obscureBalance,
                      icon: AppIcons.clock,
                      accentColor: space.isPf
                          ? AppTokens.brandPrimary
                          : AppTokens.pjSeed,
                      onTap: () => widget.onOpenTab(1, filter: 'open'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FintechMetricCard(
                      label: 'Já recebido',
                      value: summary.receivedTotal,
                      obscure: obscureBalance,
                      icon: AppIcons.check,
                      accentColor: AppTokens.income,
                      onTap: () => widget.onOpenTab(1, filter: 'all'),
                    ),
                  ),
                ],
              ),

              // Alerta contextual caso existam parcelas vencidas a receber
              if (summary.overdueInstallments > 0) ...[
                const SizedBox(height: 12),
                _OverdueAlertBanner(
                  count: summary.overdueInstallments,
                  isDark: isDark,
                  onTap: () => widget.onOpenTab(1, filter: 'overdue'),
                ),
              ],
              const SizedBox(height: 20),

              // Seção de Obrigações Financeiras: A Pagar (Previsto vs Realizado)
              Text(
                'Compromissos a Pagar',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppTokens.darkTextPrimary
                      : AppTokens.lightTextPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 10),
              _ModernPayablesCard(
                payables: summary.payables,
                obscure: obscureBalance,
                isDark: isDark,
                onTap: () => widget.onOpenTab(2),
              ),
              const SizedBox(height: 20),

              // Card de Acesso à Carteira de Contas
              _AccountsAccessCard(
                accountsCount: summary.accountsCount,
                archivedCount: summary.archivedAccountsCount,
                isDark: isDark,
                space: space,
                onTap: () => widget.onOpenTab(3),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

/// Cabeçalho moderno com saudação, identificação do espaço e estilo fintech
class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.space, required this.accountsCount});

  final Space space;
  final int accountsCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Visão Geral Financeira',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                space.label,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
        ),
        // Badge elegante indicando PF / PJ com cor de acento
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color:
                (space.isPf ? const Color(0xFF2459D4) : const Color(0xFF137A63))
                    .withValues(alpha: isDark ? 0.25 : 0.12),
            borderRadius: BorderRadius.circular(AppTokens.r10),
            border: Border.all(
              color:
                  (space.isPf
                          ? const Color(0xFF2459D4)
                          : const Color(0xFF137A63))
                      .withValues(alpha: isDark ? 0.4 : 0.25),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                space.isPf ? AppIcons.user : AppIcons.business,
                size: 14,
                color: space.isPf
                    ? (isDark
                          ? const Color(0xFF93C5FD)
                          : const Color(0xFF1D4ED8))
                    : (isDark
                          ? const Color(0xFF6EE7B7)
                          : const Color(0xFF047857)),
              ),
              const SizedBox(width: 6),
              Text(
                space.kind,
                semanticsLabel: 'Espaço ${space.label}',
                style: TextStyle(
                  color: space.isPf
                      ? (isDark
                            ? const Color(0xFF93C5FD)
                            : const Color(0xFF1D4ED8))
                      : (isDark
                            ? const Color(0xFF6EE7B7)
                            : const Color(0xFF047857)),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Cartão de Saldo Disponível Principal com acabamento nobre, botão de ocultar e marca d'água
class _BalanceHeroCard extends StatelessWidget {
  const _BalanceHeroCard({
    required this.space,
    required this.summary,
    required this.obscureBalance,
    required this.isDark,
    required this.onToggleVisibility,
  });

  final Space space;
  final SpaceSummary summary;
  final bool obscureBalance;
  final bool isDark;
  final VoidCallback onToggleVisibility;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPf = space.isPf;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppTokens.cardGradientFor(isPf: isPf),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTokens.r24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isPf ? const Color(0xFF1E40AF) : const Color(0xFF065F46))
                .withValues(alpha: isDark ? 0.45 : 0.28),
            blurRadius: 22,
            offset: const Offset(0, 8),
            spreadRadius: -2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.r24),
        child: Stack(
          children: [
            // Círculo de luz decorativo superior esquerdo
            Positioned(
              top: -50,
              left: -50,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            // Marca-d'água oficial do gorila
            const BrandWatermark(size: 160, opacity: 0.07, color: Colors.white),
            Padding(
              padding: const EdgeInsets.all(AppTokens.p20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(
                                  AppTokens.r8,
                                ),
                              ),
                              child: const AppIcon(
                                AppIcons.wallet,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Flexible(
                              child: Text(
                                'Saldo disponível',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Botão de privacidade para ocultar/exibir saldo
                      Semantics(
                        button: true,
                        label: obscureBalance
                            ? 'Mostrar saldo'
                            : 'Ocultar saldo',
                        child: IconButton(
                          onPressed: onToggleVisibility,
                          tooltip: obscureBalance
                              ? 'Mostrar saldo'
                              : 'Ocultar saldo',
                          icon: AppIcon(
                            obscureBalance ? AppIcons.view : AppIcons.viewOff,
                            color: Colors.white70,
                            size: 18,
                          ),
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.1,
                            ),
                            padding: const EdgeInsets.all(6),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Exibição do Saldo (ou máscara de privacidade)
                  if (obscureBalance)
                    Text(
                      'R\$ ••••••••',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    )
                  else
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: MoneyText(
                        summary.balance,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.6,
                          fontSize: 30,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),

                  // Linha divisória suave interna
                  Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  const SizedBox(height: 10),

                  // Rodapé do Card com resumo de contas e assinatura da marca
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          summary.archivedAccountsCount == 0
                              ? '${summary.accountsCount} ${summary.accountsCount == 1 ? 'conta ativa' : 'contas ativas'} · efetivado'
                              : '${summary.accountsCount} contas (${summary.archivedAccountsCount} arquivada${summary.archivedAccountsCount == 1 ? '' : 's'}) · efetivado',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const CardBrandSignature(color: Colors.white60),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Seção de Ações Rápidas: navegação direta para os fluxos reais existentes no app
class _QuickActionsSection extends StatelessWidget {
  const _QuickActionsSection({required this.space, required this.onOpenTab});

  final Space space;
  final void Function(int tab, {String? filter}) onOpenTab;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Expanded(
          child: _QuickActionButton(
            icon: AppIcons.receivables,
            label: 'A receber',
            color: space.isPf ? AppTokens.brandPrimary : AppTokens.pjSeed,
            isDark: isDark,
            onTap: () => onOpenTab(1),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionButton(
            icon: AppIcons.payables,
            label: 'A pagar',
            color: AppTokens.expense,
            isDark: isDark,
            onTap: () => onOpenTab(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionButton(
            icon: AppIcons.accounts,
            label: 'Contas',
            color: const Color(0xFF0EA5E9),
            isDark: isDark,
            onTap: () => onOpenTab(3),
          ),
        ),
      ],
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  final List<List<dynamic>> icon;
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.r16),
        side: BorderSide(
          color: isDark ? AppTokens.darkBorder : AppTokens.lightBorder,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.r16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.2 : 0.1),
                  shape: BoxShape.circle,
                ),
                child: AppIcon(icon, size: 20, color: color),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card de Métrica Fintech (Recebimentos e previsões)
class _FintechMetricCard extends StatelessWidget {
  const _FintechMetricCard({
    required this.label,
    required this.value,
    required this.obscure,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final Money value;
  final bool obscure;
  final List<List<dynamic>> icon;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.r16),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.p14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(
                        alpha: isDark ? 0.22 : 0.12,
                      ),
                      borderRadius: BorderRadius.circular(AppTokens.r8),
                    ),
                    child: AppIcon(icon, size: 16, color: accentColor),
                  ),
                  AppIcon(
                    AppIcons.forward,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.6,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              if (obscure)
                Text(
                  'R\$ ••••',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: MoneyText(
                    value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
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

/// Banner de Alerta para parcelas vencidas
class _OverdueAlertBanner extends StatelessWidget {
  const _OverdueAlertBanner({
    required this.count,
    required this.isDark,
    required this.onTap,
  });

  final int count;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? const Color(0xFF3B1818) : const Color(0xFFFEF2F2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.r12),
        side: BorderSide(
          color: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.r12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const AppIcon(AppIcons.alert, color: AppTokens.expense, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$count ${count == 1 ? 'parcela vencida' : 'parcelas vencidas'} a receber',
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
    );
  }
}

/// Cartão moderno de A Pagar com distinção de Previsto vs Realizado
class _ModernPayablesCard extends StatelessWidget {
  const _ModernPayablesCard({
    required this.payables,
    required this.obscure,
    required this.isDark,
    required this.onTap,
  });

  final PayablesSummary payables;
  final bool obscure;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget payableRow(String label, Money value, {bool alert = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: alert
                        ? AppTokens.expense
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: alert ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (obscure)
                Text(
                  'R\$ ••••',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: alert ? AppTokens.expense : null,
                  ),
                )
              else
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: MoneyText(
                      value,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: alert ? AppTokens.expense : null,
                      ),
                    ),
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
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTokens.expense.withValues(
                              alpha: isDark ? 0.22 : 0.12,
                            ),
                            borderRadius: BorderRadius.circular(AppTokens.r8),
                          ),
                          child: const AppIcon(
                            AppIcons.payables,
                            size: 16,
                            color: AppTokens.expense,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Obrigações e Faturas',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const AppIcon(AppIcons.forward, size: 16),
                ],
              ),
              const SizedBox(height: 12),
              payableRow('Em aberto', payables.openTotal),
              payableRow(
                'Vencido (${payables.overdueCount})',
                payables.overdueTotal,
                alert: payables.overdueCount > 0,
              ),
              payableRow('Próximos 30 dias', payables.dueNext30DaysTotal),
              const Divider(height: 18),
              payableRow('Pago (líquido, realizado)', payables.paidTotal),
              if (payables.awaitingAmountCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${payables.awaitingAmountCount} '
                    '${payables.awaitingAmountCount == 1 ? 'fatura' : 'faturas'} '
                    'com valor a informar (fora dos totais)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTokens.warning,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                'Obrigações não alteram saldo bancário; somente pagamentos efetivados.',
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

/// Card de Atalho para a Carteira de Contas
class _AccountsAccessCard extends StatelessWidget {
  const _AccountsAccessCard({
    required this.accountsCount,
    required this.archivedCount,
    required this.isDark,
    required this.space,
    required this.onTap,
  });

  final int accountsCount;
  final int archivedCount;
  final bool isDark;
  final Space space;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(
              alpha: isDark ? 0.3 : 0.6,
            ),
            borderRadius: BorderRadius.circular(AppTokens.r12),
          ),
          child: AppIcon(
            AppIcons.accounts,
            size: 20,
            color: theme.colorScheme.primary,
          ),
        ),
        title: Text(
          accountsCount == 0
              ? 'Cadastre a primeira conta'
              : 'Carteira de Contas',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        subtitle: Text(
          accountsCount == 0
              ? 'Informe o saldo inicial e a data de referência.'
              : '$accountsCount ${accountsCount == 1 ? 'conta cadastrada' : 'contas cadastradas'}'
                    '${archivedCount > 0 ? ' ($archivedCount arquivada${archivedCount == 1 ? '' : 's'})' : ''}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: const AppIcon(AppIcons.forward, size: 18),
        onTap: onTap,
      ),
    );
  }
}
