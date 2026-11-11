import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/text_formatters.dart';
import '../../ui/app_tokens.dart';
import '../../ui/widgets.dart';
import '../accounts/account.dart';
import '../accounts/accounts_repository.dart';
import '../auth/auth_models.dart';
import '../categories/categories_repository.dart';
import '../categories/category.dart';
import 'planning_models.dart';
import 'planning_repository.dart';

class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key, required this.space, this.repository});

  final Space space;
  final PlanningRepository? repository;

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen> {
  late final PlanningRepository _repo =
      widget.repository ?? PlanningRepository(context.read<ApiClient>());

  int _selectedDays = 30;
  String _selectedView = 'cash'; // 'cash' ou 'accrual'
  int? _selectedAccountId;
  int? _selectedCategoryId;

  bool _loading = true;
  String? _errorMessage;
  CashFlowResponse? _response;

  List<Account> _accounts = [];
  List<Category> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final accountsRepo = context.read<AccountsRepository?>();
      final categoriesRepo = context.read<CategoriesRepository?>();

      if (accountsRepo != null) {
        _accounts = await accountsRepo.list(widget.space.id);
      }
      if (categoriesRepo != null) {
        _categories = await categoriesRepo.list(widget.space.id);
      }
    } catch (_) {
      // Ignora erro no carregamento de filtros secundários
    }
    await _loadPlanning();
  }

  Future<void> _loadPlanning() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final res = await _repo.fetchCashFlow(
        spaceId: widget.space.id,
        days: _selectedDays,
        view: _selectedView,
        accountId: _selectedAccountId,
        categoryId: _selectedCategoryId,
      );
      if (mounted) {
        setState(() {
          _response = res;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e is ApiException
              ? e.message
              : 'Falha ao carregar planejamento financeiro.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = widget.space.isPf
        ? const Color(0xFF1E5BB8)
        : const Color(0xFF0F8A5F);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Planejamento e Fluxo de Caixa'),
        actions: [
          if (widget.space.canExport)
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              tooltip: 'Exportar Fluxo de Caixa (CSV)',
              onPressed: _exportCsv,
            )
          else
            const Tooltip(
              message: 'Perfil de operador não possui alçada para exportar relatórios.',
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 20,
                  color: AppTokens.neutral,
                ),
              ),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: RefreshIndicator(
            onRefresh: _loadPlanning,
            child: ListView(
              padding: const EdgeInsets.all(AppTokens.p16),
              children: [
                SpaceBadge(widget.space, prefix: 'Planejamento no espaço'),
                const SizedBox(height: 16),

                // Controles de Filtros e Período
                _buildFiltersCard(theme, primaryColor),
                const SizedBox(height: 16),

                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_errorMessage != null)
                  _buildErrorView(theme)
                else if (_response == null || _response!.daily.isEmpty)
                  _buildEmptyView(theme)
                else ...[
                  // Cards Executivos de Resumo
                  _buildSummaryCards(theme, _response!, primaryColor),
                  const SizedBox(height: 20),

                  // Tabela / Timeline Diária
                  _buildDailyTimeline(theme, _response!, primaryColor),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFiltersCard(ThemeData theme, Color primaryColor) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.r12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.p14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: AppTokens.neutral,
                ),
                const SizedBox(width: 8),
                Text(
                  'Filtros e Projeção',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Seletores: Dias e Visão
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Período
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Período: ',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    for (final days in [30, 60, 90])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text('$days dias'),
                          selected: _selectedDays == days,
                          onSelected: (val) {
                            if (val) {
                              setState(() => _selectedDays = days);
                              _loadPlanning();
                            }
                          },
                        ),
                      ),
                  ],
                ),

                // Visão (Caixa vs Competência)
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'cash', label: Text('Visão de Caixa')),
                    ButtonSegment(
                      value: 'accrual',
                      label: Text('Visão de Competência'),
                    ),
                  ],
                  selected: {_selectedView},
                  onSelectionChanged: (val) {
                    setState(() => _selectedView = val.first);
                    _loadPlanning();
                  },
                ),
              ],
            ),

            if (_accounts.isNotEmpty || _categories.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (_accounts.isNotEmpty)
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        initialValue: _selectedAccountId,
                        decoration: InputDecoration(
                          labelText: 'Conta Bancária',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppTokens.r8),
                          ),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Todas as contas'),
                          ),
                          for (final acc in _accounts)
                            DropdownMenuItem(
                              value: acc.id,
                              child: Text(
                                toFinancialUpper(acc.name),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (val) {
                          setState(() => _selectedAccountId = val);
                          _loadPlanning();
                        },
                      ),
                    ),
                  if (_accounts.isNotEmpty && _categories.isNotEmpty)
                    const SizedBox(width: 12),
                  if (_categories.isNotEmpty)
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        initialValue: _selectedCategoryId,
                        decoration: InputDecoration(
                          labelText: 'Categoria',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppTokens.r8),
                          ),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Todas as categorias'),
                          ),
                          for (final cat in _categories)
                            DropdownMenuItem(
                              value: cat.id,
                              child: Text(
                                toFinancialUpper(cat.name),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (val) {
                          setState(() => _selectedCategoryId = val);
                          _loadPlanning();
                        },
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(
    ThemeData theme,
    CashFlowResponse response,
    Color primaryColor,
  ) {
    final s = response.summary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;
        final cardWidth = isWide
            ? (constraints.maxWidth - 24) / 3
            : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            // Saldo Inicial
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                title: 'Saldo Inicial do Período',
                amount: response.initialBalance.brl,
                subtitle: 'Data base: ${formatDateBr(response.startDate)}',
                color: theme.colorScheme.onSurface,
              ),
            ),

            // Entradas Realizadas e Previstas
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                title: 'Entradas (Realizadas / Previstas)',
                amount: s.realizedInflow.brl,
                subtitle: 'Previsto a receber: ${s.projectedInflow.brl}',
                color: AppTokens.income,
                icon: Icons.trending_up_rounded,
              ),
            ),

            // Saídas Realizadas e Previstas
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                title: 'Saídas (Realizadas / Previstas)',
                amount: s.realizedOutflow.brl,
                subtitle: 'Previsto a pagar: ${s.projectedOutflow.brl}',
                color: AppTokens.expense,
                icon: Icons.trending_down_rounded,
              ),
            ),

            // Saldo Final Projetado
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                title: 'Saldo Final Projetado',
                amount: s.finalProjectedBalance.brl,
                subtitle: 'Ao término de ${response.periodDays} dias',
                color: primaryColor,
                highlight: true,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDailyTimeline(
    ThemeData theme,
    CashFlowResponse response,
    Color primaryColor,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.r12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.p16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Projeção Diária de Caixa (${response.daily.length} dias)',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),

            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: response.daily.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, indent: 12, endIndent: 12),
              itemBuilder: (context, index) {
                final day = response.daily[index];
                final hasMovement =
                    day.realizedInflow.cents > 0 ||
                    day.realizedOutflow.cents > 0 ||
                    day.projectedInflow.cents > 0 ||
                    day.projectedOutflow.cents > 0;

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  child: Row(
                    children: [
                      // Data
                      SizedBox(
                        width: 90,
                        child: Text(
                          formatDateBr(day.date),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),

                      // Movimentação do Dia
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (hasMovement) ...[
                              if (day.realizedInflow.cents > 0)
                                Text(
                                  '+${day.realizedInflow.brl} realizado',
                                  style: const TextStyle(
                                    color: AppTokens.income,
                                    fontSize: 12,
                                  ),
                                ),
                              if (day.projectedInflow.cents > 0)
                                Text(
                                  '+${day.projectedInflow.brl} previsto',
                                  style: TextStyle(
                                    color: AppTokens.income.withValues(
                                      alpha: 0.8,
                                    ),
                                    fontSize: 12,
                                  ),
                                ),
                              if (day.realizedOutflow.cents > 0)
                                Text(
                                  '-${day.realizedOutflow.brl} realizado',
                                  style: const TextStyle(
                                    color: AppTokens.expense,
                                    fontSize: 12,
                                  ),
                                ),
                              if (day.projectedOutflow.cents > 0)
                                Text(
                                  '-${day.projectedOutflow.brl} previsto',
                                  style: TextStyle(
                                    color: AppTokens.expense.withValues(
                                      alpha: 0.8,
                                    ),
                                    fontSize: 12,
                                  ),
                                ),
                            ] else
                              const Text(
                                'Sem lançamentos',
                                style: TextStyle(
                                  color: AppTokens.neutral,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Saldo Projetado
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Saldo projetado',
                            style: TextStyle(
                              color: AppTokens.neutral,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            day.projectedBalance.brl,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: day.projectedBalance.cents < 0
                                  ? AppTokens.expense
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.p32),
        child: Column(
          children: [
            const Icon(
              Icons.analytics_outlined,
              size: 48,
              color: AppTokens.neutral,
            ),
            const SizedBox(height: 8),
            Text(
              'Nenhum dado encontrado para o período selecionado.',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.p24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: AppTokens.expense,
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Erro inesperado.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadPlanning,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  void _exportCsv() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Exportando fluxo de caixa em formato CSV auditável...'),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.amount,
    required this.subtitle,
    required this.color,
    this.icon,
    this.highlight = false,
  });

  final String title;
  final String amount;
  final String subtitle;
  final Color color;
  final IconData? icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: highlight ? color.withValues(alpha: 0.08) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.r12),
        side: BorderSide(
          color: highlight
              ? color.withValues(alpha: 0.3)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.p14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: AppTokens.neutral,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              amount,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: AppTokens.neutral, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
