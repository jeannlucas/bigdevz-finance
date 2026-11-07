import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../accounts/account.dart';
import '../accounts/accounts_repository.dart';
import '../auth/auth_models.dart';
import '../categories/category_badge.dart';
import '../settings/preferences_controller.dart';
import 'statement_entry.dart';
import 'statement_repository.dart';

class StatementTab extends StatefulWidget {
  const StatementTab({super.key, required this.space});

  final Space space;

  @override
  State<StatementTab> createState() => _StatementTabState();
}

class _StatementTabState extends State<StatementTab> {
  bool _loading = true;
  String? _error;
  List<StatementEntry> _entries = [];
  List<Account> _accounts = [];

  int? _selectedAccountId;
  String _selectedDirection = 'all'; // 'all', 'credit', 'debit'

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StatementTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.space.id != widget.space.id) {
      _selectedAccountId = null;
      _selectedDirection = 'all';
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final accountsRepo = context.read<AccountsRepository>();
      final statementRepo = context.read<StatementRepository>();

      final accountsFuture = accountsRepo.list(widget.space.id);
      final statementFuture = statementRepo.list(
        widget.space.id,
        accountId: _selectedAccountId,
        direction: _selectedDirection == 'all' ? null : _selectedDirection,
      );

      final results = await Future.wait([accountsFuture, statementFuture]);
      if (!mounted) return;

      setState(() {
        _accounts = results[0] as List<Account>;
        _entries = results[1] as List<StatementEntry>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Não foi possível carregar o extrato.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<PreferencesController?>();
    final obscure = preferences?.obscureValues ?? false;
    final theme = Theme.of(context);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.p16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Extrato',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        if (_loading)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.p12),
                    _buildFilters(theme),
                    if (!_loading && _error == null) ...[
                      const SizedBox(height: AppTokens.p16),
                      _buildSummaryCard(theme, obscure),
                    ],
                  ],
                ),
              ),
            ),
            if (_loading && _entries.isEmpty)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: AppTokens.p12),
                      FilledButton.tonal(
                        onPressed: _load,
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_entries.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        AppIcons.receipt,
                        size: 48,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: AppTokens.p12),
                      Text(
                        'Nenhuma movimentação encontrada',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.p16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final entry = _entries[index];
                    return _StatementTile(entry: entry, obscure: obscure);
                  }, childCount: _entries.length),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(ThemeData theme) {
    return Wrap(
      spacing: AppTokens.p8,
      runSpacing: AppTokens.p8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Filtro de Direção (Segmented ou Chips)
        ChoiceChip(
          label: const Text('Todos'),
          selected: _selectedDirection == 'all',
          onSelected: (selected) {
            if (selected) {
              setState(() => _selectedDirection = 'all');
              _load();
            }
          },
        ),
        ChoiceChip(
          avatar: const Icon(
            Icons.arrow_downward,
            size: 14,
            color: AppTokens.income,
          ),
          label: const Text('Entradas'),
          selected: _selectedDirection == 'credit',
          onSelected: (selected) {
            if (selected) {
              setState(() => _selectedDirection = 'credit');
              _load();
            }
          },
        ),
        ChoiceChip(
          avatar: const Icon(
            Icons.arrow_upward,
            size: 14,
            color: AppTokens.expense,
          ),
          label: const Text('Saídas'),
          selected: _selectedDirection == 'debit',
          onSelected: (selected) {
            if (selected) {
              setState(() => _selectedDirection = 'debit');
              _load();
            }
          },
        ),
        if (_accounts.isNotEmpty)
          DropdownButtonHideUnderline(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(AppTokens.r8),
              ),
              child: DropdownButton<int?>(
                value: _selectedAccountId,
                hint: const Text('Todas as contas'),
                isDense: true,
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Todas as contas'),
                  ),
                  for (final acc in _accounts)
                    DropdownMenuItem<int?>(
                      value: acc.id,
                      child: Text(acc.name),
                    ),
                ],
                onChanged: (accId) {
                  setState(() => _selectedAccountId = accId);
                  _load();
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSummaryCard(ThemeData theme, bool obscure) {
    int totalCreditCents = 0;
    int totalDebitCents = 0;

    for (final entry in _entries) {
      if (entry.direction.isCredit) {
        totalCreditCents += entry.amount.cents;
      } else {
        totalDebitCents += entry.amount.cents;
      }
    }

    final netCents = totalCreditCents - totalDebitCents;
    final netMoney = Money(netCents.abs());

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.r12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.p16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Entradas',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    obscure ? 'R\$ ••••••••' : Money(totalCreditCents).brl,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTokens.income,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 36,
              width: 1,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(width: AppTokens.p16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Saídas',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    obscure ? 'R\$ ••••••••' : Money(totalDebitCents).brl,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTokens.expense,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 36,
              width: 1,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(width: AppTokens.p16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Líquido',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    obscure
                        ? 'R\$ ••••••••'
                        : '${netCents < 0 ? '-' : '+'} ${netMoney.brl}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: netCents < 0
                          ? AppTokens.expense
                          : AppTokens.income,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatementTile extends StatelessWidget {
  const _StatementTile({required this.entry, required this.obscure});

  final StatementEntry entry;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCredit = entry.direction.isCredit;

    final sign = isCredit ? '+' : '-';
    final color = isCredit ? AppTokens.income : AppTokens.expense;

    final formattedValue = obscure
        ? '$sign R\$ ••••••••'
        : '$sign ${entry.amount.brl}';

    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.p8),
      padding: const EdgeInsets.all(AppTokens.p12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTokens.r12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(
              isCredit
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: AppTokens.p12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.accountName} • ${entry.effectiveDate}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (entry.category != null) ...[
                  const SizedBox(height: 4),
                  CategoryBadge(category: entry.category!, compact: true),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppTokens.p8),
          Semantics(
            label: isCredit
                ? 'Entrada de ${entry.amount.brl}'
                : 'Saída de ${entry.amount.brl}',
            child: Text(
              formattedValue,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
