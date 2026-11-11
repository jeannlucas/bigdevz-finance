import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/text_formatters.dart';
import '../../features/categories/category.dart';
import '../../features/categories/category_badge.dart';
import '../../features/settings/preferences_controller.dart';
import '../app_tokens.dart';
import '../widgets.dart';
import 'financial_item_view.dart';

/// Card compacto para exibição em dispositivos móveis (< 840px).
class FinancialMobileCard<T extends FinancialItemView> extends StatelessWidget {
  const FinancialMobileCard({
    super.key,
    required this.item,
    this.isSelectionActive = false,
    this.isSelected = false,
    this.onToggleSelect,
    this.onTap,
    this.quickActionLabel,
    this.onQuickAction,
    this.canQuickAction = true,
  });

  final T item;
  final bool isSelectionActive;
  final bool isSelected;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onTap;
  final String? quickActionLabel;
  final VoidCallback? onQuickAction;
  final bool canQuickAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final obscure =
        context.watch<PreferencesController?>()?.obscureValues ?? false;
    final isSelectable = isSelectionActive && item.isEligibleForBatch;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: isSelected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.r16),
              side: BorderSide(color: theme.colorScheme.primary, width: 1.5),
            )
          : null,
      child: InkWell(
        onTap: isSelectionActive
            ? (isSelectable ? onToggleSelect : null)
            : onTap,
        borderRadius: BorderRadius.circular(AppTokens.r16),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.p12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Checkbox de seleção em lote
              if (isSelectionActive) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 2),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: isSelectable
                          ? (_) => onToggleSelect?.call()
                          : null,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Linha Superior: Descrição e Status
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            toFinancialUpper(item.title),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusChip(
                          label: item.statusLabel,
                          tone: item.statusTone,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Linha Intermediária: Favorecido, Tipo, Categoria
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (item.counterparty != null &&
                            item.counterparty!.trim().isNotEmpty)
                          Text(
                            toFinancialUpper(item.counterparty!),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        Text(
                          item.kindLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.8),
                            fontSize: 11,
                          ),
                        ),
                        if (item.category != null && item.category is Category)
                          CategoryBadge(
                            category: item.category as Category,
                            compact: true,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Linha Inferior: Vencimento e Valor/Ação com quebra fluida (Reflow acessível)
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Text(
                          item.isOverdue && !item.isSettled
                              ? 'Venceu em ${formatDateBr(item.dueDate)}'
                              : 'Vence em ${formatDateBr(item.dueDate)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: item.isOverdue && !item.isSettled
                                ? AppTokens.expense
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (item.isAwaitingAmount)
                              Text(
                                'A informar',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppTokens.warning,
                                  fontSize: 15,
                                ),
                              )
                            else ...[
                              if (item.amountLabel != null)
                                Text(
                                  item.amountLabel!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: item.isOverdue && !item.isSettled
                                        ? AppTokens.expense
                                        : theme.colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              MoneyText(
                                item.pendingAmount ??
                                    item.totalAmount ??
                                    const Money(0),
                                obscure: obscure,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: item.isOverdue && !item.isSettled
                                      ? AppTokens.expense
                                      : null,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              if (item.isPartial &&
                                  item.paidAmount != null &&
                                  item.paidAmount!.cents > 0) ...[
                                if (item.counterparty != null ||
                                    (item.amountLabel != null &&
                                        item.amountLabel!.contains(
                                          'pagar',
                                        ))) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Pago líquido',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontSize: 10,
                                    ),
                                  ),
                                  MoneyText(
                                    item.paidAmount!,
                                    obscure: obscure,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppTokens.income,
                                      fontSize: 11,
                                    ),
                                  ),
                                ] else ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Recebido: ${obscure ? '••••••' : item.paidAmount!.brl}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppTokens.income,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ] else if (!item.isSettled &&
                                  item.totalAmount != null &&
                                  item.pendingAmount != null &&
                                  (item.counterparty != null ||
                                      (item.amountLabel != null &&
                                          item.amountLabel!.contains(
                                            'pagar',
                                          )))) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Valor total',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                ),
                                MoneyText(
                                  item.totalAmount!,
                                  obscure: obscure,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ],
                            if (quickActionLabel != null &&
                                !isSelectionActive) ...[
                              const SizedBox(height: 6),
                              canQuickAction && onQuickAction != null
                                  ? FilledButton.tonal(
                                      onPressed: onQuickAction,
                                      style: FilledButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        minimumSize: const Size(64, 30),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      child: Text(quickActionLabel!),
                                    )
                                  : OutlinedButton(
                                      onPressed: null,
                                      style: OutlinedButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        minimumSize: const Size(64, 30),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 12,
                                        ),
                                      ),
                                      child: Text(quickActionLabel!),
                                    ),
                            ],
                          ],
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
    );
  }
}
