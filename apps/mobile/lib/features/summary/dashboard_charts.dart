import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/text_formatters.dart';
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
    this.accountsAccess,
    this.showCategories = true,
    this.onOpenAccounts,
    this.onOpenReceivables,
    this.onOpenPayables,
  });

  final SpaceSummary summary;
  final List<Account> accounts;
  final bool obscure;
  final Widget? accountsAccess;
  final bool showCategories;
  final VoidCallback? onOpenAccounts;
  final VoidCallback? onOpenReceivables;
  final VoidCallback? onOpenPayables;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWidescreen = constraints.maxWidth >= 760;

        final bankCard = Column(
          children: [
            ?accountsAccess,
            BankDistributionDonutCard(
              accounts: accounts,
              obscure: obscure,
              onTapDetails: accountsAccess == null ? onOpenAccounts : null,
            ),
          ],
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
              if (showCategories) ...[
                const SizedBox(height: AppTokens.p16),
                categoryCard,
              ],
            ],
          );
        }

        return Column(
          children: [
            cashFlowCard,
            const SizedBox(height: AppTokens.p16),
            bankCard,
            if (showCategories) ...[
              const SizedBox(height: AppTokens.p16),
              categoryCard,
            ],
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
                      final bank = BankCatalog.resolveForAccount(account);
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
                                toFinancialUpper(account.name),
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
      final bank = BankCatalog.resolveForAccount(account);
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

/// Saldo no fim da janela, calculado a partir do caixa disponível e dos valores em aberto.
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
    final incoming = summary.receivableDueNext30DaysTotal;
    final outgoing = summary.payables.dueNext30DaysTotal;
    final projection = incoming == null
        ? null
        : Money(summary.balance.cents + incoming.cents - outgoing.cents);
    String format(Money amount) => obscure ? 'R\$ ••••' : amount.brl;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.p16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fluxo de Caixa', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'De hoje até daqui a 30 dias',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (projection == null)
              const Text('Projeção indisponível.')
            else ...[
              _CashFlowLine(
                label: 'Saldo disponível hoje',
                value: format(summary.balance),
              ),
              _CashFlowLine(
                label: 'Entradas previstas',
                value: format(incoming!),
                onTap: onTapReceivables,
              ),
              _CashFlowLine(
                label: 'Saídas previstas',
                value: format(outgoing),
                onTap: onTapPayables,
              ),
              const Divider(),
              _CashFlowLine(
                label: 'Saldo projetado ao fim do período',
                value: format(projection),
                color: !obscure && projection.cents < 0
                    ? theme.colorScheme.error
                    : null,
              ),
              const SizedBox(height: 6),
              Text(
                'Considera valores informados. Vencidos ficam fora da projeção.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CashFlowLine extends StatelessWidget {
  const _CashFlowLine({
    required this.label,
    required this.value,
    this.onTap,
    this.color,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (onTap != null)
            const Icon(Icons.chevron_right, size: 16)
          else
            const SizedBox(width: 16),
        ],
      ),
    );
    return onTap == null ? content : InkWell(onTap: onTap, child: content);
  }
}

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
  final Set<int> _expandedCategoryIds = {};

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
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 420;
              final headerTitle = Row(
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
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );

              final selector = SegmentedButton<bool>(
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
              );

              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    headerTitle,
                    const SizedBox(height: AppTokens.p8),
                    selector,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: headerTitle),
                  const SizedBox(width: AppTokens.p8),
                  selector,
                ],
              );
            },
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
                    final hasComp = item.composition.isNotEmpty;
                    final isExpanded = _expandedCategoryIds.contains(item.id);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: hasComp
                              ? () => setState(() {
                                  if (isExpanded) {
                                    _expandedCategoryIds.remove(item.id);
                                  } else {
                                    _expandedCategoryIds.add(item.id);
                                  }
                                })
                              : null,
                          borderRadius: BorderRadius.circular(AppTokens.r8),
                          child: Padding(
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
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          toFinancialUpper(item.name),
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: isDark
                                                    ? AppTokens.darkTextPrimary
                                                    : AppTokens
                                                          .lightTextPrimary,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (hasComp) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          isExpanded
                                              ? Icons.expand_less_rounded
                                              : Icons.expand_more_rounded,
                                          size: 16,
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ],
                                    ],
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
                          ),
                        ),

                        // Detalhamento da composição da categoria principal
                        if (hasComp && isExpanded)
                          Padding(
                            padding: const EdgeInsets.only(left: 24, bottom: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: item.composition.map((comp) {
                                final compPercent = item.totalCents > 0
                                    ? (comp.totalCents * 100 / item.totalCents)
                                          .round()
                                    : 0;
                                final label = comp.isDirect
                                    ? '${comp.name} (direto)'
                                    : comp.name;

                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2.0,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.subdirectory_arrow_right_rounded,
                                        size: 14,
                                        color: theme.colorScheme.outline,
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Category.iconToMaterial(comp.icon),
                                        size: 12,
                                        color: comp.colorValue,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          toFinancialUpper(label),
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                fontSize: 11,
                                                color: isDark
                                                    ? AppTokens
                                                          .darkTextSecondary
                                                    : AppTokens
                                                          .lightTextSecondary,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        '$compPercent%',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              fontSize: 10,
                                              color: isDark
                                                  ? AppTokens.darkTextSecondary
                                                  : AppTokens
                                                        .lightTextSecondary,
                                            ),
                                      ),
                                      const SizedBox(width: AppTokens.p8),
                                      Text(
                                        widget.obscure
                                            ? '••••'
                                            : comp.total.brl,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              fontSize: 11,
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
