import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../accounts/account.dart';
import '../accounts/bank_catalog.dart';
import '../categories/category.dart';
import 'summary.dart';

/// Painel executivo de gráficos e inteligência visual financeira do BigDev.Z Finance.
/// Apresenta o Donut de Distribuição por Bancos e o Termômetro Comparativo de Fluxo de Caixa.
class ExecutiveDashboardCharts extends StatelessWidget {
  const ExecutiveDashboardCharts({
    super.key,
    required this.summary,
    required this.accounts,
    required this.obscure,
    this.onOpenAccounts,
    this.onOpenReceivables,
    this.onOpenPayables,
  });

  final SpaceSummary summary;
  final List<Account> accounts;
  final bool obscure;
  final VoidCallback? onOpenAccounts;
  final VoidCallback? onOpenReceivables;
  final VoidCallback? onOpenPayables;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWidescreen = constraints.maxWidth >= 760;

        final bankCard = BankDistributionDonutCard(
          accounts: accounts,
          obscure: obscure,
          onTapDetails: onOpenAccounts,
        );

        final cashFlowCard = CashFlowThermometerCard(
          summary: summary,
          obscure: obscure,
          onTapReceivables: onOpenReceivables,
          onTapPayables: onOpenPayables,
        );

        final categoryCard = CategoryDistributionDonutCard(
          categories: summary.categories,
          obscure: obscure,
        );

        if (isWidescreen) {
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: bankCard),
                  const SizedBox(width: AppTokens.p16),
                  Expanded(child: cashFlowCard),
                ],
              ),
              const SizedBox(height: AppTokens.p16),
              categoryCard,
            ],
          );
        }

        return Column(
          children: [
            bankCard,
            const SizedBox(height: AppTokens.p16),
            cashFlowCard,
            const SizedBox(height: AppTokens.p16),
            categoryCard,
          ],
        );
      },
    );
  }
}

/// Card de gráfico Donut exibindo a distribuição patrimonial por banco/instituição.
class BankDistributionDonutCard extends StatelessWidget {
  const BankDistributionDonutCard({
    super.key,
    required this.accounts,
    required this.obscure,
    this.onTapDetails,
  });

  final List<Account> accounts;
  final bool obscure;
  final VoidCallback? onTapDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final positiveAccounts = accounts
        .where((a) => a.balance.cents > 0)
        .toList();
    final int totalPositiveCents = positiveAccounts.fold(
      0,
      (sum, a) => sum + a.balance.cents,
    );

    return Container(
      padding: const EdgeInsets.all(AppTokens.p16),
      decoration: BoxDecoration(
        color: isDark ? AppTokens.darkSurface : AppTokens.lightSurface,
        borderRadius: BorderRadius.circular(AppTokens.r16),
        border: Border.all(
          color: isDark ? AppTokens.darkBorder : AppTokens.lightBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTokens.brandPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.r8),
                ),
                alignment: Alignment.center,
                child: AppIcon(
                  AppIcons.wallet,
                  size: 18,
                  color: AppTokens.brandPrimary,
                ),
              ),
              const SizedBox(width: AppTokens.p8),
              Expanded(
                child: Text(
                  'Distribuição por Bancos',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppTokens.darkTextPrimary
                        : AppTokens.lightTextPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onTapDetails != null)
                TextButton(
                  onPressed: onTapDetails,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.p8,
                    ),
                    minimumSize: const Size(60, 32),
                  ),
                  child: const Text(
                    'Ver contas',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppTokens.p16),
          if (positiveAccounts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTokens.p20),
              child: Center(
                child: Text(
                  'Nenhuma conta com saldo positivo.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppTokens.darkTextSecondary
                        : AppTokens.lightTextSecondary,
                  ),
                ),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CustomPaint(
                    painter: _DonutChartPainter(
                      accounts: positiveAccounts,
                      totalCents: totalPositiveCents,
                      backgroundColor: isDark
                          ? AppTokens.darkBorder
                          : AppTokens.lightBorder,
                    ),
                    child: Center(
                      child: Text(
                        '${positiveAccounts.length}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? AppTokens.darkTextPrimary
                              : AppTokens.lightTextPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppTokens.p12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: positiveAccounts.map((account) {
                      final bank = BankCatalog.findByAccountName(account.name);
                      final color = bank?.color ?? AppTokens.brandPrimary;
                      final percent = totalPositiveCents > 0
                          ? (account.balance.cents * 100 / totalPositiveCents)
                                .round()
                          : 0;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: AppTokens.p8),
                            Expanded(
                              child: Text(
                                account.name,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppTokens.darkTextPrimary
                                      : AppTokens.lightTextPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: AppTokens.p8),
                            Text(
                              '$percent%',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? AppTokens.darkTextSecondary
                                    : AppTokens.lightTextSecondary,
                              ),
                            ),
                            const SizedBox(width: AppTokens.p8),
                            Text(
                              obscure ? '••••' : account.balance.brl,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppTokens.darkTextPrimary
                                    : AppTokens.lightTextPrimary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// CustomPainter para o gráfico de Donut de alta precisão.
class _DonutChartPainter extends CustomPainter {
  _DonutChartPainter({
    required this.accounts,
    required this.totalCents,
    required this.backgroundColor,
  });

  final List<Account> accounts;
  final int totalCents;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 14) / 2;
    const strokeWidth = 10.0;

    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, bgPaint);

    if (totalCents <= 0 || accounts.isEmpty) return;

    double startAngle = -math.pi / 2;

    for (final account in accounts) {
      final sweepAngle = (account.balance.cents / totalCents) * 2 * math.pi;
      final bank = BankCatalog.findByAccountName(account.name);
      final color = bank?.color ?? AppTokens.brandPrimary;

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      final adjustedSweep = accounts.length > 1
          ? math.max(0.01, sweepAngle - 0.06)
          : sweepAngle;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle + (accounts.length > 1 ? 0.03 : 0),
        adjustedSweep,
        false,
        paint,
      );

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.totalCents != totalCents ||
        oldDelegate.accounts.length != accounts.length;
  }
}

/// Card de Termômetro de Fluxo de Caixa (Entradas vs Saídas & Margem Projetada).
class CashFlowThermometerCard extends StatelessWidget {
  const CashFlowThermometerCard({
    super.key,
    required this.summary,
    required this.obscure,
    this.onTapReceivables,
    this.onTapPayables,
  });

  final SpaceSummary summary;
  final bool obscure;
  final VoidCallback? onTapReceivables;
  final VoidCallback? onTapPayables;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final totalInflowCents =
        summary.receivedTotal.cents + summary.receivableRemaining.cents;
    final totalOutflowCents =
        summary.payables.paidTotal.cents +
        summary.payables.openTotal.cents +
        summary.payables.overdueTotal.cents;

    final netMarginCents = totalInflowCents - totalOutflowCents;
    final isSurplus = netMarginCents >= 0;

    final maxVolume = math.max(
      1,
      math.max(totalInflowCents, totalOutflowCents),
    );
    final inflowFactor = totalInflowCents / maxVolume;
    final outflowFactor = totalOutflowCents / maxVolume;

    return Container(
      padding: const EdgeInsets.all(AppTokens.p16),
      decoration: BoxDecoration(
        color: isDark ? AppTokens.darkSurface : AppTokens.lightSurface,
        borderRadius: BorderRadius.circular(AppTokens.r16),
        border: Border.all(
          color: isDark ? AppTokens.darkBorder : AppTokens.lightBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTokens.income.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.r8),
                ),
                alignment: Alignment.center,
                child: AppIcon(
                  AppIcons.receipt,
                  size: 18,
                  color: AppTokens.income,
                ),
              ),
              const SizedBox(width: AppTokens.p8),
              Expanded(
                child: Text(
                  'Fluxo de Caixa',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppTokens.darkTextPrimary
                        : AppTokens.lightTextPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.p16),

          // Barra 1: Entradas (Recebidos + A Receber)
          InkWell(
            onTap: onTapReceivables,
            borderRadius: BorderRadius.circular(AppTokens.r8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppTokens.income,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppTokens.p4),
                      Expanded(
                        child: Text(
                          'Entradas',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppTokens.darkTextPrimary
                                : AppTokens.lightTextPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppTokens.p8),
                      Text(
                        obscure ? '••••' : Money(totalInflowCents).brl,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTokens.income,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.p4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4.0),
                    child: SizedBox(
                      height: 8,
                      child: LinearProgressIndicator(
                        value: inflowFactor.clamp(0.0, 1.0),
                        backgroundColor: isDark
                            ? AppTokens.darkBorder
                            : AppTokens.lightBorder,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppTokens.income,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTokens.p12),

          // Barra 2: Saídas & Compromissos (Pago + Aberto + Vencido)
          InkWell(
            onTap: onTapPayables,
            borderRadius: BorderRadius.circular(AppTokens.r8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppTokens.expense,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppTokens.p4),
                      Expanded(
                        child: Text(
                          'Saídas & Compromissos',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppTokens.darkTextPrimary
                                : AppTokens.lightTextPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppTokens.p8),
                      Text(
                        obscure ? '••••' : Money(totalOutflowCents).brl,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTokens.expense,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.p4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4.0),
                    child: SizedBox(
                      height: 8,
                      child: LinearProgressIndicator(
                        value: outflowFactor.clamp(0.0, 1.0),
                        backgroundColor: isDark
                            ? AppTokens.darkBorder
                            : AppTokens.lightBorder,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppTokens.expense,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTokens.p14),

          // Badge de Saldo Projetado Líquido (Superávit / Déficit)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.p12,
              vertical: AppTokens.p8,
            ),
            decoration: BoxDecoration(
              color: isSurplus
                  ? AppTokens.income.withValues(alpha: isDark ? 0.15 : 0.08)
                  : AppTokens.expense.withValues(alpha: isDark ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(AppTokens.r8),
              border: Border.all(
                color: isSurplus
                    ? AppTokens.income.withValues(alpha: 0.3)
                    : AppTokens.expense.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(
                  isSurplus ? AppIcons.check : AppIcons.alert,
                  size: 16,
                  color: isSurplus ? AppTokens.income : AppTokens.expense,
                ),
                const SizedBox(width: AppTokens.p8),
                Expanded(
                  child: Text(
                    isSurplus
                        ? 'Previsão de sobra: ${obscure ? '••••' : Money(netMarginCents).brl}'
                        : 'Atenção: vai faltar ${obscure ? '••••' : Money(-netMarginCents).brl}',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isSurplus ? AppTokens.income : AppTokens.expense,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Card de gráfico Donut exibindo a distribuição por categoria (Despesas e Receitas).
class CategoryDistributionDonutCard extends StatefulWidget {
  const CategoryDistributionDonutCard({
    super.key,
    required this.categories,
    required this.obscure,
  });

  final CategoriesSummary categories;
  final bool obscure;

  @override
  State<CategoryDistributionDonutCard> createState() =>
      _CategoryDistributionDonutCardState();
}

class _CategoryDistributionDonutCardState
    extends State<CategoryDistributionDonutCard> {
  bool _showExpenses = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final items = _showExpenses
        ? widget.categories.expenses
        : widget.categories.incomes;
    final int totalCents = items.fold(0, (sum, it) => sum + it.totalCents);

    return Container(
      padding: const EdgeInsets.all(AppTokens.p16),
      decoration: BoxDecoration(
        color: isDark ? AppTokens.darkSurface : AppTokens.lightSurface,
        borderRadius: BorderRadius.circular(AppTokens.r16),
        border: Border.all(
          color: isDark ? AppTokens.darkBorder : AppTokens.lightBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTokens.brandPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.r8),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.pie_chart_rounded,
                  size: 18,
                  color: AppTokens.brandPrimary,
                ),
              ),
              const SizedBox(width: AppTokens.p8),
              Expanded(
                child: Text(
                  'Distribuição por Categoria',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppTokens.darkTextPrimary
                        : AppTokens.lightTextPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Despesas', style: TextStyle(fontSize: 11)),
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Receitas', style: TextStyle(fontSize: 11)),
                  ),
                ],
                selected: {_showExpenses},
                onSelectionChanged: (set) =>
                    setState(() => _showExpenses = set.first),
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.p16),
          if (items.isEmpty || totalCents <= 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTokens.p20),
              child: Center(
                child: Text(
                  _showExpenses
                      ? 'Nenhuma despesa categorizada.'
                      : 'Nenhuma receita categorizada.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppTokens.darkTextSecondary
                        : AppTokens.lightTextSecondary,
                  ),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 480;
                final donut = SizedBox(
                  width: 90,
                  height: 90,
                  child: CustomPaint(
                    painter: _CategoryDonutChartPainter(
                      items: items,
                      totalCents: totalCents,
                      backgroundColor: isDark
                          ? AppTokens.darkBorder
                          : AppTokens.lightBorder,
                    ),
                    child: Center(
                      child: Text(
                        '${items.length}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? AppTokens.darkTextPrimary
                              : AppTokens.lightTextPrimary,
                        ),
                      ),
                    ),
                  ),
                );

                final legend = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: items.map((item) {
                    final percent = totalCents > 0
                        ? (item.totalCents * 100 / totalCents).round()
                        : 0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3.0),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: item.colorValue,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppTokens.p8),
                          Icon(
                            Category.iconToMaterial(item.icon),
                            size: 14,
                            color: item.colorValue,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.name,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppTokens.darkTextPrimary
                                    : AppTokens.lightTextPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppTokens.p8),
                          Text(
                            '$percent%',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isDark
                                  ? AppTokens.darkTextSecondary
                                  : AppTokens.lightTextSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: AppTokens.p8),
                          Text(
                            widget.obscure ? '••••' : item.total.brl,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppTokens.darkTextPrimary
                                  : AppTokens.lightTextPrimary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );

                if (isWide) {
                  return Row(
                    children: [
                      donut,
                      const SizedBox(width: AppTokens.p24),
                      Expanded(child: legend),
                    ],
                  );
                }

                return Column(
                  children: [
                    Center(child: donut),
                    const SizedBox(height: AppTokens.p16),
                    legend,
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _CategoryDonutChartPainter extends CustomPainter {
  _CategoryDonutChartPainter({
    required this.items,
    required this.totalCents,
    required this.backgroundColor,
  });

  final List<CategorySummaryItem> items;
  final int totalCents;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 14) / 2;
    const strokeWidth = 10.0;

    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, bgPaint);

    if (totalCents <= 0 || items.isEmpty) return;

    double startAngle = -math.pi / 2;

    for (final item in items) {
      final sweepAngle = (item.totalCents / totalCents) * 2 * math.pi;
      final paint = Paint()
        ..color = item.colorValue
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      final adjustedSweep = items.length > 1
          ? math.max(0.01, sweepAngle - 0.06)
          : sweepAngle;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle + (items.length > 1 ? 0.03 : 0),
        adjustedSweep,
        false,
        paint,
      );

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _CategoryDonutChartPainter oldDelegate) {
    return oldDelegate.totalCents != totalCents ||
        oldDelegate.items.length != items.length;
  }
}
