import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import 'agreement.dart';
import 'agreement_form_screen.dart';
import 'agreement_screen.dart';
import 'agreements_repository.dart';

class AgreementsTab extends StatefulWidget {
  const AgreementsTab({
    super.key,
    required this.space,
    this.initialFilter = 'open',
  });

  final Space space;
  final String initialFilter;

  @override
  State<AgreementsTab> createState() => _AgreementsTabState();
}

class _AgreementsTabState extends State<AgreementsTab> {
  static const _filters = {
    'open': 'Em aberto',
    'overdue': 'Vencidas',
    'today': 'Hoje',
    'next_30_days': 'Próximos 30 dias',
    'paid': 'Recebidas',
    'all': 'Todas',
  };

  final ScrollController _chipsScrollController = ScrollController();
  final Map<String, GlobalKey> _chipKeys = {
    for (final key in _filters.keys) key: GlobalKey(),
  };

  late String _filter;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
    _chipsScrollController.addListener(_updateScrollIndicators);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollIndicators();
      _ensureSelectedChipVisible();
    });
  }

  @override
  void didUpdateWidget(covariant AgreementsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialFilter != oldWidget.initialFilter) {
      setState(() => _filter = widget.initialFilter);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureSelectedChipVisible();
      });
    }
  }

  @override
  void dispose() {
    _chipsScrollController.removeListener(_updateScrollIndicators);
    _chipsScrollController.dispose();
    super.dispose();
  }

  void _updateScrollIndicators() {
    if (!_chipsScrollController.hasClients) return;
    final position = _chipsScrollController.position;
    final canLeft = position.pixels > 2;
    final canRight = position.pixels < (position.maxScrollExtent - 2);
    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      if (mounted) {
        setState(() {
          _canScrollLeft = canLeft;
          _canScrollRight = canRight;
        });
      }
    }
  }

  void _ensureSelectedChipVisible() {
    final key = _chipKeys[_filter];
    final currentContext = key?.currentContext;
    if (currentContext != null) {
      Scrollable.ensureVisible(
        currentContext,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
    }
  }

  void _selectFilter(String newFilter) {
    setState(() => _filter = newFilter);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureSelectedChipVisible();
    });
  }

  @override
  Widget build(BuildContext context) {
    final space = widget.space;
    final theme = Theme.of(context);
    final indicatorColor = theme.scaffoldBackgroundColor;

    return Column(
      children: [
        // Cabeçalho da aba Contas a receber com ação principal
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.p16,
            AppTokens.p12,
            AppTokens.p16,
            0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Contas a receber',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  spaceRoute(
                    isPf: space.isPf,
                    child: AgreementFormScreen(space: space),
                  ),
                ),
                icon: const AppIcon(AppIcons.add, size: 18),
                label: const Text('Nova conta a receber'),
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
        // Barra de filtros com ChoiceChip e indicador de rolagem fluído e sutil
        SizedBox(
          height: 52,
          child: Stack(
            children: [
              ListView(
                controller: _chipsScrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.p16,
                  vertical: 6,
                ),
                children: [
                  for (final MapEntry(key: value, value: label)
                      in _filters.entries)
                    Padding(
                      key: _chipKeys[value],
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _filter == value,
                        onSelected: (_) => _selectFilter(value),
                      ),
                    ),
                ],
              ),
              // Gradiente / seta sutil à esquerda
              if (_canScrollLeft)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      width: 28,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            indicatorColor,
                            indicatorColor.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.chevron_left_rounded,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ),
                ),
              // Gradiente / seta sutil à direita
              if (_canScrollRight)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      width: 28,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerRight,
                          end: Alignment.centerLeft,
                          colors: [
                            indicatorColor,
                            indicatorColor.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: LoadView<AgreementsListResult>(
            key: ValueKey('agreements-$_filter-${space.id}'),
            load: () => context.read<AgreementsRepository>().list(
              space.id,
              status: _filter,
            ),
            isEmpty: (result) => result.items.isEmpty,
            emptyWithData: (context, result, _) {
              if (result.totalCount == 0) {
                return const EmptyState(
                  icon: AppIcons.receivables,
                  title: 'Você ainda não tem contas a receber',
                  message: 'Cadastre sua primeira venda parcelada ou valor a receber para acompanhar vencimentos e entradas. Valores previstos não alteram o saldo bancário.',
                );
              }
              return EmptyState(
                icon: AppIcons.receivables,
                title: 'Nenhuma conta a receber neste filtro',
                message: 'Tente outro filtro ou consulte Todas.',
                action: OutlinedButton(
                  onPressed: () => _selectFilter('all'),
                  child: const Text('Ver todas'),
                ),
              );
            },
            builder: (context, result, refresh) {
              final agreements = result.items;
              return RefreshIndicator(
                onRefresh: refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.p16,
                    4,
                    AppTokens.p16,
                    96,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        agreements.length == 1
                            ? '1 conta a receber'
                            : '${agreements.length} contas a receber',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    for (final item in agreements) ...[
                      AgreementCard(
                        agreement: item,
                        activeFilter: _filter,
                        onTap: () => Navigator.of(context).push(
                          spaceRoute(
                            isPf: space.isPf,
                            child: AgreementScreen(
                              space: space,
                              agreementId: item.id,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class AgreementCard extends StatelessWidget {
  const AgreementCard({
    super.key,
    required this.agreement,
    this.activeFilter = 'open',
    this.onTap,
  });

  final Agreement agreement;
  final String activeFilter;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = agreement.total.cents == 0
        ? 0.0
        : (agreement.received.cents / agreement.total.cents).clamp(0.0, 1.0);

    final overdueCount = agreement.overdueInstallments;
    final overdueLabel = overdueCount == 1
        ? '1 vencida'
        : '$overdueCount vencidas';

    // Determina se devemos destacar um valor específico do filtro ativo:
    // Filtros: overdue (Vencido), today (A receber hoje), next_30_days (A receber no período)
    final filterMatchingInstallments = _matchingInstallments(
      agreement.installments,
      activeFilter,
    );
    final filterMatchingAmount = filterMatchingInstallments.fold<int>(
      0,
      (sum, inst) => sum + inst.remaining.cents,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.r16),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.p16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Linha do Título e Status compacto
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      agreement.description,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (overdueCount > 0)
                    StatusChip(label: overdueLabel, tone: StatusTone.danger)
                  else if (agreement.remaining.isZero)
                    const StatusChip(
                      label: 'Quitada',
                      tone: StatusTone.success,
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Bloco de Valores: Restante a receber como Herói principal
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _primaryValueLabel(activeFilter),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                activeFilter == 'overdue' &&
                                    filterMatchingAmount > 0
                                ? AppTokens.expense
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        MoneyText(
                          _primaryValue(
                            agreement,
                            activeFilter,
                            filterMatchingAmount,
                          ),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            color:
                                activeFilter == 'overdue' &&
                                    filterMatchingAmount > 0
                                ? AppTokens.expense
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _secondaryValueLabel(activeFilter),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      MoneyText(
                        _secondaryValue(agreement, activeFilter),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (_hasFilterSubset(activeFilter) &&
                  filterMatchingInstallments.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  _filterInstallmentMotivation(
                    activeFilter,
                    filterMatchingInstallments,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: activeFilter == 'overdue'
                        ? AppTokens.expense
                        : theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Barra de progresso do recebimento financeiro
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recebido: ${agreement.received.brl}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTokens.income,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        '${(progress * 100).toInt()}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        agreement.remaining.isZero
                            ? AppTokens.income
                            : theme.colorScheme.primary,
                      ),
                      semanticsLabel:
                          'Recebido da conta: ${agreement.received.brl}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Parcelas e próximo vencimento compactos
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '${agreement.paidInstallments} de ${agreement.installmentCount} parcelas pagas'
                      '${agreement.nextDueDate != null ? ' · próx. ${formatDateBr(agreement.nextDueDate!)}' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _hasFilterSubset(String filter) =>
      filter == 'overdue' || filter == 'today' || filter == 'next_30_days';

  static List<Installment> _matchingInstallments(
    List<Installment> installments,
    String filter,
  ) {
    if (installments.isEmpty) return const [];
    return switch (filter) {
      'overdue' =>
        installments.where((i) => i.overdue && !i.remaining.isZero).toList(),
      'today' => installments.where((i) {
        if (i.remaining.isZero) return false;
        // Hoje no fuso canônico da data de vencimento
        final today = toApiDate(DateTime.now());
        return i.dueDate == today;
      }).toList(),
      'next_30_days' => installments.where((i) {
        if (i.remaining.isZero) return false;
        final due = parseApiDate(i.dueDate);
        final now = DateUtils.dateOnly(DateTime.now());
        final tomorrow = now.add(const Duration(days: 1));
        final in30 = now.add(const Duration(days: 30));
        return !due.isBefore(tomorrow) && !due.isAfter(in30);
      }).toList(),
      _ => const [],
    };
  }

  static String _primaryValueLabel(String filter) => switch (filter) {
    'overdue' => 'Vencido no filtro',
    'today' => 'A receber hoje',
    'next_30_days' => 'A receber no período',
    _ => 'Restante a receber',
  };

  static Money _primaryValue(
    Agreement agreement,
    String filter,
    int filterAmount,
  ) {
    if (_hasFilterSubset(filter) && filterAmount > 0) {
      return Money(filterAmount);
    }
    return agreement.remaining;
  }

  static String _secondaryValueLabel(String filter) {
    if (_hasFilterSubset(filter)) return 'Restante total';
    return 'Valor total';
  }

  static Money _secondaryValue(Agreement agreement, String filter) {
    if (_hasFilterSubset(filter)) return agreement.remaining;
    return agreement.total;
  }

  static String _filterInstallmentMotivation(
    String filter,
    List<Installment> items,
  ) {
    final count = items.length;
    final numbers = items.map((i) => i.number).join(', ');
    return switch (filter) {
      'overdue' =>
        count == 1
            ? 'Parcela $numbers vencida'
            : '$count parcelas vencidas (parcelas $numbers)',
      'today' =>
        count == 1
            ? 'Parcela $numbers vence hoje'
            : '$count parcelas vencem hoje (parcelas $numbers)',
      'next_30_days' =>
        count == 1
            ? 'Parcela $numbers vence no período'
            : '$count parcelas vencem no período (parcelas $numbers)',
      _ => count == 1 ? 'Parcela $numbers' : '$count parcelas',
    };
  }
}
