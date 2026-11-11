import 'package:flutter/material.dart';

import 'financial_desktop_table.dart';
import 'financial_group_header.dart';
import 'financial_item_view.dart';
import 'financial_mobile_card.dart';

/// Tipos de entradas na lista plana da agenda financeira virtualizada.
sealed class _AgendaEntry<T extends FinancialItemView> {
  const _AgendaEntry();
}

class _GroupHeaderEntry<T extends FinancialItemView> extends _AgendaEntry<T> {
  const _GroupHeaderEntry({
    required this.group,
    required this.summary,
    required this.isExpanded,
  });

  final FinancialDueDateGroup group;
  final FinancialGroupSummary<T> summary;
  final bool isExpanded;
}

class _DesktopTableHeaderEntry<T extends FinancialItemView>
    extends _AgendaEntry<T> {
  const _DesktopTableHeaderEntry({required this.group});

  final FinancialDueDateGroup group;
}

class _ItemEntry<T extends FinancialItemView> extends _AgendaEntry<T> {
  const _ItemEntry({
    required this.group,
    required this.item,
    required this.itemIndexInGroup,
    required this.totalItemsInGroup,
  });

  final FinancialDueDateGroup group;
  final T item;
  final int itemIndexInGroup;
  final int totalItemsInGroup;
}

/// Constrói a lista plana de entradas a partir dos grupos e estados de expansão.
List<_AgendaEntry<T>> _buildAgendaEntries<T extends FinancialItemView>({
  required Map<FinancialDueDateGroup, FinancialGroupSummary<T>> grouped,
  required Set<FinancialDueDateGroup> expandedGroups,
  required bool isDesktop,
}) {
  final entries = <_AgendaEntry<T>>[];

  for (final group in FinancialDueDateGroup.values) {
    final summary = grouped[group];
    if (summary == null || summary.count == 0) continue;

    final isExpanded = expandedGroups.contains(group);
    entries.add(
      _GroupHeaderEntry<T>(
        group: group,
        summary: summary,
        isExpanded: isExpanded,
      ),
    );

    if (isExpanded) {
      if (isDesktop) {
        entries.add(_DesktopTableHeaderEntry<T>(group: group));
      }
      for (int i = 0; i < summary.items.length; i++) {
        entries.add(
          _ItemEntry<T>(
            group: group,
            item: summary.items[i],
            itemIndexInGroup: i,
            totalItemsInGroup: summary.items.length,
          ),
        );
      }
    }
  }

  return entries;
}

/// Visão unificada da agenda financeira com virtualização real por item.
///
/// Tanto no Desktop quanto no Mobile, cada linha de tabela ou card é renderizado
/// sob demanda através de um único [ListView.builder], sem instanciar todos os widgets
/// simultaneamente quando um grupo possui 110, 500 ou mais lançamentos.
class FinancialAgendaView<T extends FinancialItemView> extends StatelessWidget {
  const FinancialAgendaView({
    super.key,
    required this.items,
    required this.expandedGroups,
    required this.onToggleGroup,
    required this.isDesktop,
    this.isSelectionActive = false,
    this.selectedIds = const {},
    this.onToggleSelect,
    this.onTapItem,
    this.quickActionLabel,
    this.quickActionIcon,
    this.onQuickAction,
    this.isQuickActionEnabled,
    this.singularLabel = 'item',
    this.pluralLabel = 'itens',
    this.emptyMessage =
        'Nenhum lançamento encontrado para a busca ou filtro aplicado.',
  });

  final List<T> items;
  final Set<FinancialDueDateGroup> expandedGroups;
  final ValueChanged<FinancialDueDateGroup> onToggleGroup;
  final bool isDesktop;
  final bool isSelectionActive;
  final Set<int> selectedIds;
  final ValueChanged<int>? onToggleSelect;
  final ValueChanged<T>? onTapItem;
  final String? quickActionLabel;
  final IconData? quickActionIcon;
  final FinancialItemActionCallback<T>? onQuickAction;
  final bool Function(T item)? isQuickActionEnabled;
  final String singularLabel;
  final String pluralLabel;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.6,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final grouped = groupFinancialItems<T>(items);
    final entries = _buildAgendaEntries<T>(
      grouped: grouped,
      expandedGroups: expandedGroups,
      isDesktop: isDesktop,
    );

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];

        if (entry is _GroupHeaderEntry<T>) {
          final isFirstGroup = index == 0;
          return Padding(
            padding: EdgeInsets.only(
              top: isFirstGroup ? 0 : 12,
              bottom: entry.isExpanded ? 6 : 0,
            ),
            child: FinancialGroupHeader(
              group: entry.group,
              count: entry.summary.count,
              total: entry.summary.total,
              isExpanded: entry.isExpanded,
              onToggleExpanded: () => onToggleGroup(entry.group),
              singularLabel: singularLabel,
              pluralLabel: pluralLabel,
            ),
          );
        }

        if (entry is _DesktopTableHeaderEntry<T>) {
          return Padding(
            padding: const EdgeInsets.only(top: 2),
            child: FinancialDesktopTableHeader(
              isSelectionActive: isSelectionActive,
              hasQuickAction: quickActionLabel != null,
            ),
          );
        }

        if (entry is _ItemEntry<T>) {
          final item = entry.item;
          if (isDesktop) {
            return FinancialDesktopTableRow<T>(
              item: item,
              isFirst: entry.itemIndexInGroup == 0,
              isLast: entry.itemIndexInGroup == entry.totalItemsInGroup - 1,
              isSelected: selectedIds.contains(item.id),
              isSelectionActive: isSelectionActive,
              onToggleSelect: () => onToggleSelect?.call(item.id),
              onTap: () => onTapItem?.call(item),
              quickActionLabel: quickActionLabel,
              quickActionIcon: quickActionIcon,
              onQuickAction: onQuickAction != null
                  ? () => onQuickAction!(item)
                  : null,
              canQuickAction: isQuickActionEnabled?.call(item) ?? true,
            );
          } else {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FinancialMobileCard<T>(
                item: item,
                isSelectionActive: isSelectionActive,
                isSelected: selectedIds.contains(item.id),
                onToggleSelect: () => onToggleSelect?.call(item.id),
                onTap: () => onTapItem?.call(item),
                quickActionLabel: quickActionLabel,
                onQuickAction: onQuickAction != null
                    ? () => onQuickAction!(item)
                    : null,
                canQuickAction: isQuickActionEnabled?.call(item) ?? true,
              ),
            );
          }
        }

        return const SizedBox.shrink();
      },
    );
  }
}
