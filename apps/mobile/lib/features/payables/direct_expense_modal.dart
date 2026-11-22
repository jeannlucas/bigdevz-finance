import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/text_formatters.dart';
import '../../ui/app_tokens.dart';
import '../../ui/date_field.dart';
import '../accounts/account.dart';
import '../accounts/accounts_repository.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import '../categories/category_picker_field.dart';
import 'payables_repository.dart';

/// Abre o fluxo de "Registrar despesa paga" (compra no débito em confirmação única).
Future<void> showDirectExpenseModal(
  BuildContext context, {
  required Space space,
  int? preselectedAccountId,
}) {
  final isDesktop = MediaQuery.sizeOf(context).width >= 640;
  if (isDesktop) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.r20),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540, maxHeight: 680),
          child: _DirectExpenseContent(
            space: space,
            preselectedAccountId: preselectedAccountId,
          ),
        ),
      ),
    );
  } else {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTokens.r24),
        ),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.9,
          ),
          child: _DirectExpenseContent(
            space: space,
            preselectedAccountId: preselectedAccountId,
          ),
        ),
      ),
    );
  }
}

class _DirectExpenseContent extends StatefulWidget {
  const _DirectExpenseContent({required this.space, this.preselectedAccountId});

  final Space space;
  final int? preselectedAccountId;

  @override
  State<_DirectExpenseContent> createState() => _DirectExpenseContentState();
}

class _DirectExpenseContentState extends State<_DirectExpenseContent> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  int? _selectedAccountId;
  int? _selectedCategoryId;

  List<Account> _accounts = [];
  bool _loadingAccounts = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedAccountId = widget.preselectedAccountId;
    _loadAccounts();
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    try {
      final repo = context.read<AccountsRepository>();
      final list = await repo.list(widget.space.id);
      final active = list.where((a) => !a.isArchived).toList();
      if (mounted) {
        setState(() {
          _accounts = active;
          if (_selectedAccountId == null && active.isNotEmpty) {
            _selectedAccountId = active.first.id;
          }
          _loadingAccounts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Erro ao carregar contas.';
          _loadingAccounts = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    if (_selectedAccountId == null) {
      setState(() => _error = 'Selecione uma conta bancária de origem.');
      return;
    }

    final amount = Money.fromInput(_amountCtrl.text);
    if (amount == null || amount.isZero) {
      setState(() => _error = 'Informe um valor válido.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final idempotencyKey =
        'direct-expense-${widget.space.id}-${DateTime.now().millisecondsSinceEpoch}-${amount.cents}';

    try {
      final repo = context.read<PayablesRepository>();
      await repo.registerDirectExpense(
        widget.space.id,
        accountId: _selectedAccountId!,
        amount: amount,
        date: toApiDate(_date),
        description: _descriptionCtrl.text.trim(),
        categoryId: _selectedCategoryId,
        idempotencyKey: idempotencyKey,
      );

      if (!mounted) return;
      context.read<SessionController>().dataChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Despesa paga de ${amount.brl} registrada com sucesso!',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loadingAccounts) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppTokens.p20),
        children: [
          // Cabeçalho
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTokens.expense.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.r10),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.shopping_bag_rounded,
                  color: AppTokens.expense,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Registrar Despesa Paga',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Débito em conta à vista em confirmação única',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(AppTokens.r8),
              ),
              child: Text(
                _error!,
                style: TextStyle(
                  color: theme.colorScheme.onErrorContainer,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // 1. Conta de Origem (Visível com saldo disponível)
          DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: _selectedAccountId,
            decoration: const InputDecoration(
              labelText: 'Conta de Origem *',
              prefixIcon: Icon(Icons.account_balance_rounded, size: 20),
            ),
            items: [
              for (final acc in _accounts)
                DropdownMenuItem<int>(
                  value: acc.id,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          toFinancialUpper(acc.name),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Saldo: ${acc.balance.brl}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: acc.balance.cents >= 0
                              ? AppTokens.income
                              : AppTokens.expense,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: (val) => setState(() => _selectedAccountId = val),
            validator: (v) => v == null ? 'Selecione uma conta.' : null,
          ),
          const SizedBox(height: 14),

          // 2. Valor
          TextFormField(
            controller: _amountCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Valor Pago *',
              prefixText: r'R$ ',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [MoneyInputFormatter()],
            validator: (v) {
              final m = Money.fromInput(v ?? '');
              if (m == null || m.isZero) return 'Informe o valor da despesa.';
              return null;
            },
          ),
          const SizedBox(height: 14),

          // 3. Descrição
          TextFormField(
            controller: _descriptionCtrl,
            inputFormatters: const [UpperCaseTextFormatter()],
            decoration: const InputDecoration(
              labelText: 'Descrição da Despesa *',
              hintText: 'Ex: Almoço com cliente, Combustível...',
              prefixIcon: Icon(Icons.description_outlined, size: 20),
            ),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Informe a descrição.' : null,
          ),
          const SizedBox(height: 14),

          // 4. Categoria (com subcategorias suportadas)
          CategoryPickerField(
            spaceId: widget.space.id,
            type: 'expense',
            selectedCategoryId: _selectedCategoryId,
            onChanged: (catId) => setState(() => _selectedCategoryId = catId),
          ),
          const SizedBox(height: 14),

          // 5. Data da despesa
          DateField(
            label: 'Data do Pagamento',
            value: _date,
            onChanged: (d) => setState(() => _date = d),
          ),
          const SizedBox(height: 24),

          // Botão único de confirmação
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: AppTokens.expense,
            ),
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_outline_rounded, size: 20),
            label: Text(
              _saving ? 'Registrando...' : 'Confirmar Despesa Paga',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}
