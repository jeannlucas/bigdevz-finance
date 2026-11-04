import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import '../settings/preferences_controller.dart';
import 'loan.dart';
import 'loan_form_screen.dart';
import 'loans_repository.dart';

class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key, required this.space});

  final Space space;

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  String _kindFilter = 'all'; // all, taken, granted
  String _statusFilter = 'active'; // active, settled, all
  bool _loading = false;
  ApiException? _error;
  List<Loan> _loans = [];

  @override
  void initState() {
    super.initState();
    _loadLoans();
  }

  Future<void> _loadLoans() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<LoansRepository>().list(
        widget.space.id,
        kind: _kindFilter,
        status: _statusFilter,
      );
      if (!mounted) return;
      setState(() => _loans = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preferences = context.watch<PreferencesController>();
    final obscureValues = preferences.obscureValues;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Empréstimos'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const AppIcon(AppIcons.refresh),
            onPressed: _loading ? null : _loadLoans,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => LoanFormScreen(space: widget.space),
            ),
          );
          if (created == true) {
            _loadLoans();
          }
        },
        icon: const AppIcon(AppIcons.add, color: Colors.white),
        label: const Text(
          'Novo Empréstimo',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadLoans,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            _buildFilters(theme),
            const SizedBox(height: 12),
            if (_loading && _loans.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null && _loans.isEmpty)
              _buildErrorState(theme)
            else if (_loans.isEmpty)
              _buildEmptyState(theme)
            else ...[
              _buildSummaryHeader(theme, obscureValues),
              const SizedBox(height: 16),
              ..._loans.map(
                (loan) => _buildLoanCard(theme, loan, obscureValues),
              ),
            ],
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                label: const Text('Todos'),
                selected: _kindFilter == 'all',
                onSelected: (val) {
                  setState(() => _kindFilter = 'all');
                  _loadLoans();
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Tomados (Dívidas)'),
                selected: _kindFilter == 'taken',
                onSelected: (val) {
                  setState(() => _kindFilter = 'taken');
                  _loadLoans();
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Concedidos (A Receber)'),
                selected: _kindFilter == 'granted',
                onSelected: (val) {
                  setState(() => _kindFilter = 'granted');
                  _loadLoans();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('Ativos'),
                selected: _statusFilter == 'active',
                onSelected: (val) {
                  setState(() => _statusFilter = 'active');
                  _loadLoans();
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Quitados'),
                selected: _statusFilter == 'settled',
                onSelected: (val) {
                  setState(() => _statusFilter = 'settled');
                  _loadLoans();
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Ver Todos'),
                selected: _statusFilter == 'all',
                onSelected: (val) {
                  setState(() => _statusFilter = 'all');
                  _loadLoans();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryHeader(ThemeData theme, bool obscureValues) {
    var takenDebtCents = 0;
    var grantedReceivableCents = 0;

    for (final loan in _loans) {
      if (loan.isTaken) {
        takenDebtCents += loan.remaining.cents;
      } else {
        grantedReceivableCents += loan.remaining.cents;
      }
    }

    return Row(
      children: [
        Expanded(
          child: Card(
            elevation: 0,
            color: AppTokens.expense.withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppTokens.expense.withValues(alpha: 0.2)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Dívida Total (Tomados)',
                    style: TextStyle(fontSize: 12, color: AppTokens.neutral),
                  ),
                  const SizedBox(height: 4),
                  MoneyText(
                    Money(takenDebtCents),
                    obscure: obscureValues,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTokens.expense,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card(
            elevation: 0,
            color: AppTokens.income.withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppTokens.income.withValues(alpha: 0.2)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'A Receber (Concedidos)',
                    style: TextStyle(fontSize: 12, color: AppTokens.neutral),
                  ),
                  const SizedBox(height: 4),
                  MoneyText(
                    Money(grantedReceivableCents),
                    obscure: obscureValues,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTokens.income,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoanCard(ThemeData theme, Loan loan, bool obscureValues) {
    final isTaken = loan.isTaken;
    final badgeColor = isTaken ? AppTokens.expense : AppTokens.income;
    final badgeBg = badgeColor.withValues(alpha: 0.12);
    final badgeText = isTaken ? 'Tomado' : 'Concedido';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showLoanDetails(loan),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loan.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          loan.counterparty,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppTokens.neutral,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: badgeColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: loan.progress,
                backgroundColor: theme.dividerColor.withValues(alpha: 0.2),
                color: isTaken ? AppTokens.brandPrimary : AppTokens.income,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isTaken ? 'Saldo devedor' : 'Saldo a receber',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTokens.neutral,
                        ),
                      ),
                      const SizedBox(height: 2),
                      MoneyText(
                        loan.remaining,
                        obscure: obscureValues,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isTaken ? AppTokens.expense : AppTokens.income,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Total com encargos',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTokens.neutral,
                        ),
                      ),
                      const SizedBox(height: 2),
                      MoneyText(
                        loan.total,
                        obscure: obscureValues,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${loan.installmentCount} parcelas',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTokens.neutral,
                    ),
                  ),
                  Text(
                    '1º Venc: ${formatDateBr(loan.firstDueDate)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTokens.neutral,
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

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                shape: BoxShape.circle,
              ),
              child: const AppIcon(AppIcons.loan, size: 40),
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum empréstimo encontrado',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Cadastre seus empréstimos tomados ou concedidos para controlar saldo devedor e parcelas.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTokens.neutral,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          children: [
            const AppIcon(AppIcons.error, size: 40),
            const SizedBox(height: 16),
            Text(
              'Algo deu errado',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!.message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTokens.neutral,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loadLoans,
              icon: const AppIcon(AppIcons.refresh, size: 18),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLoanDetails(Loan loan) async {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (_, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              children: [
                Text(
                  loan.title,
                  style: Theme.of(ctx).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${loan.counterparty} • ${loan.isTaken ? "Tomado" : "Concedido"}',
                  style: const TextStyle(color: AppTokens.neutral),
                ),
                const SizedBox(height: 16),
                _detailRow('Valor Principal', loan.principal.brl),
                _detailRow('Juros / Encargos', loan.interest.brl),
                _detailRow('Valor Total', loan.total.brl),
                _detailRow(
                  loan.isTaken ? 'Total Pago' : 'Total Recebido',
                  loan.paidOrReceived.brl,
                ),
                _detailRow(
                  loan.isTaken ? 'Saldo Devedor' : 'Saldo Restante',
                  loan.remaining.brl,
                  isBold: true,
                ),
                _detailRow('Parcelas', '${loan.installmentCount}x'),
                _detailRow('1º Vencimento', formatDateBr(loan.firstDueDate)),
                if (loan.disbursedAt != null)
                  _detailRow(
                    'Data do Desembolso',
                    formatDateBr(loan.disbursedAt!),
                  ),
                if (loan.notes != null && loan.notes!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Observações',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    loan.notes!,
                    style: const TextStyle(color: AppTokens.neutral),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            );
          },
        );
      },
    );
  }

  Widget _detailRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTokens.neutral)),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isBold ? AppTokens.brandPrimary : null,
            ),
          ),
        ],
      ),
    );
  }
}
