import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../ui/app_tokens.dart';
import '../../ui/date_field.dart';
import '../accounts/account.dart';
import '../accounts/accounts_repository.dart';
import '../agreements/receipt_attempts.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import '../categories/category_badge.dart';
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
    this.onUpdated,
  });

  final Space space;
  final int payableId;
  final VoidCallback? onUpdated;

  @override
  State<_PayableModalContent> createState() => _PayableModalContentState();
}

class _PayableModalContentState extends State<_PayableModalContent> {
  Payable? _payable;
  List<Account> _accounts = [];
  bool _loading = true;
  String? _error;

  bool _isPaying = false;
  bool _isEditingBill = false;
  bool _submitting = false;
  String? _submitError;
  bool _success = false;
  String? _successMessage;

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _billAmountController = TextEditingController();
  late DateTime _selectedDate;
  int? _selectedAccountId;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateUtils.dateOnly(DateTime.now());
    _loadData();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _billAmountController.dispose();
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
      _selectedDate = DateUtils.dateOnly(DateTime.now());
      _selectedAccountId = _accounts.isNotEmpty ? _accounts.first.id : null;
      _submitError = null;
      _success = false;
    });
  }

  void _cancelPayment() {
    setState(() {
      _isPaying = false;
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

  Future<void> _submitPayment() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAccountId == null) {
      setState(
        () => _submitError = 'Selecione uma conta de saída para debitar.',
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

    final account = _accounts.firstWhere((a) => a.id == _selectedAccountId);

    final amount = Money.fromInput(_amountController.text.trim());
    if (amount == null || amount.cents <= 0) {
      setState(() => _submitError = 'Informe um valor válido maior que zero.');
      return;
    }

    final remaining = payable.remaining ?? payable.amount ?? const Money(0);
    if (amount.cents > remaining.cents) {
      setState(
        () => _submitError =
            'O valor não pode ser maior que o saldo restante da conta.',
      );
      return;
    }

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
        amount: amount,
        paidOn: toApiDate(_selectedDate),
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
            _successMessage = 'Pagamento registrado com sucesso!';
          });
          widget.onUpdated?.call();
          await _loadData();
          await Future.delayed(const Duration(milliseconds: 1000));
          if (mounted) {
            setState(() {
              _isPaying = false;
              _success = false;
              _successMessage = null;
            });
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
                      payable.description,
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
                              ? 'Credor: ${payable.payee}'
                              : 'Conta a pagar',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (payable.category != null)
                          CategoryBadge(
                            category: payable.category!,
                            compact: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
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
              if (isAwaitingAmount) ...[
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
                          'Dar baixa no pagamento',
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
                  'Valor a pagar (R\$)',
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
                      return 'Informe o valor';
                    }
                    final m = Money.fromInput(value.trim());
                    if (m == null || m.cents <= 0) {
                      return 'O valor deve ser maior que zero';
                    }
                    return null;
                  },
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
                  initialValue: _selectedAccountId,
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
                        child: Text('${acc.name} (${acc.balance.brl})'),
                      ),
                  ],
                  onChanged: (id) => setState(() => _selectedAccountId = id),
                  validator: (id) => id == null ? 'Selecione a conta' : null,
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
}
