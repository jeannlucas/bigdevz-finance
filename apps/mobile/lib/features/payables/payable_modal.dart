import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/text_formatters.dart';
import '../../ui/app_tokens.dart';
import '../../ui/confirm_changes_dialog.dart';
import '../../ui/date_field.dart';
import '../accounts/account.dart';
import '../accounts/accounts_repository.dart';
import '../agreements/receipt_attempts.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import '../categories/category_badge.dart';
import '../categories/category_picker_field.dart';
import 'payable.dart';
import 'payables_repository.dart';

/// Abre o modal interativo da Conta a Pagar ou Fatura de Cartão.
///
/// - No Desktop Web (>= 840px): Apresenta um Dialog executivo com dimensões estáveis (640x600).
/// - No Mobile (< 840px): Apresenta um Bottom Sheet deslizante (88% da altura).
///
/// Suporta contas avulsas, parceladas, recorrentes e faturas de cartão (incluindo
/// faturas com valor a informar). Permite preencher o valor e realizar a baixa
/// inline sem trocar de tela.
Future<void> showPayableModal(
  BuildContext context, {
  required Space space,
  required int payableId,
  bool initialPaying = false,
  VoidCallback? onUpdated,
}) async {
  final isDesktop = MediaQuery.sizeOf(context).width >= 840;

  if (isDesktop) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Theme.of(dialogContext).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.r20),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.85,
          ),
          child: _PayableModalContent(
            space: space,
            payableId: payableId,
            initialPaying: initialPaying,
            onUpdated: onUpdated,
          ),
        ),
      ),
    );
  } else {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTokens.r24),
        ),
      ),
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.9,
        ),
        child: _PayableModalContent(
          space: space,
          payableId: payableId,
          initialPaying: initialPaying,
          onUpdated: onUpdated,
        ),
      ),
    );
  }
}

class _PayableModalContent extends StatefulWidget {
  const _PayableModalContent({
    required this.space,
    required this.payableId,
    this.initialPaying = false,
    this.onUpdated,
  });

  final Space space;
  final int payableId;
  final bool initialPaying;
  final VoidCallback? onUpdated;

  @override
  State<_PayableModalContent> createState() => _PayableModalContentState();
}

class _PayableModalContentState extends State<_PayableModalContent> {
  Payable? _payable;
  List<Account> _accounts = [];
  bool _loading = true;
  String? _error;
  bool _hasInitializedPayment = false;

  bool _isPaying = false;
  bool _isEditingBill = false;
  bool _submitting = false;
  String? _submitError;
  bool _success = false;
  String? _successMessage;

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _billAmountController = TextEditingController();
  final _interestController = TextEditingController();
  final _fineController = TextEditingController();
  final _discountController = TextEditingController();
  bool _showCharges = false;
  late DateTime _selectedDate;
  int? _selectedAccountId;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateUtils.dateOnly(DateTime.now());
    _amountController.addListener(_onChargeChanged);
    _interestController.addListener(_onChargeChanged);
    _fineController.addListener(_onChargeChanged);
    _discountController.addListener(_onChargeChanged);
    _loadData();
  }

  void _onChargeChanged() {
    if (_isPaying && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _amountController.removeListener(_onChargeChanged);
    _interestController.removeListener(_onChargeChanged);
    _fineController.removeListener(_onChargeChanged);
    _discountController.removeListener(_onChargeChanged);
    _amountController.dispose();
    _billAmountController.dispose();
    _interestController.dispose();
    _fineController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        context.read<PayablesRepository>().find(
          widget.space.id,
          widget.payableId,
        ),
        context.read<AccountsRepository>().list(widget.space.id),
      ]);
      if (mounted) {
        setState(() {
          _payable = results[0] as Payable;
          _accounts = (results[1] as List<Account>)
              .where((a) => !a.isArchived)
              .toList();
          _loading = false;
        });
        if (widget.initialPaying &&
            !_hasInitializedPayment &&
            (_payable?.canPay ?? false)) {
          _hasInitializedPayment = true;
          _startPayment();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Não foi possível carregar os dados desta conta.';
          _loading = false;
        });
      }
    }
  }

  void _startPayment() {
    final remaining = _payable?.remaining ?? _payable?.amount ?? const Money(0);
    setState(() {
      _isPaying = true;
      _isEditingBill = false;
      _amountController.text = remaining.plain;
      _interestController.clear();
      _fineController.clear();
      _discountController.clear();
      _showCharges = false;
      _selectedDate = DateUtils.dateOnly(DateTime.now());
      _selectedAccountId = null;
      _submitError = null;
      _success = false;
    });
  }

  void _cancelPayment() {
    setState(() {
      _isPaying = false;
      _interestController.clear();
      _fineController.clear();
      _discountController.clear();
      _showCharges = false;
      _submitError = null;
      _success = false;
    });
  }

  void _startEditingBill() {
    final currentAmount = _payable?.amount;
    setState(() {
      _isEditingBill = true;
      _isPaying = false;
      _billAmountController.text = currentAmount != null
          ? currentAmount.plain
          : '';
      _submitError = null;
      _success = false;
    });
  }

  void _cancelEditingBill() {
    setState(() {
      _isEditingBill = false;
      _submitError = null;
      _success = false;
    });
  }

  Future<void> _cancelPayable(Payable payable) async {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.block, color: Colors.redAccent),
            SizedBox(width: 8),
            Expanded(child: Text('Cancelar conta a pagar')),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tem certeza que deseja cancelar esta conta a pagar? '
                'Esta ação cancela a conta a pagar e não altera saldos bancários.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: reasonController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Motivo do cancelamento *',
                  hintText: 'Ex.: Lançado por engano, boleto cancelado',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Informe o motivo do cancelamento.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogCtx).pop(true);
              }
            },
            child: const Text('Confirmar cancelamento'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    try {
      await context.read<PayablesRepository>().cancel(
        widget.space.id,
        payable.id,
        reasonController.text.trim(),
      );
      if (!mounted) return;
      context.read<SessionController>().dataChanged();
      widget.onUpdated?.call();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conta a pagar cancelada com sucesso.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao cancelar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _editPayable(Payable payable) async {
    final descController = TextEditingController(
      text: toFinancialUpper(payable.description),
    );
    final payeeController = TextEditingController(
      text: payable.payee != null ? toFinancialUpper(payable.payee!) : '',
    );
    final amountController = TextEditingController(
      text: payable.amount?.plain ?? '',
    );
    DateTime due = parseApiDate(payable.dueDate);
    int? selectedCategoryId = payable.categoryId;
    final formKey = GlobalKey<FormState>();

    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.edit_outlined),
              SizedBox(width: 8),
              Expanded(child: Text('Editar conta a pagar')),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: descController,
                      inputFormatters: const [UpperCaseTextFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Descrição *',
                      ),
                      maxLength: 120,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Informe a descrição.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: payeeController,
                      inputFormatters: const [UpperCaseTextFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Credor / Beneficiário (opcional)',
                      ),
                      maxLength: 120,
                    ),
                    const SizedBox(height: 12),
                    CategoryPickerField(
                      spaceId: widget.space.id,
                      type: 'expense',
                      selectedCategoryId: selectedCategoryId,
                      onChanged: (newId) =>
                          setDialogState(() => selectedCategoryId = newId),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: amountController,
                      decoration: const InputDecoration(
                        labelText: 'Valor *',
                        prefixText: 'R\$ ',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        final parsed = Money.fromInput(v ?? '');
                        if (parsed == null || parsed.isZero) {
                          return 'Informe um valor válido.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DateField(
                      label: 'Vencimento *',
                      value: due,
                      onChanged: (newDate) =>
                          setDialogState(() => due = newDate),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final newDesc = descController.text.trim();
                final newPayee = payeeController.text.trim();
                final newAmount = Money.fromInput(amountController.text)!;
                final newDueDate = toApiDate(due);

                final changes = <ChangeDifference>[];
                final currentUpperDesc = toFinancialUpper(payable.description);
                if (newDesc != currentUpperDesc) {
                  changes.add(
                    ChangeDifference(
                      label: 'Descrição',
                      oldValue: currentUpperDesc,
                      newValue: newDesc,
                    ),
                  );
                }
                final currentUpperPayee = toFinancialUpper(payable.payee);
                if (newPayee != currentUpperPayee) {
                  changes.add(
                    ChangeDifference(
                      label: 'Beneficiário',
                      oldValue: currentUpperPayee.isEmpty
                          ? '(nenhum)'
                          : currentUpperPayee,
                      newValue: newPayee.isEmpty ? '(nenhum)' : newPayee,
                    ),
                  );
                }
                if (selectedCategoryId != payable.categoryId) {
                  changes.add(
                    ChangeDifference(
                      label: 'Categoria',
                      oldValue: payable.category?.name ?? '(sem categoria)',
                      newValue: selectedCategoryId == null
                          ? '(sem categoria)'
                          : 'Alterada',
                    ),
                  );
                }
                if (payable.amount != null &&
                    newAmount.cents != payable.amount!.cents) {
                  changes.add(
                    ChangeDifference(
                      label: 'Valor',
                      oldValue: payable.amount!.brl,
                      newValue: newAmount.brl,
                    ),
                  );
                }
                if (payable.dueDate != newDueDate) {
                  changes.add(
                    ChangeDifference(
                      label: 'Vencimento',
                      oldValue: formatDateBr(payable.dueDate),
                      newValue: formatDateBr(newDueDate),
                    ),
                  );
                }

                if (changes.isEmpty) {
                  Navigator.of(dialogCtx).pop(false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Nenhuma alteração foi realizada.'),
                    ),
                  );
                  return;
                }

                final confirmed = await showDialog<bool>(
                  context: dialogCtx,
                  builder: (confirmCtx) =>
                      ConfirmChangesDialog(changes: changes),
                );
                if (confirmed == true && dialogCtx.mounted) {
                  Navigator.of(dialogCtx).pop(true);
                }
              },
              child: const Text('Salvar alterações'),
            ),
          ],
        ),
      ),
    );

    if (updated != true) return;
    if (!mounted) return;

    try {
      await context.read<PayablesRepository>().update(
        widget.space.id,
        payable.id,
        {
          'description': descController.text.trim(),
          'payee': payeeController.text.trim().isEmpty
              ? null
              : payeeController.text.trim(),
          'category_id': selectedCategoryId,
          'amount': Money.fromInput(amountController.text)!.toApi(),
          'due_date': toApiDate(due),
        },
      );
      if (!mounted) return;
      context.read<SessionController>().dataChanged();
      widget.onUpdated?.call();
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Conta a pagar atualizada com sucesso.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao atualizar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _changeCategory(Payable payable) async {
    int? selectedId = payable.categoryId;
    final formKey = GlobalKey<FormState>();

    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.label_outline_rounded),
              SizedBox(width: 8),
              Expanded(child: Text('Alterar categoria')),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selecione uma categoria de despesa para esta conta.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  CategoryPickerField(
                    spaceId: widget.space.id,
                    type: 'expense',
                    selectedCategoryId: selectedId,
                    onChanged: (newId) =>
                        setDialogState(() => selectedId = newId),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('Salvar categoria'),
            ),
          ],
        ),
      ),
    );

    if (updated != true) return;
    if (!mounted) return;

    try {
      await context.read<PayablesRepository>().update(
        widget.space.id,
        payable.id,
        {'category_id': selectedId, 'reason': 'Reclassificação de categoria'},
      );
      if (!mounted) return;
      context.read<SessionController>().dataChanged();
      widget.onUpdated?.call();
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Categoria atualizada com sucesso.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao atualizar categoria: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _revertPayment(Payable payable, Payment payment) async {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final totalToRestore = payment.effectiveTotal;
    final principalToReopen = payment.effectivePrincipal;
    final expectedPaidCents = payable.paid.cents - principalToReopen.cents;
    final expectedStatus = expectedPaidCents <= 0 ? 'Em aberto' : 'Parcial';

    final account = _accounts
        .where((a) => a.id == payment.accountId)
        .firstOrNull;
    final accountName = account?.name ?? 'Conta #${payment.accountId}';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.replay_rounded, color: Colors.amber),
            SizedBox(width: 8),
            Expanded(child: Text('Estornar pagamento')),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppTokens.p14),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(AppTokens.r12),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Impacto financeiro do estorno:',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.amber.shade900,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• Saldo a devolver na conta (${toFinancialUpper(accountName)}): +${totalToRestore.brl}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '• Valor a reabrir na conta a pagar: +${principalToReopen.brl}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '• Novo status da conta a pagar: $expectedStatus',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: reasonController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Justificativa do estorno *',
                      hintText: 'Ex.: Pagamento indevido, pagamento duplicado',
                      helperText: 'Obrigatório (mínimo de 3 caracteres)',
                    ),
                    maxLength: 255,
                    validator: (v) {
                      if (v == null || v.trim().length < 3) {
                        return 'Informe a justificativa do estorno (mínimo 3 caracteres).';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.amber.shade800,
            ),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogCtx).pop(true);
              }
            },
            child: const Text('Confirmar estorno'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final userId = context.read<SessionController>().user?.id;
    if (userId == null) return;

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final attempts = context.read<ReceiptAttempts>();
      final outcome = await attempts.submitPaymentFix(
        userId: userId,
        spaceId: widget.space.id,
        payableId: payable.id,
        original: payment,
        originalAccountName: accountName,
        reason: reasonController.text.trim(),
      );

      if (mounted) {
        if (outcome.state != ReceiptAttemptState.confirmed) {
          setState(() {
            _submitting = false;
            _submitError = outcome.message;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(outcome.message),
              backgroundColor: Colors.red,
            ),
          );
        } else {
          setState(() => _submitting = false);
          context.read<SessionController>().dataChanged();
          widget.onUpdated?.call();
          await _loadData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Estorno realizado com sucesso! O saldo foi restaurado.',
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao estornar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _correctPayment(Payable payable, Payment payment) async {
    final reasonController = TextEditingController();
    final amountController = TextEditingController(
      text: payment.effectivePrincipal.plain,
    );
    DateTime date = parseApiDate(payment.paidOn);
    int? selectedAccountId = payment.accountId;
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.edit_note_rounded, color: Colors.blueAccent),
              SizedBox(width: 8),
              Expanded(child: Text('Corrigir pagamento')),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'O pagamento original será estornado e um novo pagamento auditado substituirá a operação.',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: amountController,
                      decoration: const InputDecoration(
                        labelText: 'Valor correto *',
                        prefixText: 'R\$ ',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [MoneyInputFormatter()],
                      validator: (v) {
                        final m = Money.fromInput(v ?? '');
                        if (m == null || m.cents <= 0) {
                          return 'Informe um valor válido.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: selectedAccountId,
                      decoration: const InputDecoration(
                        labelText: 'Conta de saída *',
                      ),
                      items: [
                        for (final acc in _accounts)
                          DropdownMenuItem(
                            value: acc.id,
                            child: Text(
                              '${toFinancialUpper(acc.name)} (${acc.balance.brl})',
                            ),
                          ),
                      ],
                      onChanged: (id) =>
                          setDialogState(() => selectedAccountId = id),
                      validator: (id) =>
                          id == null ? 'Selecione a conta' : null,
                    ),
                    const SizedBox(height: 12),
                    DateField(
                      label: 'Data de pagamento *',
                      value: date,
                      onChanged: (newDate) =>
                          setDialogState(() => date = newDate),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: reasonController,
                      decoration: const InputDecoration(
                        labelText: 'Justificativa da correção *',
                        hintText: 'Ex.: Conta bancária errada, valor digitado incorreto',
                      ),
                      maxLength: 255,
                      validator: (v) => (v == null || v.trim().length < 3)
                          ? 'Informe o motivo (mínimo 3 caracteres).'
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(dialogCtx).pop(true);
                }
              },
              child: const Text('Confirmar correção'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final userId = context.read<SessionController>().user?.id;
    if (userId == null) return;

    final newAmount = Money.fromInput(amountController.text.trim())!;
    final targetAccount = _accounts.firstWhere(
      (a) => a.id == selectedAccountId,
    );
    final origAccount = _accounts
        .where((a) => a.id == payment.accountId)
        .firstOrNull;

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final attempts = context.read<ReceiptAttempts>();
      final outcome = await attempts.submitPaymentFix(
        userId: userId,
        spaceId: widget.space.id,
        payableId: payable.id,
        original: payment,
        originalAccountName: origAccount?.name ?? 'Conta #${payment.accountId}',
        reason: reasonController.text.trim(),
        replacement: (
          accountId: targetAccount.id,
          accountName: targetAccount.name,
          amount: newAmount,
          receivedOn: toApiDate(date),
        ),
      );

      if (mounted) {
        if (outcome.state != ReceiptAttemptState.confirmed) {
          setState(() {
            _submitting = false;
            _submitError = outcome.message;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(outcome.message),
              backgroundColor: Colors.red,
            ),
          );
        } else {
          setState(() => _submitting = false);
          context.read<SessionController>().dataChanged();
          widget.onUpdated?.call();
          await _loadData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Pagamento corrigido com sucesso!')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao corrigir pagamento: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _submitBillAmount() async {
    final payable = _payable;
    if (payable == null) return;

    final amount = Money.fromInput(_billAmountController.text.trim());
    if (amount == null || amount.cents <= 0) {
      setState(
        () => _submitError =
            'Informe um valor válido maior que zero para a fatura.',
      );
      return;
    }

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      await context.read<PayablesRepository>().update(
        widget.space.id,
        payable.id,
        {
          'description': payable.description,
          'payee': payable.payee,
          'amount': amount.toApi(),
          'due_date': payable.dueDate,
        },
      );

      if (mounted) {
        setState(() {
          _submitting = false;
          _success = true;
          _successMessage = 'Valor da fatura salvo com sucesso!';
        });
        widget.onUpdated?.call();
        await _loadData();
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) {
          setState(() {
            _isEditingBill = false;
            _success = false;
            _successMessage = null;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _submitError = e is ApiException
              ? e.message
              : 'Falha ao salvar o valor da fatura.';
        });
      }
    }
  }

  Money get _currentPrincipal =>
      Money.fromInput(_amountController.text.trim()) ?? const Money(0);
  Money get _currentInterest =>
      Money.fromInput(_interestController.text.trim()) ?? const Money(0);
  Money get _currentFine =>
      Money.fromInput(_fineController.text.trim()) ?? const Money(0);
  Money get _currentDiscount =>
      Money.fromInput(_discountController.text.trim()) ?? const Money(0);

  int get _computedTotalCents {
    final p = _currentPrincipal.cents;
    final i = _currentInterest.cents;
    final f = _currentFine.cents;
    final d = _currentDiscount.cents;
    return p + i + f - d;
  }

  Future<void> _submitPayment() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAccountId == null) {
      setState(
        () => _submitError =
            'Selecione uma conta bancária para debitar o pagamento.',
      );
      return;
    }

    final userId = context.read<SessionController>().user?.id;
    if (userId == null) {
      setState(() => _submitError = 'Sessão expirada. Faça login novamente.');
      return;
    }

    final payable = _payable;
    if (payable == null) return;

    final account = _accounts
        .where((a) => a.id == _selectedAccountId)
        .firstOrNull;
    if (account == null) {
      setState(
        () => _submitError = 'Selecione uma conta válida do espaço ativo.',
      );
      return;
    }

    final principal = Money.fromInput(_amountController.text.trim());
    if (principal == null || principal.cents <= 0) {
      setState(
        () =>
            _submitError = 'Informe um valor principal válido maior que zero.',
      );
      return;
    }

    final remaining = payable.remaining ?? payable.amount ?? const Money(0);
    if (principal.cents > remaining.cents) {
      setState(
        () => _submitError =
            'O valor principal não pode ser maior que o saldo restante da conta (${remaining.brl}).',
      );
      return;
    }

    final interest = Money.fromInput(_interestController.text.trim());
    final fine = Money.fromInput(_fineController.text.trim());
    final discount = Money.fromInput(_discountController.text.trim());

    final subtotalCents =
        principal.cents + (interest?.cents ?? 0) + (fine?.cents ?? 0);
    if ((discount?.cents ?? 0) >= subtotalCents) {
      setState(
        () => _submitError =
            'O desconto deve ser menor que o subtotal com juros e multa.',
      );
      return;
    }

    final totalDebited = Money(subtotalCents - (discount?.cents ?? 0));

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final attempts = context.read<ReceiptAttempts>();
      final outcome = await attempts.submitPayment(
        userId: userId,
        spaceId: widget.space.id,
        payableId: payable.id,
        accountId: account.id,
        accountName: account.name,
        amount: principal,
        paidOn: toApiDate(_selectedDate),
        interest: interest,
        fine: fine,
        discount: discount,
      );

      if (mounted) {
        if (outcome.state != ReceiptAttemptState.confirmed) {
          setState(() {
            _submitting = false;
            _submitError = outcome.message;
          });
        } else {
          setState(() {
            _submitting = false;
            _success = true;
            _successMessage =
                'Pagamento de ${totalDebited.brl} registrado com sucesso!';
          });
          widget.onUpdated?.call();
          if (widget.initialPaying) {
            await Future.delayed(const Duration(milliseconds: 700));
            if (mounted) {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.of(context).pop();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    'Pagamento de ${totalDebited.brl} registrado com sucesso!',
                  ),
                ),
              );
            }
          } else {
            await _loadData();
            await Future.delayed(const Duration(milliseconds: 800));
            if (mounted) {
              setState(() {
                _isPaying = false;
                _success = false;
                _successMessage = null;
              });
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _submitError = e is ApiException
              ? e.message
              : 'Falha ao registrar pagamento.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Carregando detalhes...',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null || _payable == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Erro ao carregar conta a pagar',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _loadData,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    final payable = _payable!;

    return _isEditingBill
        ? _buildEditBillForm(context, payable)
        : _isPaying
        ? _buildPaymentForm(context, payable)
        : _buildPayableView(context, payable);
  }

  /// Visão geral da Conta a Pagar / Fatura
  Widget _buildPayableView(BuildContext context, Payable payable) {
    final theme = Theme.of(context);
    final isOverdue = payable.overdue;
    final isPaid = payable.status == PayableStatus.paid;
    final isAwaitingAmount =
        payable.status == PayableStatus.awaitingAmount ||
        payable.amount == null;
    final isCardBill = payable.isCardBill;
    final remaining = payable.remaining ?? payable.amount ?? const Money(0);
    final totalAmount = payable.amount ?? const Money(0);

    return Column(
      key: const ValueKey('payable-view'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cabeçalho
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.p20,
            AppTokens.p16,
            AppTokens.p12,
            AppTokens.p12,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isCardBill
                      ? const Color(0xFF7B2CBF).withValues(alpha: 0.12)
                      : isOverdue
                      ? theme.colorScheme.error.withValues(alpha: 0.12)
                      : theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.r12),
                ),
                child: Icon(
                  isCardBill
                      ? Icons.credit_card_rounded
                      : Icons.arrow_upward_rounded,
                  color: isCardBill
                      ? const Color(0xFF7B2CBF)
                      : isOverdue
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      toFinancialUpper(payable.description),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Text(
                          isCardBill
                              ? 'Fatura de Cartão de Crédito'
                              : payable.payee != null &&
                                    payable.payee!.isNotEmpty
                              ? 'Credor: ${toFinancialUpper(payable.payee)}'
                              : 'Conta a pagar',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        InkWell(
                          onTap: payable.isCancelled
                              ? null
                              : () => _changeCategory(payable),
                          borderRadius: BorderRadius.circular(4),
                          child: payable.category != null
                              ? CategoryBadge(
                                  category: payable.category!,
                                  compact: true,
                                )
                              : Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.label_outline_rounded,
                                        size: 12,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Sem categoria',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!payable.isCancelled) ...[
                IconButton(
                  icon: const Icon(Icons.label_outline_rounded, size: 20),
                  tooltip: 'Alterar categoria',
                  onPressed: () => _changeCategory(payable),
                ),
                if (payable.paid.isZero) ...[
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: 'Editar conta a pagar',
                    onPressed: () => _editPayable(payable),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.block,
                      size: 20,
                      color: theme.colorScheme.error,
                    ),
                    tooltip: 'Cancelar conta a pagar',
                    onPressed: () => _cancelPayable(payable),
                  ),
                ],
              ],
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Fechar',
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // Conteúdo
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(AppTokens.p20),
            children: [
              // Banner de Cancelamento
              if (payable.isCancelled) ...[
                Container(
                  padding: const EdgeInsets.all(AppTokens.p14),
                  margin: const EdgeInsets.only(bottom: AppTokens.p16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(
                      alpha: 0.35,
                    ),
                    borderRadius: BorderRadius.circular(AppTokens.r12),
                    border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.block,
                        color: theme.colorScheme.error,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Conta a pagar cancelada',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.error,
                                fontSize: 14,
                              ),
                            ),
                            if (payable.cancelReason != null &&
                                payable.cancelReason!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Motivo: ${payable.cancelReason}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // Card de Valores
              if (isAwaitingAmount)
                Container(
                  padding: const EdgeInsets.all(AppTokens.p16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(AppTokens.r16),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: Colors.amber.shade800,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Valor a informar',
                            style: TextStyle(
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'O total desta fatura ainda não foi lançado. Você pode informar o valor assim que a fatura fechar.',
                        style: TextStyle(
                          color: Colors.amber.shade900.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(AppTokens.p16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.35,
                    ),
                    borderRadius: BorderRadius.circular(AppTokens.r16),
                    border: Border.all(
                      color: isOverdue
                          ? theme.colorScheme.error.withValues(alpha: 0.3)
                          : theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.4,
                            ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Valor total',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            totalAmount.brl,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      if (payable.paid.cents > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Já pago',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF0F8A5F),
                              ),
                            ),
                            Text(
                              payable.paid.brl,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF0F8A5F),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(height: 1),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Falta pagar',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            remaining.brl,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: isOverdue
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // Informações de Vencimento e Status
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppTokens.r12),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.event_outlined,
                            size: 18,
                            color: isOverdue
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Vencimento: ${formatDateBr(payable.dueDate)}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isOverdue
                                    ? theme.colorScheme.error
                                    : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
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
                        color: isPaid
                            ? const Color(0xFF0F8A5F).withValues(alpha: 0.15)
                            : isAwaitingAmount
                            ? Colors.amber.shade100
                            : isOverdue
                            ? theme.colorScheme.errorContainer
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isPaid
                            ? 'Pago'
                            : isAwaitingAmount
                            ? 'Aguardando valor'
                            : isOverdue
                            ? 'Vencida'
                            : payable.status.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isPaid
                              ? const Color(0xFF0F8A5F)
                              : isAwaitingAmount
                              ? Colors.amber.shade900
                              : isOverdue
                              ? theme.colorScheme.onErrorContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Ações Principais
              if (payable.isCancelled) ...[
                Container(
                  padding: const EdgeInsets.all(AppTokens.p16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(
                      alpha: 0.2,
                    ),
                    borderRadius: BorderRadius.circular(AppTokens.r12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.block, color: theme.colorScheme.error),
                      const SizedBox(width: 8),
                      Text(
                        'Esta conta foi cancelada',
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (isAwaitingAmount) ...[
                SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _startEditingBill,
                    icon: const Icon(Icons.edit_note_rounded, size: 22),
                    label: const Text(
                      'Informar valor da fatura',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTokens.r12),
                      ),
                    ),
                  ),
                ),
              ] else if (!isPaid) ...[
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _startPayment,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      backgroundColor: const Color(0xFF0F8A5F),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTokens.r12),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline_rounded, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Registrar pagamento',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isCardBill) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: _startEditingBill,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Corrigir total da fatura'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTokens.r12),
                        ),
                      ),
                    ),
                  ),
                ],
              ] else
                Container(
                  padding: const EdgeInsets.all(AppTokens.p16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F8A5F).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppTokens.r12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF0F8A5F),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Esta conta já foi liquidada',
                        style: TextStyle(
                          color: Color(0xFF0F8A5F),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              // Histórico de Pagamentos e Estornos (AC-PAY-REV-001..006)
              _buildPaymentHistory(context, payable),
            ],
          ),
        ),
      ],
    );
  }

  /// Formulário para Informar ou Corrigir o Total da Fatura
  Widget _buildEditBillForm(BuildContext context, Payable payable) {
    final theme = Theme.of(context);

    if (_success) {
      return Center(
        key: const ValueKey('bill-success'),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFF0F8A5F),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _successMessage ?? 'Fatura atualizada!',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F8A5F),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      key: const ValueKey('edit-bill-form'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Topo com voltar e fechar
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.p12,
            AppTokens.p12,
            AppTokens.p12,
            AppTokens.p12,
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _submitting ? null : _cancelEditingBill,
                tooltip: 'Voltar',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Valor da Fatura',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).pop(),
                tooltip: 'Fechar',
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // Formulário
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(AppTokens.p20),
            children: [
              if (_submitError != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppTokens.p12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(
                      alpha: 0.6,
                    ),
                    borderRadius: BorderRadius.circular(AppTokens.r12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: theme.colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _submitError!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              Text(
                'Digite o valor total fechado da fatura deste mês:',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),

              // Campo Valor da fatura
              Text(
                'Total da fatura (R\$)',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _billAmountController,
                keyboardType: TextInputType.number,
                autofocus: true,
                inputFormatters: [MoneyInputFormatter()],
                decoration: InputDecoration(
                  prefixText: 'R\$ ',
                  hintText: '0,00',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTokens.r12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: _submitting ? null : _submitBillAmount,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.r12),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Salvar total da fatura',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Formulário de Baixa de Pagamento
  Widget _buildPaymentForm(BuildContext context, Payable payable) {
    final theme = Theme.of(context);

    if (_success) {
      return Center(
        key: const ValueKey('payment-success'),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFF0F8A5F),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _successMessage ?? 'Pagamento registrado!',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F8A5F),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'O valor foi debitado da conta informada.',
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

    final remaining = payable.remaining ?? payable.amount ?? const Money(0);

    return Column(
      key: const ValueKey('payment-form'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Topo com voltar e fechar
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.p12,
            AppTokens.p12,
            AppTokens.p12,
            AppTokens.p12,
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _submitting ? null : _cancelPayment,
                tooltip: 'Voltar',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Confirmar Pagamento',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).pop(),
                tooltip: 'Fechar',
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // Formulário
        Flexible(
          child: Form(
            key: _formKey,
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(AppTokens.p20),
              children: [
                if (_submitError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(AppTokens.p12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withValues(
                        alpha: 0.6,
                      ),
                      borderRadius: BorderRadius.circular(AppTokens.r12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: theme.colorScheme.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _submitError!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Destaque de saldo
                Container(
                  padding: const EdgeInsets.all(AppTokens.p16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(AppTokens.r12),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.4,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Saldo a pagar',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              remaining.brl,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Venc: ${formatDateBr(payable.dueDate)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Campo Valor
                Text(
                  'Valor principal a amortizar (R\$)',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [MoneyInputFormatter()],
                  decoration: InputDecoration(
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.r12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe o valor principal';
                    }
                    final m = Money.fromInput(value.trim());
                    if (m == null || m.cents <= 0) {
                      return 'O valor deve ser maior que zero';
                    }
                    if (payable.remaining != null &&
                        m.cents > payable.remaining!.cents) {
                      return 'O valor excede o saldo restante (${payable.remaining!.brl})';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 12),

                // Seção de Juros, Multa e Descontos (AC-PAY-INT-001..007)
                InkWell(
                  onTap: () => setState(() => _showCharges = !_showCharges),
                  borderRadius: BorderRadius.circular(AppTokens.r8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 4,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _showCharges
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Juros, multa e desconto (opcional)',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (_showCharges) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Juros (R\$)',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextFormField(
                              key: const ValueKey('interest-input'),
                              controller: _interestController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [MoneyInputFormatter()],
                              decoration: InputDecoration(
                                prefixText: 'R\$ ',
                                hintText: '0,00',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppTokens.r8,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Multa (R\$)',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextFormField(
                              key: const ValueKey('fine-input'),
                              controller: _fineController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [MoneyInputFormatter()],
                              decoration: InputDecoration(
                                prefixText: 'R\$ ',
                                hintText: '0,00',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppTokens.r8,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Desconto (R\$)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextFormField(
                        key: const ValueKey('discount-input'),
                        controller: _discountController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [MoneyInputFormatter()],
                        decoration: InputDecoration(
                          prefixText: 'R\$ ',
                          hintText: '0,00',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppTokens.r8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                // Card de Cálculo em tempo real do total a debitar
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(AppTokens.p14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.25,
                    ),
                    borderRadius: BorderRadius.circular(AppTokens.r12),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Valor principal amortizado:',
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(
                            _currentPrincipal.brl,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      if (_currentInterest.cents > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '(+) Juros:',
                              style: theme.textTheme.bodySmall,
                            ),
                            Text(
                              '+${_currentInterest.brl}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (_currentFine.cents > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '(+) Multa:',
                              style: theme.textTheme.bodySmall,
                            ),
                            Text(
                              '+${_currentFine.brl}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (_currentDiscount.cents > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '(-) Desconto:',
                              style: theme.textTheme.bodySmall,
                            ),
                            Text(
                              '-${_currentDiscount.brl}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text(
                              'Total a debitar na conta:',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            Money(_computedTotalCents).brl,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Conta Bancária de Saída
                Text(
                  'Conta de onde vai sair o dinheiro',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _selectedAccountId,
                  hint: const Text('Selecione uma conta'),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.r12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  items: [
                    for (final acc in _accounts)
                      DropdownMenuItem(
                        value: acc.id,
                        child: Text(
                          '${toFinancialUpper(acc.name)} (${acc.balance.brl})',
                        ),
                      ),
                  ],
                  onChanged: (id) => setState(() => _selectedAccountId = id),
                  validator: (id) => id == null
                      ? 'Selecione uma conta bancária para debitar o pagamento.'
                      : null,
                ),

                const SizedBox(height: 16),

                // Data de Pagamento
                Text(
                  'Data do pagamento',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                DateField(
                  label: '',
                  value: _selectedDate,
                  onChanged: (date) => setState(() => _selectedDate = date),
                ),

                const SizedBox(height: 28),

                // Botão de Confirmação
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submitPayment,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      backgroundColor: const Color(0xFF0F8A5F),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTokens.r12),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Confirmar pagamento',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentHistory(BuildContext context, Payable payable) {
    final theme = Theme.of(context);
    final payments = payable.payments;
    if (payments.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            Icon(
              Icons.history_rounded,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Histórico de pagamentos (${payments.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final payment in payments) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(AppTokens.p14),
            decoration: BoxDecoration(
              color: payment.isReversed
                  ? theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.25,
                    )
                  : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTokens.r12),
              border: Border.all(
                color: payment.isReversed
                    ? theme.colorScheme.outlineVariant.withValues(alpha: 0.3)
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            payment.effectiveTotal.brl,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              decoration: payment.isReversed
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: payment.isReversed
                                  ? theme.colorScheme.onSurfaceVariant
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (payment.isReversed)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Estornado',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                            )
                          else if (payment.isCorrected)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Corrigido',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F8A5F)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Liquidado',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F8A5F),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      formatDateBr(payment.paidOn),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (payment.hasCharges) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Valor original: ${payment.effectivePrincipal.brl}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (payment.interest != null &&
                          payment.interest!.cents > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '+Juros: ${payment.interest!.brl}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.red.shade800,
                            ),
                          ),
                        ),
                      if (payment.fine != null && payment.fine!.cents > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '+Multa: ${payment.fine!.brl}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.red.shade800,
                            ),
                          ),
                        ),
                      if (payment.discount != null &&
                          payment.discount!.cents > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '-Desc: ${payment.discount!.brl}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.account_balance_rounded,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      toFinancialUpper(
                        _accounts
                                .where((a) => a.id == payment.accountId)
                                .firstOrNull
                                ?.name ??
                            'Conta #${payment.accountId}',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (payment.isReversed && payment.reversalReason != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Motivo do estorno: ${payment.reversalReason}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                if (!payment.isReversed) ...[
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: theme.colorScheme.primary,
                        ),
                        onPressed: _submitting
                            ? null
                            : () => _correctPayment(payable, payment),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Corrigir'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: Colors.amber.shade900,
                        ),
                        onPressed: _submitting
                            ? null
                            : () => _revertPayment(payable, payment),
                        icon: const Icon(Icons.replay_rounded, size: 16),
                        label: const Text('Estornar'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
