import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../features/categories/category.dart';
import '../../features/categories/category_filter_chip.dart';
import '../app_icons.dart';
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

/// Opções de filtro por período de vencimento (legado).
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

const List<String> _monthNamesPtBr = [
  '',
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];

/// Formata uma data no formato "Mês de AAAA" em português do Brasil (ex.: "Novembro de 2026").
String formatMonthYearBr(DateTime date) {
  final m = (date.month >= 1 && date.month <= 12)
      ? _monthNamesPtBr[date.month]
      : '';
  return '$m de ${date.year}';
}

/// Tipos de seleção de período financeiro.
enum FinancialPeriodType {
  month,
  overdue,
  all,
  today,
  next7Days,
  next30Days,
  custom,
}

/// Representa a seleção temporal ativa na agenda financeira.
///
/// Permite filtrar por mês específico com navegação (mês anterior/próximo),
/// visualizar apenas vencidas, exibir todos os períodos ou intervalo personalizado.
class FinancialPeriodSelection {
  const FinancialPeriodSelection({
    required this.type,
    this.referenceMonth,
    this.customStartDate,
    this.customEndDate,
  });

  /// Inicia no mês corrente completo (1º ao último dia do mês corrente).
  factory FinancialPeriodSelection.currentMonth([DateTime? now]) {
    final n = now ?? DateTime.now();
    return FinancialPeriodSelection(
      type: FinancialPeriodType.month,
      referenceMonth: DateTime(n.year, n.month, 1),
    );
  }

  /// Seleção de um mês específico pelo ano e mês.
  factory FinancialPeriodSelection.month(int year, int month) {
    return FinancialPeriodSelection(
      type: FinancialPeriodType.month,
      referenceMonth: DateTime(year, month, 1),
    );
  }

  /// Seleção exclusiva de contas vencidas.
  const FinancialPeriodSelection.overdue()
    : type = FinancialPeriodType.overdue,
      referenceMonth = null,
      customStartDate = null,
      customEndDate = null;

  /// Exibir todas as contas sem restrição de período.
  const FinancialPeriodSelection.all()
    : type = FinancialPeriodType.all,
      referenceMonth = null,
      customStartDate = null,
      customEndDate = null;

  /// Seleção de intervalo personalizado com validação de datas.
  factory FinancialPeriodSelection.custom(DateTime start, DateTime end) {
    final s = DateUtils.dateOnly(start);
    final e = DateUtils.dateOnly(end);
    final validStart = s.isAfter(e) ? e : s;
    final validEnd = s.isAfter(e) ? s : e;
    return FinancialPeriodSelection(
      type: FinancialPeriodType.custom,
      customStartDate: validStart,
      customEndDate: validEnd,
    );
  }

  final FinancialPeriodType type;
  final DateTime? referenceMonth;
  final DateTime? customStartDate;
  final DateTime? customEndDate;

  DateTime? get startDate {
    if (type == FinancialPeriodType.custom) {
      return customStartDate;
    }
    if (type != FinancialPeriodType.month || referenceMonth == null) {
      return null;
    }
    return DateTime(referenceMonth!.year, referenceMonth!.month, 1);
  }

  DateTime? get endDate {
    if (type == FinancialPeriodType.custom) {
      return customEndDate;
    }
    if (type != FinancialPeriodType.month || referenceMonth == null) {
      return null;
    }
    return DateTime(referenceMonth!.year, referenceMonth!.month + 1, 0);
  }

  String get label {
    switch (type) {
      case FinancialPeriodType.month:
        return referenceMonth != null
            ? formatMonthYearBr(referenceMonth!)
            : 'Mês corrente';
      case FinancialPeriodType.overdue:
        return 'Vencidas';
      case FinancialPeriodType.all:
        return 'Todos os períodos';
      case FinancialPeriodType.today:
        return 'Hoje';
      case FinancialPeriodType.next7Days:
        return 'Próximos 7 dias';
      case FinancialPeriodType.next30Days:
        return 'Próximos 30 dias';
      case FinancialPeriodType.custom:
        if (customStartDate != null && customEndDate != null) {
          return '${formatDateBr(toApiDate(customStartDate!))} a ${formatDateBr(toApiDate(customEndDate!))}';
        }
        return 'Intervalo personalizado';
    }
  }

  bool isCurrentMonth([DateTime? now]) {
    if (type != FinancialPeriodType.month || referenceMonth == null) {
      return false;
    }
    final n = now ?? DateTime.now();
    return referenceMonth!.year == n.year && referenceMonth!.month == n.month;
  }

  FinancialPeriodSelection nextMonth() {
    final base = referenceMonth ?? DateTime.now();
    return FinancialPeriodSelection.month(base.year, base.month + 1);
  }

  FinancialPeriodSelection previousMonth() {
    final base = referenceMonth ?? DateTime.now();
    return FinancialPeriodSelection.month(base.year, base.month - 1);
  }

  bool matches(String dueDateStr, [DateTime? now]) {
    if (type == FinancialPeriodType.all) return true;
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final due = parseApiDate(dueDateStr);
    final dueDate = DateTime(due.year, due.month, due.day);

    switch (type) {
      case FinancialPeriodType.all:
        return true;
      case FinancialPeriodType.overdue:
        return dueDate.isBefore(today);
      case FinancialPeriodType.today:
        return dueDate.isAtSameMomentAs(today);
      case FinancialPeriodType.next7Days:
        final in7 = today.add(const Duration(days: 7));
        return !dueDate.isBefore(today) && !dueDate.isAfter(in7);
      case FinancialPeriodType.next30Days:
        final in30 = today.add(const Duration(days: 30));
        return !dueDate.isBefore(today) && !dueDate.isAfter(in30);
      case FinancialPeriodType.month:
        final ref = referenceMonth ?? today;
        final startOfMonth = DateTime(ref.year, ref.month, 1);
        final endOfMonth = DateTime(ref.year, ref.month + 1, 0);
        return !dueDate.isBefore(startOfMonth) && !dueDate.isAfter(endOfMonth);
      case FinancialPeriodType.custom:
        final start = customStartDate != null
            ? DateUtils.dateOnly(customStartDate!)
            : null;
        final end = customEndDate != null
            ? DateUtils.dateOnly(customEndDate!)
            : null;
        if (start != null && dueDate.isBefore(start)) return false;
        if (end != null && dueDate.isAfter(end)) return false;
        return true;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinancialPeriodSelection &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          (type != FinancialPeriodType.month ||
              (referenceMonth?.year == other.referenceMonth?.year &&
                  referenceMonth?.month == other.referenceMonth?.month)) &&
          (type != FinancialPeriodType.custom ||
              (customStartDate == other.customStartDate &&
                  customEndDate == other.customEndDate));

  @override
  int get hashCode => Object.hash(
    type,
    type == FinancialPeriodType.month ? referenceMonth?.year : null,
    type == FinancialPeriodType.month ? referenceMonth?.month : null,
    type == FinancialPeriodType.custom ? customStartDate : null,
    type == FinancialPeriodType.custom ? customEndDate : null,
  );
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
  FinancialPeriodSelection? periodSelection,
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
    if (periodSelection != null) {
      if (!periodSelection.matches(item.dueDate, n)) return false;
    } else if (period != FinancialPeriodFilter.all) {
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
/// Agrupa os filtros visíveis da página no desktop.
class FinancialFilterPanel extends StatelessWidget {
  const FinancialFilterPanel({
    super.key,
    required this.period,
    required this.controls,
    this.onClear,
  });

  final Widget period;
  final Widget controls;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('financial-filter-panel'),
      padding: const EdgeInsets.all(AppTokens.p12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTokens.r12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppTokens.p16,
            runSpacing: AppTokens.p8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.date_range_outlined, size: 18),
              Text('Período', style: theme.textTheme.labelLarge),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 330),
                child: period,
              ),
              if (onClear != null)
                TextButton(
                  onPressed: onClear,
                  child: const Text('Limpar filtros'),
                ),
            ],
          ),
          const Divider(height: 18),
          controls,
        ],
      ),
    );
  }
}

/// Estado vazio contextual dentro da área de resultados.
class FinancialEmptyPanel extends StatelessWidget {
  const FinancialEmptyPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final List<List<dynamic>> icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card.outlined(
          margin: const EdgeInsets.all(AppTokens.p16),
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.p20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppIcon(icon, size: 24, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                if (action != null) ...[
                  const SizedBox(height: 12),
                  Center(child: action),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showFinancialFiltersSheet({
  required BuildContext context,
  required String currentStatus,
  required Map<String, String> statusOptions,
  required ValueChanged<String> onStatusSelected,
  required int? currentCategoryId,
  required ValueChanged<int?> onCategorySelected,
  required int spaceId,
  required String categoryType,
}) async {
  var status = currentStatus;
  var categoryId = currentCategoryId;

  final apply = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (ctx, update) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Filtros', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              const Text('Situação'),
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in statusOptions.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: status == entry.key,
                      onSelected: (_) => update(() => status = entry.key),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              CategoryFilterChip(
                spaceId: spaceId,
                type: categoryType,
                selectedCategoryId: categoryId,
                onChanged: (id) => update(() => categoryId = id),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Aplicar filtros'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancelar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (apply != true || !context.mounted) return;
  if (status != currentStatus) onStatusSelected(status);
  if (categoryId != currentCategoryId) onCategorySelected(categoryId);
}

/// Barra de busca textual e controles de ordenação e filtros rápidos.
class FinancialSearchBar extends StatefulWidget {
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
  State<FinancialSearchBar> createState() => _FinancialSearchBarState();
}

class _FinancialSearchBarState extends State<FinancialSearchBar> {
  late final _controller = TextEditingController(text: widget.query);

  @override
  void didUpdateWidget(covariant FinancialSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.query) {
      _controller.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
                  controller: _controller,
                  onChanged: widget.onQueryChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.7,
                      ),
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: widget.query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () => widget.onQueryChanged(''),
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
              icon: MediaQuery.sizeOf(context).width >= 840
                  ? null
                  : Icon(widget.sort.icon, size: 20),
              tooltip: 'Ordenar: ${widget.sort.label}',
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.r12),
              ),
              initialValue: widget.sort,
              onSelected: widget.onSortChanged,
              itemBuilder: (context) => [
                for (final opt in FinancialSortOption.values)
                  PopupMenuItem(
                    value: opt,
                    child: Row(
                      children: [
                        Icon(
                          opt.icon,
                          size: 18,
                          color: opt == widget.sort
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            opt.label,
                            style: TextStyle(
                              fontWeight: opt == widget.sort
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: opt == widget.sort
                                  ? theme.colorScheme.primary
                                  : null,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (opt == widget.sort)
                          Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                      ],
                    ),
                  ),
              ],
              child: MediaQuery.sizeOf(context).width < 840
                  ? null
                  : Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(widget.sort.icon, size: 18),
                          const SizedBox(width: 8),
                          const Text('Ordenar'),
                        ],
                      ),
                    ),
            ),

            // Botão de Filtros Avançados
            if (widget.onOpenFilters != null) ...[
              const SizedBox(width: 4),
              Badge(
                isLabelVisible: widget.activeFiltersCount > 0,
                label: Text('${widget.activeFiltersCount}'),
                child: IconButton.outlined(
                  onPressed: widget.onOpenFilters,
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
        if (widget.activeFilterChips.isNotEmpty || widget.query.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.query.isNotEmpty)
                InputChip(
                  label: Text('Busca: "${widget.query}"'),
                  onDeleted: () => widget.onQueryChanged(''),
                  deleteIconColor: theme.colorScheme.onSurfaceVariant,
                  visualDensity: VisualDensity.compact,
                ),
              ...widget.activeFilterChips,
              if (widget.onClearAllFilters != null &&
                  (widget.activeFilterChips.isNotEmpty ||
                      widget.query.isNotEmpty))
                TextButton(
                  onPressed: widget.onClearAllFilters,
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

/// Barra de navegação e seletor de período para a agenda financeira (mês atual, mês anterior/próximo, vencidas e todas).
class FinancialPeriodBar extends StatelessWidget {
  const FinancialPeriodBar({
    super.key,
    required this.selection,
    required this.onChanged,
    this.overdueCount = 0,
    this.showOverdue = true,
    this.now,
  });

  final FinancialPeriodSelection selection;
  final ValueChanged<FinancialPeriodSelection> onChanged;
  final int overdueCount;
  final bool showOverdue;
  final DateTime? now;

  Future<void> _pickCustomRange(BuildContext context) async {
    final baseNow = now ?? DateTime.now();
    final initialStart =
        selection.startDate ?? DateTime(baseNow.year, baseNow.month, 1);
    final initialEnd =
        selection.endDate ?? DateTime(baseNow.year, baseNow.month + 1, 0);
    final range = DateTimeRange(
      start: initialStart.isBefore(initialEnd) ? initialStart : initialEnd,
      end: initialEnd.isAfter(initialStart) ? initialEnd : initialStart,
    );

    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: range,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
      helpText: 'Selecione o intervalo de vencimento',
      saveText: 'Aplicar',
    );

    if (picked != null) {
      onChanged(FinancialPeriodSelection.custom(picked.start, picked.end));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMonth = selection.type == FinancialPeriodType.month;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(AppTokens.r12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          // Botão Anterior (<)
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 22),
            onPressed: isMonth
                ? () => onChanged(selection.previousMonth())
                : () => onChanged(FinancialPeriodSelection.currentMonth(now)),
            tooltip: isMonth ? 'Mês anterior' : 'Voltar ao mês atual',
            visualDensity: VisualDensity.compact,
          ),

          // Seletor Central
          Expanded(
            child: PopupMenuButton<String>(
              tooltip: 'Alterar período (${selection.label})',
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.r12),
              ),
              onSelected: (val) {
                if (val == 'current') {
                  onChanged(FinancialPeriodSelection.currentMonth(now));
                } else if (val == 'last7' ||
                    val == 'last30' ||
                    val == 'next7' ||
                    val == 'next30') {
                  final today = DateUtils.dateOnly(now ?? DateTime.now());
                  final upcoming = val == 'next7' || val == 'next30';
                  final start = upcoming
                      ? today
                      : DateTime(
                          today.year,
                          today.month,
                          today.day - (val == 'last7' ? 6 : 29),
                        );
                  final end = upcoming
                      ? DateTime(
                          today.year,
                          today.month,
                          today.day + (val == 'next7' ? 6 : 29),
                        )
                      : today;
                  onChanged(FinancialPeriodSelection.custom(start, end));
                } else if (val == 'overdue') {
                  onChanged(FinancialPeriodSelection.overdue());
                } else if (val == 'custom') {
                  _pickCustomRange(context);
                } else if (val == 'all') {
                  onChanged(FinancialPeriodSelection.all());
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'current',
                  child: Text(
                    'Mês atual (${formatMonthYearBr(now ?? DateTime.now())})',
                  ),
                ),
                if (showOverdue) ...[
                  const PopupMenuItem(
                    value: 'next7',
                    child: Text('Próximos 7 dias'),
                  ),
                  const PopupMenuItem(
                    value: 'next30',
                    child: Text('Próximos 30 dias'),
                  ),
                  PopupMenuItem(
                    value: 'overdue',
                    child: Text(
                      overdueCount > 0
                          ? 'Vencidas ($overdueCount)'
                          : 'Vencidas',
                    ),
                  ),
                ] else ...[
                  const PopupMenuItem(
                    value: 'last7',
                    child: Text('Últimos 7 dias'),
                  ),
                  const PopupMenuItem(
                    value: 'last30',
                    child: Text('Últimos 30 dias'),
                  ),
                ],
                const PopupMenuItem(
                  value: 'custom',
                  child: Text('Intervalo personalizado...'),
                ),
                const PopupMenuItem(
                  value: 'all',
                  child: Text('Todos os períodos'),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      selection.type == FinancialPeriodType.overdue
                          ? Icons.warning_amber_rounded
                          : (selection.type == FinancialPeriodType.all
                                ? Icons.all_inclusive_rounded
                                : (selection.type == FinancialPeriodType.custom
                                      ? Icons.date_range_rounded
                                      : Icons.calendar_today_rounded)),
                      size: 16,
                      color: selection.type == FinancialPeriodType.overdue
                          ? AppTokens.expense
                          : theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        selection.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: selection.type == FinancialPeriodType.overdue
                              ? AppTokens.expense
                              : theme.colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Botão Próximo (>)
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, size: 22),
            onPressed: isMonth
                ? () => onChanged(selection.nextMonth())
                : () => onChanged(FinancialPeriodSelection.currentMonth(now)),
            tooltip: isMonth ? 'Próximo mês' : 'Voltar ao mês atual',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// Banner de alerta e ação rápida para contas vencidas fora do período visualizado.
class FinancialOverdueBanner extends StatelessWidget {
  const FinancialOverdueBanner({
    super.key,
    required this.overdueCount,
    required this.onViewOverdue,
    this.isOverdueMode = false,
    this.onReturnToMonth,
  });

  final int overdueCount;
  final VoidCallback onViewOverdue;
  final bool isOverdueMode;
  final VoidCallback? onReturnToMonth;

  @override
  Widget build(BuildContext context) {
    if (overdueCount == 0 && !isOverdueMode) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (isOverdueMode) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppTokens.expense.withValues(alpha: isDark ? 0.18 : 0.08),
          borderRadius: BorderRadius.circular(AppTokens.r12),
          border: Border.all(color: AppTokens.expense.withValues(alpha: 0.35)),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 20,
                  color: AppTokens.expense,
                ),
                Text(
                  'Exibindo contas vencidas em aberto.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTokens.expense,
                  ),
                ),
              ],
            ),
            if (onReturnToMonth != null)
              FilledButton.tonal(
                onPressed: onReturnToMonth,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
                child: const Text('Voltar ao mês'),
              ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTokens.warning.withValues(alpha: isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(AppTokens.r12),
        border: Border.all(color: AppTokens.warning.withValues(alpha: 0.4)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 20,
                color: AppTokens.warning,
              ),
              Text(
                overdueCount == 1
                    ? '1 conta vencida fora deste mês.'
                    : '$overdueCount contas vencidas fora deste mês.',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          FilledButton.tonal(
            onPressed: onViewOverdue,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            child: const Text('Ver vencidas'),
          ),
        ],
      ),
    );
  }
}
