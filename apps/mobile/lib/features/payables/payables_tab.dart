import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/text_formatters.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../../ui/financial/financial_agenda_view.dart';
import '../../ui/financial/financial_item_view.dart';
import '../../ui/financial/financial_search_bar.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import '../categories/category_badge.dart';
import '../categories/category_filter_chip.dart';
import '../settings/preferences_controller.dart';
import 'cards_screen.dart';
import 'batch_payable_modal.dart';
import 'payable.dart';
import 'payable_creations.dart';
import 'payable_form_screen.dart';
import 'payable_item_adapter.dart';
import 'payable_modal.dart';
import 'payables_repository.dart';
import 'pending_creation_card.dart';

/// Obrigações a pagar do espaço, com filtro por situação. Cadastrar não
/// altera saldo: só pagamentos movimentam contas.
class PayablesTab extends StatefulWidget {
  const PayablesTab({
    super.key,
    required this.space,
    this.initialFilter = 'open',
  });

  final Space space;
  final String initialFilter;

  @override
  State<PayablesTab> createState() => _PayablesTabState();
}

class _PayablesTabState extends State<PayablesTab> {
  static const _filters = {
    'open': 'Em aberto',
    'overdue': 'Vencidas',
    'awaiting_amount': 'Valor a informar',
    'paid': 'Pagas',
    'cancelled': 'Canceladas',
    'all': 'Todas',
  };

  late String _filter = widget.initialFilter;
  int? _selectedCategoryId;
  PendingCreation? _pending;
  bool _selectionMode = false;
  final Set<int> _selectedPayableIds = {};
  String _searchQuery = '';
  FinancialSortOption _sortOption = FinancialSortOption.dueDateAsc;
  FinancialPeriodFilter _periodFilter = FinancialPeriodFilter.all;
  final Set<FinancialDueDateGroup> _expandedGroups = {
    FinancialDueDateGroup.overdue,
    FinancialDueDateGroup.today,
    FinancialDueDateGroup.next7Days,
    FinancialDueDateGroup.thisMonth,
    FinancialDueDateGroup.future,
  };

  bool _isEligible(Payable p) =>
      p.status != PayableStatus.paid &&
      p.status != PayableStatus.cancelled &&
      p.remaining != null &&
      p.remaining!.cents > 0;

  Money _totalSelected(List<Payable> items) {
    final selected = items.where((p) => _selectedPayableIds.contains(p.id));
    return Money(
      selected.fold<int>(0, (sum, p) => sum + (p.remaining?.cents ?? 0)),
    );
  }

  void _toggleSelect(int payableId) {
    setState(() {
      if (_selectedPayableIds.contains(payableId)) {
        _selectedPayableIds.remove(payableId);
        if (_selectedPayableIds.isEmpty && !_selectionMode) {
          _selectionMode = false;
        }
      } else {
        _selectedPayableIds.add(payableId);
      }
    });
  }

  void _toggleSelectAll(List<Payable> eligible) {
    setState(() {
      if (_selectedPayableIds.length == eligible.length) {
        _selectedPayableIds.clear();
      } else {
        _selectedPayableIds.clear();
        _selectedPayableIds.addAll(eligible.map((p) => p.id));
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPending());
  }

  /// Cadastro sem confirmação deste usuário e espaço; não bloqueia pagamentos.
  Future<void> _loadPending() async {
    final user = context.read<SessionController>().user;
    final pending = user == null
        ? null
        : await context.read<PayableCreations>().pending(
            user.id,
            widget.space.id,
          );
    if (mounted) setState(() => _pending = pending);
  }

  @override
  Widget build(BuildContext context) {
    final space = widget.space;
    final pending = _pending;
    final textScaler = MediaQuery.textScalerOf(context);
    final chipsHeight = (44.0 * textScaler.scale(1.0) + 8.0).clamp(52.0, 96.0);

    return Column(
      children: [
        if (pending != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.p16,
              AppTokens.p8,
              AppTokens.p16,
              0,
            ),
            child: PendingCreationCard(
              key: ValueKey(pending.idempotencyKey),
              pending: pending,
              onSettled: (outcome) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(outcome.message)));
                setState(() => _pending = null);
                context.read<SessionController>().dataChanged();
              },
            ),
          ),
        // Cabeçalho da aba A pagar com ação principal (layout adaptativo)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.p16,
            AppTokens.p12,
            AppTokens.p16,
            0,
          ),
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppTokens.p12,
              runSpacing: AppTokens.p8,
              children: [
                Text(
                  'A pagar',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => showPayableFormModal(context, space: space),
                  icon: const AppIcon(AppIcons.add, size: 18),
                  label: const Text('Nova conta a pagar'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: chipsHeight,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.p16,
              vertical: 6,
            ),
            children: [
              for (final MapEntry(key: value, value: label) in _filters.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _filter == value,
                    onSelected: (_) => setState(() => _filter = value),
                  ),
                ),
              CategoryFilterChip(
                spaceId: space.id,
                type: 'expense',
                selectedCategoryId: _selectedCategoryId,
                onChanged: (catId) =>
                    setState(() => _selectedCategoryId = catId),
              ),
              ActionChip(
                avatar: const AppIcon(AppIcons.card, size: 16),
                label: const Text('Cartões e recorrências'),
                onPressed: () => Navigator.of(context).push(
                  spaceRoute(
                    isPf: space.isPf,
                    child: CardsScreen(space: space),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LoadView<List<Payable>>(
            key: ValueKey('payables-$_filter-$_selectedCategoryId'),
            load: () => context.read<PayablesRepository>().list(
              space.id,
              status: _filter,
              categoryId: _selectedCategoryId,
            ),
            isEmpty: (items) => items.isEmpty,
            empty: (context, _) => EmptyState(
              icon: AppIcons.payables,
              title: 'Nada em "${_filters[_filter]}"',
              message:
                  'Cadastre contas a pagar avulsas, parceladas ou recorrentes. '
                  'Faturas de cartão aparecem com valor a informar.',
            ),
            builder: (context, items, refresh) {
              final eligibleItems = items.where(_isEligible).toList();
              final isSelectionActive =
                  _selectionMode || _selectedPayableIds.isNotEmpty;
              final isDesktop = MediaQuery.sizeOf(context).width >= 840;

              final adapters = items.map(PayableItemAdapter.new).toList();
              final filteredAdapters = filterAndSortFinancialItems(
                adapters,
                query: _searchQuery,
                sort: _sortOption,
                period: _periodFilter,
                categoryId: _selectedCategoryId,
              );

              return Stack(
                children: [
                  RefreshIndicator(
                    onRefresh: refresh,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1040),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppTokens.p16,
                            4,
                            AppTokens.p16,
                            0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      items.length == 1
                                          ? '1 conta a pagar'
                                          : '${items.length} contas a pagar',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                    if (eligibleItems.isNotEmpty) ...[
                                      if (!isSelectionActive)
                                        TextButton.icon(
                                          onPressed: () => setState(
                                            () => _selectionMode = true,
                                          ),
                                          icon: const Icon(
                                            Icons.checklist_rounded,
                                            size: 16,
                                          ),
                                          label: const Text(
                                            'Selecionar várias',
                                          ),
                                          style: TextButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                          ),
                                        )
                                      else
                                        Wrap(
                                          spacing: 4,
                                          children: [
                                            TextButton(
                                              onPressed: () => _toggleSelectAll(
                                                eligibleItems,
                                              ),
                                              style: TextButton.styleFrom(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                    ),
                                              ),
                                              child: Text(
                                                _selectedPayableIds.length ==
                                                        eligibleItems.length
                                                    ? 'Desmarcar todas'
                                                    : 'Selecionar todas',
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () => setState(() {
                                                _selectionMode = false;
                                                _selectedPayableIds.clear();
                                              }),
                                              style: TextButton.styleFrom(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                    ),
                                              ),
                                              child: const Text('Cancelar'),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: FinancialSearchBar(
                                  query: _searchQuery,
                                  onQueryChanged: (q) =>
                                      setState(() => _searchQuery = q),
                                  sort: _sortOption,
                                  onSortChanged: (s) =>
                                      setState(() => _sortOption = s),
                                  hintText:
                                      'Buscar por descrição ou favorecido...',
                                  activeFiltersCount:
                                      (_searchQuery.isNotEmpty ? 1 : 0) +
                                      (_filter != 'open' ? 1 : 0) +
                                      (_periodFilter !=
                                              FinancialPeriodFilter.all
                                          ? 1
                                          : 0) +
                                      (_selectedCategoryId != null ? 1 : 0),
                                  onOpenFilters: () =>
                                      showFinancialFiltersSheet(
                                        context: context,
                                        currentStatus: _filter,
                                        statusOptions: _filters,
                                        onStatusSelected: (s) =>
                                            setState(() => _filter = s),
                                        currentPeriod: _periodFilter,
                                        onPeriodSelected: (p) =>
                                            setState(() => _periodFilter = p),
                                        currentCategoryId: _selectedCategoryId,
                                        onCategorySelected: (c) => setState(
                                          () => _selectedCategoryId = c,
                                        ),
                                        spaceId: space.id,
                                        categoryType: 'expense',
                                        onClearAll: () => setState(() {
                                          _filter = 'open';
                                          _periodFilter =
                                              FinancialPeriodFilter.all;
                                          _selectedCategoryId = null;
                                        }),
                                      ),
                                  activeFilterChips: [
                                    if (_filter != 'open')
                                      InputChip(
                                        label: Text(
                                          'Situação: ${_filters[_filter] ?? _filter}',
                                        ),
                                        onDeleted: () =>
                                            setState(() => _filter = 'open'),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    if (_periodFilter !=
                                        FinancialPeriodFilter.all)
                                      InputChip(
                                        label: Text(
                                          'Período: ${_periodFilter.label}',
                                        ),
                                        onDeleted: () => setState(
                                          () => _periodFilter =
                                              FinancialPeriodFilter.all,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    if (_selectedCategoryId != null)
                                      InputChip(
                                        label: const Text('Categoria filtrada'),
                                        onDeleted: () => setState(
                                          () => _selectedCategoryId = null,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                  ],
                                  onClearAllFilters: () => setState(() {
                                    _searchQuery = '';
                                    _filter = 'open';
                                    _periodFilter = FinancialPeriodFilter.all;
                                    _selectedCategoryId = null;
                                    _sortOption =
                                        FinancialSortOption.dueDateAsc;
                                  }),
                                ),
                              ),
                              Expanded(
                                child: FinancialAgendaView<PayableItemAdapter>(
                                  items: filteredAdapters,
                                  isDesktop: isDesktop,
                                  expandedGroups: _expandedGroups,
                                  onToggleGroup: (group) => setState(() {
                                    if (_expandedGroups.contains(group)) {
                                      _expandedGroups.remove(group);
                                    } else {
                                      _expandedGroups.add(group);
                                    }
                                  }),
                                  isSelectionActive: isSelectionActive,
                                  selectedIds: _selectedPayableIds,
                                  onToggleSelect: _toggleSelect,
                                  onTapItem: (adapter) => showPayableModal(
                                    context,
                                    space: space,
                                    payableId: adapter.payable.id,
                                    onUpdated: refresh,
                                  ),
                                  quickActionLabel: 'Pagar',
                                  isQuickActionEnabled: (adapter) =>
                                      adapter.payable.canPay,
                                  onQuickAction: (adapter) => showPayableModal(
                                    context,
                                    space: space,
                                    payableId: adapter.payable.id,
                                    onUpdated: refresh,
                                  ),
                                  singularLabel: 'conta a pagar',
                                  pluralLabel: 'contas a pagar',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Barra flutuante de pagamento em lote
                  if (_selectedPayableIds.isNotEmpty)
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600),
                          child: Material(
                            elevation: 8,
                            shadowColor: Colors.black54,
                            borderRadius: BorderRadius.circular(AppTokens.r16),
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHigh,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${_selectedPayableIds.length} selecionadas',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                      Text(
                                        _totalSelected(items).brl,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error,
                                            ),
                                      ),
                                    ],
                                  ),
                                  FilledButton.icon(
                                    onPressed: () {
                                      final selectedList = items
                                          .where(
                                            (p) => _selectedPayableIds.contains(
                                              p.id,
                                            ),
                                          )
                                          .toList();
                                      showBatchPayableModal(
                                        context,
                                        space: space,
                                        payables: selectedList,
                                        onCompleted: () {
                                          setState(() {
                                            _selectedPayableIds.clear();
                                            _selectionMode = false;
                                          });
                                          refresh();
                                        },
                                      );
                                    },
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .error,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          AppTokens.r12,
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.playlist_add_check_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      'Pagar selecionadas (${_selectedPayableIds.length})',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class PayableCard extends StatelessWidget {
  const PayableCard({
    super.key,
    required this.space,
    required this.payable,
    this.isSelectable = false,
    this.isSelected = false,
    this.onToggleSelect,
    this.onTap,
  });

  final Space space;
  final Payable payable;
  final bool isSelectable;
  final bool isSelected;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final obscure =
        context.watch<PreferencesController?>()?.obscureValues ?? false;
    final isAwaiting =
        payable.status == PayableStatus.awaitingAmount ||
        payable.remaining == null;
    final isPaid = payable.status == PayableStatus.paid;
    final isCancelled = payable.status == PayableStatus.cancelled;
    final isPartial = payable.status == PayableStatus.partial;

    return Card(
      key: ValueKey('payable-${payable.id}'),
      clipBehavior: Clip.antiAlias,
      shape: isSelected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.r16),
              side: BorderSide(color: theme.colorScheme.error, width: 1.5),
            )
          : null,
      child: InkWell(
        onTap: isSelectable ? onToggleSelect : onTap,
        borderRadius: BorderRadius.circular(AppTokens.r16),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.p16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isSelectable)
                Padding(
                  padding: const EdgeInsets.only(right: 12, top: 2),
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => onToggleSelect?.call(),
                    visualDensity: VisualDensity.compact,
                    activeColor: theme.colorScheme.error,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Linha Superior: Descrição e StatusChip alinhados
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                toFinancialUpper(payable.description),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${payable.kindLabel} · vence ${formatDateBr(payable.dueDate)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (payable.payee != null &&
                                  payable.payee!.trim().isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  toFinancialUpper(payable.payee!),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.8),
                                    fontSize: 11,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              if (payable.category != null) ...[
                                const SizedBox(height: 6),
                                CategoryBadge(
                                  category: payable.category!,
                                  compact: true,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        payableStatusChip(payable),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Bloco de Valores com destaque fintech adaptativo com Wrap
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.start,
                      spacing: AppTokens.p16,
                      runSpacing: AppTokens.p8,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isPaid
                                  ? 'Total pago'
                                  : isCancelled
                                  ? 'Valor cancelado'
                                  : 'Restante a pagar',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: payable.overdue
                                    ? AppTokens.expense
                                    : theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            if (isAwaiting)
                              Text(
                                'Valor a informar',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppTokens.warning,
                                  letterSpacing: -0.2,
                                ),
                              )
                            else
                              MoneyText(
                                isPaid
                                    ? payable.paid
                                    : (payable.remaining ??
                                          payable.amount ??
                                          const Money(0)),
                                obscure: obscure,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                  color: payable.overdue
                                      ? AppTokens.expense
                                      : null,
                                ),
                              ),
                          ],
                        ),
                        if (isPartial && payable.amount != null) ...[
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pago líquido',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              MoneyText(
                                payable.paid,
                                obscure: obscure,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppTokens.income,
                                ),
                              ),
                            ],
                          ),
                        ] else if (!isPaid &&
                            !isCancelled &&
                            payable.amount != null &&
                            !isAwaiting) ...[
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Valor total',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              MoneyText(
                                payable.amount!,
                                obscure: obscure,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
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

/// Situação com vencimento: parcial e vencida podem coexistir.
Widget payableStatusChip(Payable payable) => StatusChip(
  label: payable.overdue
      ? (payable.status == PayableStatus.partial
            ? 'Parcial · vencida'
            : 'Vencida')
      : payable.status.label,
  tone: switch (payable.status) {
    _ when payable.overdue => StatusTone.danger,
    PayableStatus.paid => StatusTone.success,
    PayableStatus.partial || PayableStatus.awaitingAmount => StatusTone.warning,
    _ => StatusTone.neutral,
  },
);
