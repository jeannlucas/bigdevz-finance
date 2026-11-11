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

/// Callback de ação rápida para um item financeiro.
typedef FinancialItemActionCallback<T extends FinancialItemView> =
    void Function(T item);

/// Cabeçalho da tabela corporativa densa para Desktop.
class FinancialDesktopTableHeader extends StatelessWidget {
  const FinancialDesktopTableHeader({
    super.key,
    this.isSelectionActive = false,
    this.hasQuickAction = false,
  });

  final bool isSelectionActive;
  final bool hasQuickAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.r12),
        ),
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          left: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          right: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (isSelectionActive) ...[
            const SizedBox(width: 32),
            const SizedBox(width: 8),
          ],
          const SizedBox(
            width: 96,
            child: Text(
              'Vencimento',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            flex: 3,
            child: Text(
              'Descrição / Favorecido',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            flex: 2,
            child: Text(
              'Categoria',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            flex: 2,
            child: Text(
              'Tipo / Parcela',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          const SizedBox(
            width: 110,
            child: Text(
              'Situação',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          const SizedBox(
            width: 120,
            child: Text(
              'Valor',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          if (hasQuickAction) ...[
            const SizedBox(width: 16),
            const SizedBox(
              width: 90,
              child: Text(
                'Ações',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Linha individual de tabela para Desktop (renderizada sob demanda).
class FinancialDesktopTableRow<T extends FinancialItemView>
    extends StatelessWidget {
  const FinancialDesktopTableRow({
    super.key,
    required this.item,
    this.isFirst = false,
    this.isLast = false,
    this.isSelected = false,
    this.isSelectionActive = false,
    this.onToggleSelect,
    this.onTap,
    this.quickActionLabel,
    this.quickActionIcon,
    this.onQuickAction,
    this.canQuickAction = true,
  });

  final T item;
  final bool isFirst;
  final bool isLast;
  final bool isSelected;
  final bool isSelectionActive;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onTap;
  final String? quickActionLabel;
  final IconData? quickActionIcon;
  final VoidCallback? onQuickAction;
  final bool canQuickAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final obscure =
        context.watch<PreferencesController?>()?.obscureValues ?? false;
    final isSelectable = isSelectionActive && item.isEligibleForBatch;

    return Container(
      decoration: BoxDecoration(
        color: isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.2)
            : theme.colorScheme.surface,
        borderRadius: isLast
            ? const BorderRadius.vertical(
                bottom: Radius.circular(AppTokens.r12),
              )
            : BorderRadius.zero,
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          right: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isSelectionActive
              ? (isSelectable ? onToggleSelect : null)
              : onTap,
          borderRadius: isLast
              ? const BorderRadius.vertical(
                  bottom: Radius.circular(AppTokens.r12),
                )
              : BorderRadius.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Checkbox de Seleção
                if (isSelectionActive) ...[
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: isSelectable
                          ? (_) => onToggleSelect?.call()
                          : null,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                // Vencimento
                SizedBox(
                  width: 96,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatDateBr(item.dueDate),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: item.isOverdue && !item.isSettled
                              ? AppTokens.expense
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      if (item.isOverdue && !item.isSettled)
                        Text(
                          'Vencida',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppTokens.expense,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Descrição e Favorecido / Cliente
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        toFinancialUpper(item.title),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.counterparty != null &&
                          item.counterparty!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          toFinancialUpper(item.counterparty!),
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Categoria
                Expanded(
                  flex: 2,
                  child: item.category != null && item.category is Category
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: CategoryBadge(
                            category: item.category as Category,
                            compact: true,
                          ),
                        )
                      : const Text(
                          '—',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                ),
                const SizedBox(width: 12),

                // Tipo / Parcela
                Expanded(
                  flex: 2,
                  child: Text(
                    item.kindLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),

                // Situação
                SizedBox(
                  width: 110,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: StatusChip(
                      label: item.statusLabel,
                      tone: item.statusTone,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Valor
                SizedBox(
                  width: 120,
                  child: item.isAwaitingAmount
                      ? Text(
                          'A informar',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTokens.warning,
                          ),
                        )
                      : MoneyText(
                          item.pendingAmount ??
                              item.totalAmount ??
                              const Money(0),
                          obscure: obscure,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: item.isOverdue && !item.isSettled
                                ? AppTokens.expense
                                : null,
                          ),
                        ),
                ),

                // Ações Rápidas
                if (quickActionLabel != null) ...[
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 90,
                    child: canQuickAction && onQuickAction != null
                        ? FilledButton.tonal(
                            onPressed: onQuickAction,
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              minimumSize: const Size(0, 32),
                              textStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            child: Text(quickActionLabel!),
                          )
                        : Text(
                            '—',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.5),
                              fontSize: 12,
                            ),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tabela densa corporativa estática para Desktop (legada/compatibilidade).
class FinancialDesktopTable<T extends FinancialItemView>
    extends StatelessWidget {
  const FinancialDesktopTable({
    super.key,
    required this.items,
    this.isSelectionActive = false,
    this.selectedIds = const {},
    this.onToggleSelect,
    this.onTapItem,
    this.quickActionLabel,
    this.quickActionIcon,
    this.onQuickAction,
    this.isQuickActionEnabled,
  });

  final List<T> items;
  final bool isSelectionActive;
  final Set<int> selectedIds;
  final ValueChanged<int>? onToggleSelect;
  final ValueChanged<T>? onTapItem;
  final String? quickActionLabel;
  final IconData? quickActionIcon;
  final FinancialItemActionCallback<T>? onQuickAction;
  final bool Function(T item)? isQuickActionEnabled;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FinancialDesktopTableHeader(
          isSelectionActive: isSelectionActive,
          hasQuickAction: quickActionLabel != null,
        ),
        for (int i = 0; i < items.length; i++)
          FinancialDesktopTableRow<T>(
            item: items[i],
            isFirst: i == 0,
            isLast: i == items.length - 1,
            isSelected: selectedIds.contains(items[i].id),
            isSelectionActive: isSelectionActive,
            onToggleSelect: () => onToggleSelect?.call(items[i].id),
            onTap: () => onTapItem?.call(items[i]),
            quickActionLabel: quickActionLabel,
            quickActionIcon: quickActionIcon,
            onQuickAction: onQuickAction != null
                ? () => onQuickAction!(items[i])
                : null,
            canQuickAction: isQuickActionEnabled?.call(items[i]) ?? true,
          ),
      ],
    );
  }
}
