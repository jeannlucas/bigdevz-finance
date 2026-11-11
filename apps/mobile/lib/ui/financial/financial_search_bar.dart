import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../features/categories/category.dart';
import '../../features/categories/category_filter_chip.dart';
import '../app_tokens.dart';
import 'financial_item_view.dart';

/// Opções de ordenação da agenda financeira.
enum FinancialSortOption {
  dueDateAsc('Vencimento (próximos primeiro)', Icons.arrow_upward_rounded),
  dueDateDesc('Vencimento (distantes primeiro)', Icons.arrow_downward_rounded),
  amountDesc('Maior valor', Icons.trending_down_rounded),
  amountAsc('Menor valor', Icons.trending_up_rounded),
  titleAsc('Descrição (A-Z)', Icons.sort_by_alpha_rounded);

  const FinancialSortOption(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Opções de filtro por período de vencimento.
enum FinancialPeriodFilter {
  all('Todos os períodos'),
  overdue('Vencidas'),
  today('Hoje'),
  next7Days('Próximos 7 dias'),
  thisMonth('Este mês'),
  next30Days('Próximos 30 dias'),
  future('Futuras');

  const FinancialPeriodFilter(this.label);

  final String label;
}

/// Determina se uma data de vencimento atende ao filtro de período.
bool matchesPeriod(
  String dueDateStr,
  FinancialPeriodFilter period, [
  DateTime? now,
]) {
  if (period == FinancialPeriodFilter.all) return true;
  final n = now ?? DateTime.now();
  final group = classifyDueDate(dueDateStr, refDate: n);

  switch (period) {
    case FinancialPeriodFilter.all:
      return true;
    case FinancialPeriodFilter.overdue:
      return group == FinancialDueDateGroup.overdue;
    case FinancialPeriodFilter.today:
      return group == FinancialDueDateGroup.today;
    case FinancialPeriodFilter.next7Days:
      return group == FinancialDueDateGroup.next7Days;
    case FinancialPeriodFilter.thisMonth:
      final dt = parseApiDate(dueDateStr);
      final today = DateUtils.dateOnly(n);
      return dt.year == today.year && dt.month == today.month;
    case FinancialPeriodFilter.next30Days:
      final dt = parseApiDate(dueDateStr);
      final today = DateUtils.dateOnly(n);
      final diff = dt.difference(today).inDays;
      return diff >= 0 && diff <= 30;
    case FinancialPeriodFilter.future:
      return group == FinancialDueDateGroup.future;
  }
}

const Map<String, String> _diacriticsMap = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ă': 'a',
  'ą': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ĕ': 'e',
  'ė': 'e',
  'ę': 'e',
  'ě': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'ĭ': 'i',
  'į': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ō': 'o',
  'ŏ': 'o',
  'ő': 'o',
  'ø': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ũ': 'u',
  'ū': 'u',
  'ŭ': 'u',
  'ů': 'u',
  'ű': 'u',
  'ų': 'u',
  'ç': 'c',
  'ć': 'c',
  'ĉ': 'c',
  'ċ': 'c',
  'č': 'c',
  'ñ': 'n',
  'ń': 'n',
  'ņ': 'n',
  'ň': 'n',
  'ý': 'y',
  'ÿ': 'y',
  'ŷ': 'y',
};

/// Normaliza um texto para busca:
/// - Converte para minúsculas;
/// - Remove acentos e diacríticos latinos;
/// - Remove espaços nas extremidades e colapsa múltiplos espaços em um único espaço.
String normalizeSearchText(String input) {
  if (input.isEmpty) return '';
  final trimmed = input.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.isEmpty) return '';

  final lower = trimmed.toLowerCase();
  final buffer = StringBuffer();
  for (var i = 0; i < lower.length; i++) {
    final char = lower[i];
    buffer.write(_diacriticsMap[char] ?? char);
  }
  return buffer.toString();
}

/// Filtra e ordena uma lista de itens financeiros em memória.
List<T> filterAndSortFinancialItems<T extends FinancialItemView>(
  List<T> items, {
  String? query,
  FinancialSortOption sort = FinancialSortOption.dueDateAsc,
  FinancialPeriodFilter period = FinancialPeriodFilter.all,
  int? categoryId,
  DateTime? now,
}) {
  final q = normalizeSearchText(query ?? '');
  final n = now ?? DateTime.now();

  final filtered = items.where((item) {
    // 1. Busca textual insensível a maiúsculas, acentos e espaços
    if (q.isNotEmpty) {
      final titleNorm = normalizeSearchText(item.title);
      final counterpartyNorm = item.counterparty != null
          ? normalizeSearchText(item.counterparty!)
          : '';
      final fullText = '$titleNorm $counterpartyNorm';

      // Suporta busca da query inteira ou de todas as palavras/tokens
      final tokens = q.split(' ');
      final matches = tokens.every((token) => fullText.contains(token));
      if (!matches) return false;
    }

    // 2. Filtro de período
    if (period != FinancialPeriodFilter.all) {
      if (!matchesPeriod(item.dueDate, period, n)) return false;
    }

    // 3. Filtro de categoria
    if (categoryId != null) {
      final itemCatId =
          item.categoryId ??
          (item.category is Category ? (item.category as Category).id : null);
      if (itemCatId != categoryId) {
        return false;
      }
    }

    return true;
  }).toList();

  filtered.sort((a, b) {
    switch (sort) {
      case FinancialSortOption.dueDateAsc:
        final cmp = a.dueDate.compareTo(b.dueDate);
        return cmp != 0 ? cmp : a.id.compareTo(b.id);
      case FinancialSortOption.dueDateDesc:
        final cmp = b.dueDate.compareTo(a.dueDate);
        return cmp != 0 ? cmp : b.id.compareTo(a.id);
      case FinancialSortOption.amountDesc:
        final aCents = a.pendingAmount?.cents ?? -1;
        final bCents = b.pendingAmount?.cents ?? -1;
        final cmp = bCents.compareTo(aCents);
        return cmp != 0 ? cmp : a.dueDate.compareTo(b.dueDate);
      case FinancialSortOption.amountAsc:
        final aCents = a.pendingAmount?.cents ?? 99999999999999;
        final bCents = b.pendingAmount?.cents ?? 99999999999999;
        final cmp = aCents.compareTo(bCents);
        return cmp != 0 ? cmp : a.dueDate.compareTo(b.dueDate);
      case FinancialSortOption.titleAsc:
        final aNorm = normalizeSearchText(a.title);
        final bNorm = normalizeSearchText(b.title);
        final cmp = aNorm.compareTo(bNorm);
        return cmp != 0 ? cmp : a.dueDate.compareTo(b.dueDate);
    }
  });

  return filtered;
}

/// Abre o Bottom Sheet deslizante com filtros avançados no Mobile.
Future<void> showFinancialFiltersSheet({
  required BuildContext context,
  required String currentStatus,
  required Map<String, String> statusOptions,
  required ValueChanged<String> onStatusSelected,
  required FinancialPeriodFilter currentPeriod,
  required ValueChanged<FinancialPeriodFilter> onPeriodSelected,
  required int? currentCategoryId,
  required ValueChanged<int?> onCategorySelected,
  required int spaceId,
  required String categoryType,
  required VoidCallback onClearAll,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTokens.r20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Filtros avançados',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          onClearAll();
                          setSheetState(() {});
                        },
                        child: const Text('Limpar todos'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Situação / Status
                  Text(
                    'Situação',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final entry in statusOptions.entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: currentStatus == entry.key,
                          onSelected: (selected) {
                            if (selected) {
                              onStatusSelected(entry.key);
                              setSheetState(() {});
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Período de Vencimento
                  Text(
                    'Período de vencimento',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final p in FinancialPeriodFilter.values)
                        ChoiceChip(
                          label: Text(p.label),
                          selected: currentPeriod == p,
                          onSelected: (selected) {
                            if (selected) {
                              onPeriodSelected(p);
                              setSheetState(() {});
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Categoria
                  Text(
                    'Categoria',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CategoryFilterChip(
                      spaceId: spaceId,
                      type: categoryType,
                      selectedCategoryId: currentCategoryId,
                      onChanged: (catId) {
                        onCategorySelected(catId);
                        setSheetState(() {});
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Aplicar filtros'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Barra de busca textual e controles de ordenação e filtros rápidos.
class FinancialSearchBar extends StatelessWidget {
  const FinancialSearchBar({
    super.key,
    required this.query,
    required this.onQueryChanged,
    required this.sort,
    required this.onSortChanged,
    this.onOpenFilters,
    this.activeFiltersCount = 0,
    this.hintText = 'Buscar por descrição, fornecedor ou cliente...',
    this.activeFilterChips = const [],
    this.onClearAllFilters,
  });

  final String query;
  final ValueChanged<String> onQueryChanged;
  final FinancialSortOption sort;
  final ValueChanged<FinancialSortOption> onSortChanged;
  final VoidCallback? onOpenFilters;
  final int activeFiltersCount;
  final String hintText;
  final List<Widget> activeFilterChips;
  final VoidCallback? onClearAllFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Linha com Campo de Busca e Botões
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: TextField(
                  controller: TextEditingController.fromValue(
                    TextEditingValue(
                      text: query,
                      selection: TextSelection.collapsed(offset: query.length),
                    ),
                  ),
                  onChanged: onQueryChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.7,
                      ),
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () => onQueryChanged(''),
                            tooltip: 'Limpar busca',
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.45),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.r12),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.r12),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.4,
                        ),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.r12),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Menu de Ordenação
            PopupMenuButton<FinancialSortOption>(
              icon: Icon(
                sort.icon,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              tooltip: 'Ordenar: ${sort.label}',
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.r12),
              ),
              initialValue: sort,
              onSelected: onSortChanged,
              itemBuilder: (context) => [
                for (final opt in FinancialSortOption.values)
                  PopupMenuItem(
                    value: opt,
                    child: Row(
                      children: [
                        Icon(
                          opt.icon,
                          size: 18,
                          color: opt == sort
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            opt.label,
                            style: TextStyle(
                              fontWeight: opt == sort
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: opt == sort
                                  ? theme.colorScheme.primary
                                  : null,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (opt == sort)
                          Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                      ],
                    ),
                  ),
              ],
            ),

            // Botão de Filtros Avançados
            if (onOpenFilters != null) ...[
              const SizedBox(width: 4),
              Badge(
                isLabelVisible: activeFiltersCount > 0,
                label: Text('$activeFiltersCount'),
                child: IconButton.outlined(
                  onPressed: onOpenFilters,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  tooltip: 'Filtros',
                  style: IconButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(38, 38),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.r12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),

        // Chips de Filtros Ativos
        if (activeFilterChips.isNotEmpty || query.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (query.isNotEmpty)
                InputChip(
                  label: Text('Busca: "$query"'),
                  onDeleted: () => onQueryChanged(''),
                  deleteIconColor: theme.colorScheme.onSurfaceVariant,
                  visualDensity: VisualDensity.compact,
                ),
              ...activeFilterChips,
              if (onClearAllFilters != null &&
                  (activeFilterChips.isNotEmpty || query.isNotEmpty))
                TextButton(
                  onPressed: onClearAllFilters,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('Limpar filtros'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
