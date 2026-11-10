import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../ui/app_tokens.dart';
import '../../ui/confirm_changes_dialog.dart';
import '../../ui/date_field.dart';
import '../../ui/installment_summary_card.dart';
import '../accounts/account.dart';
import '../accounts/accounts_repository.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import '../categories/category_badge.dart';
import '../categories/category_picker_field.dart';
import 'agreement.dart';
import 'agreements_repository.dart';
import 'receipt_attempts.dart';

/// Abre o modal interativo do Acordo / Conta a Receber.
///
/// - No Desktop Web (>= 840px): Apresenta um Dialog executivo centralizado.
/// - No Mobile (< 840px): Apresenta um Bottom Sheet deslizante.
///
/// Permite visualizar as parcelas e realizar a baixa diretamente inline
/// sem trocar de página ou forçar navegações profundas.
Future<void> showAgreementModal(
  BuildContext context, {
  required Space space,
  required int agreementId,
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
            maxWidth: 680,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.85,
          ),
          child: _AgreementModalContent(
            space: space,
            agreementId: agreementId,
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
        child: _AgreementModalContent(
          space: space,
          agreementId: agreementId,
          onUpdated: onUpdated,
        ),
      ),
    );
  }
}

class _AgreementModalContent extends StatefulWidget {
  const _AgreementModalContent({
    required this.space,
    required this.agreementId,
    this.onUpdated,
  });

  final Space space;
  final int agreementId;
  final VoidCallback? onUpdated;

  @override
  State<_AgreementModalContent> createState() => _AgreementModalContentState();
}

class _AgreementModalContentState extends State<_AgreementModalContent> {
  Agreement? _agreement;
  List<Account> _accounts = [];
  bool _loading = true;
  String? _error;

  Installment? _selectedInstallment;
  final Set<int> _selectedInstallmentIds = {};
  bool _isBatchMode = false;
  int _batchProgress = 0;
  int _batchTotal = 0;

  bool _submitting = false;
  String? _submitError;
  bool _success = false;

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  late DateTime _selectedDate;
  int? _selectedAccountId;

  List<Installment> get _pendingInstallments =>
      _agreement?.installments
          .where(
            (i) => i.status != InstallmentStatus.paid && i.remaining.cents > 0,
          )
          .toList() ??
      [];

  List<Installment> get _selectedInstallments => _pendingInstallments
      .where((i) => _selectedInstallmentIds.contains(i.id))
      .toList();

  Money get _totalSelectedAmount => Money(
    _selectedInstallments.fold<int>(0, (sum, i) => sum + i.remaining.cents),
  );

  void _toggleInstallment(int id) {
    setState(() {
      if (_selectedInstallmentIds.contains(id)) {
        _selectedInstallmentIds.remove(id);
      } else {
        _selectedInstallmentIds.add(id);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedInstallmentIds.length == _pendingInstallments.length) {
        _selectedInstallmentIds.clear();
      } else {
        _selectedInstallmentIds.addAll(_pendingInstallments.map((i) => i.id));
      }
    });
  }

  void _startBatchBaixa() {
    setState(() {
      _isBatchMode = true;
      _selectedInstallment = null;
      _selectedDate = DateUtils.dateOnly(DateTime.now());
      _selectedAccountId = _accounts.isNotEmpty ? _accounts.first.id : null;
      _submitError = null;
      _success = false;
    });
  }

  void _cancelBatchBaixa() {
    setState(() {
      _isBatchMode = false;
      _submitError = null;
      _success = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = DateUtils.dateOnly(DateTime.now());
    _loadData();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        context.read<AgreementsRepository>().find(
          widget.space.id,
          widget.agreementId,
        ),
        context.read<AccountsRepository>().list(widget.space.id),
      ]);
      if (mounted) {
        setState(() {
          _agreement = results[0] as Agreement;
          _accounts = (results[1] as List<Account>)
              .where((a) => !a.isArchived)
              .toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Não foi possível carregar os dados da conta a receber.';
          _loading = false;
        });
      }
    }
  }

  void _startBaixa(Installment installment) {
    setState(() {
      _selectedInstallment = installment;
      _amountController.text = installment.remaining.plain;
      _selectedDate = DateUtils.dateOnly(DateTime.now());
      _selectedAccountId = _accounts.isNotEmpty ? _accounts.first.id : null;
      _submitError = null;
      _success = false;
    });
  }

  void _cancelBaixa() {
    setState(() {
      _selectedInstallment = null;
      _submitError = null;
      _success = false;
    });
  }

  Future<void> _cancelAgreement() async {
    final agreement = _agreement;
    if (agreement == null) return;

    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: Colors.redAccent),
            SizedBox(width: 8),
            Expanded(child: Text('Cancelar conta a receber')),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tem certeza que deseja cancelar esta conta a receber? '
                'Esta ação anula o compromisso e não altera saldos bancários.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: reasonController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Motivo do cancelamento *',
                  hintText: 'Ex.: Lançado por engano, desistência do cliente',
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
      await context.read<AgreementsRepository>().cancel(
        widget.space.id,
        agreement.id,
        reasonController.text.trim(),
      );
      if (!mounted) return;
      context.read<SessionController>().dataChanged();
      widget.onUpdated?.call();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conta a receber cancelada com sucesso.')),
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

  Future<void> _editAgreement() async {
    final agreement = _agreement;
    if (agreement == null) return;

    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) =>
          EditAgreementDialog(space: widget.space, agreement: agreement),
    );

    if (updated == true && mounted) {
      context.read<SessionController>().dataChanged();
      widget.onUpdated?.call();
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Conta a receber atualizada e parcelas recalculadas com sucesso.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _submitBaixa() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAccountId == null) {
      setState(() => _submitError = 'Selecione uma conta bancária de destino.');
      return;
    }

    final userId = context.read<SessionController>().user?.id;
    if (userId == null) {
      setState(() => _submitError = 'Sessão expirada. Faça login novamente.');
      return;
    }

    final installment = _selectedInstallment;
    if (installment == null) return;

    final account = _accounts.firstWhere((a) => a.id == _selectedAccountId);

    final amount = Money.fromInput(_amountController.text.trim());
    if (amount == null || amount.cents <= 0) {
      setState(() => _submitError = 'Informe um valor válido maior que zero.');
      return;
    }

    if (amount.cents > installment.remaining.cents) {
      setState(
        () => _submitError =
            'O valor não pode ser maior que o saldo restante da parcela.',
      );
      return;
    }

    final kind = amount.cents == installment.remaining.cents
        ? ReceiptKind.total
        : ReceiptKind.partial;

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final attempts = context.read<ReceiptAttempts>();
      final outcome = await attempts.submit(
        userId: userId,
        spaceId: widget.space.id,
        installmentId: installment.id,
        accountId: account.id,
        accountName: account.name,
        amount: amount,
        receivedOn: toApiDate(_selectedDate),
        kind: kind,
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
          });
          widget.onUpdated?.call();
          await _loadData();
          await Future.delayed(const Duration(milliseconds: 1000));
          if (mounted) {
            setState(() {
              _selectedInstallment = null;
              _success = false;
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
              : 'Falha ao registrar recebimento.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null || _agreement == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Erro ao carregar conta a receber',
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

    final agreement = _agreement!;

    if (_isBatchMode) {
      return _buildBatchBaixaView(context, agreement, _selectedInstallments);
    }

    return _selectedInstallment != null
        ? _buildBaixaView(context, agreement, _selectedInstallment!)
        : _buildAgreementView(context, agreement);
  }

  Future<void> _submitBatchBaixa() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAccountId == null) {
      setState(() => _submitError = 'Selecione uma conta bancária de destino.');
      return;
    }

    final userId = context.read<SessionController>().user?.id;
    if (userId == null) {
      setState(() => _submitError = 'Sessão expirada. Faça login novamente.');
      return;
    }

    final installments = _selectedInstallments;
    if (installments.isEmpty) return;

    final account = _accounts.firstWhere((a) => a.id == _selectedAccountId);

    setState(() {
      _submitting = true;
      _submitError = null;
      _batchProgress = 0;
      _batchTotal = installments.length;
    });

    final attempts = context.read<ReceiptAttempts>();
    for (int i = 0; i < installments.length; i++) {
      final inst = installments[i];
      if (mounted) {
        setState(() => _batchProgress = i + 1);
      }
      try {
        final outcome = await attempts.submit(
          userId: userId,
          spaceId: widget.space.id,
          installmentId: inst.id,
          accountId: account.id,
          accountName: account.name,
          amount: inst.remaining,
          receivedOn: toApiDate(_selectedDate),
          kind: ReceiptKind.total,
        );
        if (outcome.state != ReceiptAttemptState.confirmed) {
          if (mounted) {
            setState(() {
              _submitting = false;
              _submitError =
                  'Erro na parcela ${inst.number}: ${outcome.message}';
            });
          }
          return;
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _submitting = false;
            _submitError =
                'Erro na parcela ${inst.number}: ${e is ApiException ? e.message : e.toString()}';
          });
        }
        return;
      }
    }

    if (mounted) {
      setState(() {
        _submitting = false;
        _success = true;
      });
      widget.onUpdated?.call();
      await _loadData();
      await Future.delayed(const Duration(milliseconds: 1000));
      if (mounted) {
        setState(() {
          _isBatchMode = false;
          _selectedInstallmentIds.clear();
          _success = false;
        });
      }
    }
  }

  /// Visão geral do Acordo e suas Parcelas
  Widget _buildAgreementView(BuildContext context, Agreement agreement) {
    final theme = Theme.of(context);
    final isPf = widget.space.isPf;
    final primaryColor = isPf
        ? const Color(0xFF1E5BB8)
        : const Color(0xFF0F8A5F);

    final total = agreement.total;
    final received = agreement.received;
    final remaining = agreement.remaining;
    final progress = total.cents > 0
        ? (received.cents / total.cents).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      key: const ValueKey('agreement-view'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cabeçalho com Ícone, Título e Fechar
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
                  color: primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.r12),
                ),
                child: Icon(
                  Icons.arrow_downward_rounded,
                  color: primaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      agreement.description,
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
                          agreement.installmentCount == 1
                              ? 'Recebimento à vista'
                              : '${agreement.installmentCount} parcelas',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (agreement.category != null)
                          CategoryBadge(
                            category: agreement.category!,
                            compact: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!agreement.isCancelled && agreement.received.isZero) ...[
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Editar conta a receber',
                  onPressed: _editAgreement,
                ),
                IconButton(
                  icon: Icon(
                    Icons.cancel_outlined,
                    size: 20,
                    color: theme.colorScheme.error,
                  ),
                  tooltip: 'Cancelar conta a receber',
                  onPressed: _cancelAgreement,
                ),
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

        // Conteúdo rolável com Resumo e Lista de Parcelas
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(AppTokens.p20),
            children: [
              // Banner de Cancelamento
              if (agreement.isCancelled) ...[
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
                        Icons.cancel_outlined,
                        color: theme.colorScheme.error,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Conta a receber cancelada',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.error,
                                fontSize: 14,
                              ),
                            ),
                            if (agreement.cancelReason != null &&
                                agreement.cancelReason!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Motivo: ${agreement.cancelReason}',
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
              // Card Executivo de Totais
              Container(
                padding: const EdgeInsets.all(AppTokens.p16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.35,
                  ),
                  borderRadius: BorderRadius.circular(AppTokens.r16),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.4,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryMetric(
                            label: 'Total',
                            value: total.brl,
                            valueStyle: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _SummaryMetric(
                            label: 'Recebido',
                            value: received.brl,
                            valueStyle: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0F8A5F),
                            ),
                          ),
                        ),
                        Expanded(
                          child: _SummaryMetric(
                            label: 'Falta receber',
                            value: remaining.brl,
                            valueStyle: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          progress >= 1.0
                              ? const Color(0xFF0F8A5F)
                              : primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Parcelas (${agreement.installmentCount})',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (_pendingInstallments.length > 1)
                    TextButton(
                      onPressed: _toggleSelectAll,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: Text(
                        _selectedInstallmentIds.length ==
                                _pendingInstallments.length
                            ? 'Desmarcar todas'
                            : 'Selecionar todas',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: primaryColor,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Lista das parcelas
              for (final inst in agreement.installments) ...[
                _InstallmentCard(
                  installment: inst,
                  totalInstallments: agreement.installmentCount,
                  primaryColor: primaryColor,
                  isCancelled: agreement.isCancelled,
                  isSelectable:
                      !agreement.isCancelled &&
                      _pendingInstallments.length > 1 &&
                      inst.status != InstallmentStatus.paid &&
                      inst.remaining.cents > 0,
                  isSelected: _selectedInstallmentIds.contains(inst.id),
                  onToggleSelect: () => _toggleInstallment(inst.id),
                  onDarBaixa: () => _startBaixa(inst),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),

        // Barra inferior de Baixa em Lote
        if (_selectedInstallmentIds.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppTokens.p16),
            child: FilledButton.icon(
              onPressed: _startBatchBaixa,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                backgroundColor: const Color(0xFF0F8A5F),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTokens.r12),
                ),
              ),
              icon: const Icon(Icons.playlist_add_check_rounded, size: 20),
              label: Text(
                'Baixar selecionadas (${_selectedInstallmentIds.length}) • ${_totalSelectedAmount.brl}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Visão de Baixa Rápida da Parcela Selecionada
  Widget _buildBaixaView(
    BuildContext context,
    Agreement agreement,
    Installment installment,
  ) {
    final theme = Theme.of(context);
    final isPf = widget.space.isPf;
    final primaryColor = isPf
        ? const Color(0xFF1E5BB8)
        : const Color(0xFF0F8A5F);

    if (_success) {
      return Center(
        key: const ValueKey('baixa-success'),
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
                'Recebimento registrado!',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F8A5F),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'O valor foi creditado na conta com sucesso.',
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

    return Column(
      key: const ValueKey('baixa-form'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Topo com voltar e título
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
                onPressed: _submitting ? null : _cancelBaixa,
                tooltip: 'Voltar',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Baixar Parcela ${installment.number}',
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

        // Formulário de baixa
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

                // Destaque de saldo a receber
                Container(
                  padding: const EdgeInsets.all(AppTokens.p16),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppTokens.r12),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.2),
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
                              'Saldo restante da parcela',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              installment.remaining.brl,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          'Venc: ${formatDateBr(installment.dueDate)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Campo Valor
                Text(
                  'Valor a receber (R\$)',
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
                    if (m.cents > installment.remaining.cents) {
                      return 'O valor excede o saldo restante (${installment.remaining.brl})';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Seletor de Conta Bancária
                Text(
                  'Conta de destino',
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

                // Data de Recebimento
                Text(
                  'Data do recebimento',
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
                    onPressed: _submitting ? null : _submitBaixa,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
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
                            'Confirmar recebimento',
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

  /// Visão de Baixa em Lote das Parcelas Selecionadas
  Widget _buildBatchBaixaView(
    BuildContext context,
    Agreement agreement,
    List<Installment> installments,
  ) {
    final theme = Theme.of(context);

    if (_success) {
      return Center(
        key: const ValueKey('batch-baixa-success'),
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
                'Recebimento registrado!',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F8A5F),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                installments.length == 1
                    ? 'A parcela selecionada foi baixada com sucesso.'
                    : 'As ${installments.length} parcelas foram baixadas com sucesso.',
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

    return Column(
      key: const ValueKey('batch-baixa-form'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Topo com voltar e título
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
                onPressed: _submitting ? null : _cancelBatchBaixa,
                tooltip: 'Voltar',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  installments.length == 1
                      ? 'Baixar 1 parcela'
                      : 'Baixar ${installments.length} parcelas',
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

        // Formulário de baixa em lote
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

                // Destaque de total em lote
                Container(
                  padding: const EdgeInsets.all(AppTokens.p16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F8A5F).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppTokens.r12),
                    border: Border.all(
                      color: const Color(0xFF0F8A5F).withValues(alpha: 0.25),
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
                              installments.length == 1
                                  ? 'Total a receber (1 parcela)'
                                  : 'Total a receber (${installments.length} parcelas)',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _totalSelectedAmount.brl,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F8A5F),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F8A5F)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '${installments.length} selecionadas',
                          style: const TextStyle(
                            color: Color(0xFF0F8A5F),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Lista resumida das parcelas incluídas
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(AppTokens.r12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Parcelas que serão quitadas:',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final inst in installments)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Parcela ${inst.number} · Venc: ${formatDateBr(inst.dueDate)}',
                                  style: theme.textTheme.bodySmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                inst.remaining.brl,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Seletor de Conta Bancária
                Text(
                  'Conta de destino',
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

                // Data de Recebimento
                Text(
                  'Data do recebimento',
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

                // Botão de Confirmação em Lote
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submitBatchBaixa,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: const Color(0xFF0F8A5F),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTokens.r12),
                      ),
                    ),
                    child: _submitting
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Baixando parcela $_batchProgress de $_batchTotal...',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            installments.length == 1
                                ? 'Confirmar recebimento de 1 parcela'
                                : 'Confirmar recebimento das ${installments.length} parcelas',
                            style: const TextStyle(
                              fontSize: 15,
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

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, style: valueStyle),
      ],
    );
  }
}

class _InstallmentCard extends StatelessWidget {
  const _InstallmentCard({
    required this.installment,
    required this.totalInstallments,
    required this.primaryColor,
    required this.onDarBaixa,
    this.isCancelled = false,
    this.isSelectable = false,
    this.isSelected = false,
    this.onToggleSelect,
  });

  final Installment installment;
  final int totalInstallments;
  final Color primaryColor;
  final VoidCallback onDarBaixa;
  final bool isCancelled;
  final bool isSelectable;
  final bool isSelected;
  final VoidCallback? onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPaid =
        installment.status == InstallmentStatus.paid ||
        installment.remaining.cents == 0;
    final isOverdue = installment.overdue;

    return InkWell(
      onTap: isSelectable ? onToggleSelect : null,
      borderRadius: BorderRadius.circular(AppTokens.r12),
      child: Container(
        padding: const EdgeInsets.all(AppTokens.p14),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.1)
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.35,
                ),
          borderRadius: BorderRadius.circular(AppTokens.r12),
          border: Border.all(
            color: isSelected
                ? primaryColor
                : isOverdue
                ? theme.colorScheme.error.withValues(alpha: 0.5)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            if (isSelectable) ...[
              Checkbox(
                value: isSelected,
                onChanged: (_) => onToggleSelect?.call(),
                activeColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
            ],
            // Número e Vencimento
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Parcela ${installment.number} de $totalInstallments',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isOverdue && !isPaid) ...[
                        const SizedBox(width: 8),
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
                            'Vencida',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Vencimento: ${formatDateBr(installment.dueDate)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isOverdue && !isPaid
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    installment.amount.brl,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Ação / Status
            if (isCancelled)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppTokens.r8),
                ),
                child: Text(
                  'Cancelada',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else if (isPaid)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F8A5F).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppTokens.r8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_rounded,
                      color: Color(0xFF0F8A5F),
                      size: 16,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Recebida',
                      style: TextStyle(
                        color: Color(0xFF0F8A5F),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )
            else
              FilledButton.icon(
                onPressed: onDarBaixa,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(110, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTokens.r8),
                  ),
                ),
                icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                label: const Text('Dar baixa'),
              ),
          ],
        ),
      ),
    );
  }
}

enum _EditInstallmentMode { byInstallment, byTotal }

class EditAgreementDialog extends StatefulWidget {
  const EditAgreementDialog({
    super.key,
    required this.space,
    required this.agreement,
  });

  final Space space;
  final Agreement agreement;

  @override
  State<EditAgreementDialog> createState() => _EditAgreementDialogState();
}

class _EditAgreementDialogState extends State<EditAgreementDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _descController;
  late final TextEditingController _amountController;
  late final TextEditingController _countController;
  late int? _selectedCategory;
  late DateTime _firstDueDate;
  late _EditInstallmentMode _mode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final agr = widget.agreement;
    _descController = TextEditingController(text: agr.description);
    _selectedCategory = agr.categoryId;
    _countController = TextEditingController(
      text: agr.installmentCount.toString(),
    );
    _mode = agr.installmentCount > 1
        ? _EditInstallmentMode.byInstallment
        : _EditInstallmentMode.byTotal;

    final initialPerInstallment = agr.installments.isNotEmpty
        ? agr.installments.first.amount
        : agr.total;

    _amountController = TextEditingController(
      text: _mode == _EditInstallmentMode.byInstallment
          ? initialPerInstallment.plain
          : agr.total.plain,
    );

    if (agr.installments.isNotEmpty) {
      _firstDueDate = parseApiDate(agr.installments.first.dueDate);
    } else if (agr.nextDueDate != null) {
      _firstDueDate = parseApiDate(agr.nextDueDate!);
    } else {
      _firstDueDate = DateUtils.dateOnly(DateTime.now());
    }

    _countController.addListener(_onChanged);
    _amountController.addListener(_onChanged);
  }

  void _onChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _countController.removeListener(_onChanged);
    _amountController.removeListener(_onChanged);
    _descController.dispose();
    _amountController.dispose();
    _countController.dispose();
    super.dispose();
  }

  int get _parsedCount => int.tryParse(_countController.text) ?? 1;

  Money? get _computedTotal {
    final inputMoney = Money.fromInput(_amountController.text);
    if (inputMoney == null) return null;
    final count = _parsedCount;
    if (count <= 1) return inputMoney;
    if (_mode == _EditInstallmentMode.byInstallment) {
      final totalCents = inputMoney.cents * count;
      if (totalCents > Money.maxCents) return null;
      return Money(totalCents);
    }
    return inputMoney;
  }

  Money? get _computedPerInstallment {
    final inputMoney = Money.fromInput(_amountController.text);
    if (inputMoney == null) return null;
    final count = _parsedCount;
    if (count <= 1) return inputMoney;
    if (_mode == _EditInstallmentMode.byInstallment) {
      return inputMoney;
    }
    return Money(inputMoney.cents ~/ count);
  }

  bool get _hasRecalculationChanged {
    final computed = _computedTotal;
    if (computed == null) return false;
    final agr = widget.agreement;
    return computed.cents != agr.total.cents ||
        _parsedCount != agr.installmentCount ||
        toApiDate(_firstDueDate) !=
            (agr.installments.isNotEmpty
                ? agr.installments.first.dueDate
                : agr.nextDueDate);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final total = _computedTotal;
    if (total == null || total.isZero) return;

    final agr = widget.agreement;
    final changes = <ChangeDifference>[];

    final newDesc = _descController.text.trim();
    if (newDesc != agr.description) {
      changes.add(
        ChangeDifference(
          label: 'Descrição',
          oldValue: agr.description,
          newValue: newDesc,
        ),
      );
    }

    if (_selectedCategory != agr.categoryId) {
      changes.add(
        ChangeDifference(
          label: 'Categoria',
          oldValue: agr.categoryId != null
              ? 'Categoria vinculada'
              : 'Sem categoria',
          newValue: _selectedCategory != null
              ? 'Nova categoria selecionada'
              : 'Sem categoria',
        ),
      );
    }

    if (total.cents != agr.total.cents) {
      changes.add(
        ChangeDifference(
          label: 'Valor total',
          oldValue: agr.total.brl,
          newValue: total.brl,
        ),
      );
    }

    if (_parsedCount != agr.installmentCount) {
      changes.add(
        ChangeDifference(
          label: 'Número de parcelas',
          oldValue: '${agr.installmentCount}x',
          newValue: '${_parsedCount}x',
        ),
      );
    }

    final oldDueDate = agr.installments.isNotEmpty
        ? agr.installments.first.dueDate
        : (agr.nextDueDate ?? '');
    final newDueDate = toApiDate(_firstDueDate);
    if (oldDueDate.isNotEmpty && oldDueDate != newDueDate) {
      changes.add(
        ChangeDifference(
          label: 'Primeiro vencimento',
          oldValue: formatDateBr(oldDueDate),
          newValue: formatDateBr(newDueDate),
        ),
      );
    }

    if (changes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhuma alteração foi realizada.')),
      );
      Navigator.of(context).pop(false);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => ConfirmChangesDialog(
        changes: changes,
        warning: _hasRecalculationChanged
            ? 'As parcelas em aberto desta conta serão excluídas e recalculadas deterministicamente.'
            : null,
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;

    setState(() => _saving = true);
    try {
      await context.read<AgreementsRepository>().update(
        widget.space.id,
        widget.agreement.id,
        {
          'description': _descController.text.trim(),
          'category_id': _selectedCategory,
          'total': total.toApi(),
          'installment_count': _parsedCount,
          'first_due_date': toApiDate(_firstDueDate),
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final agr = widget.agreement;
    final isUnreceived = agr.received.isZero;
    final total = _computedTotal;
    final perInst = _computedPerInstallment;
    final count = _parsedCount;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.edit_outlined),
          SizedBox(width: 8),
          Expanded(child: Text('Editar conta a receber')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _descController,
                  decoration: const InputDecoration(labelText: 'Descrição *'),
                  maxLength: 120,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Informe a descrição.'
                      : null,
                ),
                const SizedBox(height: 12),
                CategoryPickerField(
                  spaceId: widget.space.id,
                  type: 'income',
                  selectedCategoryId: _selectedCategory,
                  onChanged: (catId) =>
                      setState(() => _selectedCategory = catId),
                ),
                if (isUnreceived) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Text(
                    'Valor e Parcelamento',
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<_EditInstallmentMode>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: _EditInstallmentMode.byInstallment,
                        label: Text('Valor da parcela'),
                        icon: Icon(Icons.pin_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: _EditInstallmentMode.byTotal,
                        label: Text('Valor total'),
                        icon: Icon(Icons.all_inclusive, size: 16),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (newSelection) {
                      if (newSelection.isEmpty) return;
                      final newMode = newSelection.first;
                      if (newMode == _mode) return;
                      final currentMoney = Money.fromInput(
                        _amountController.text,
                      );
                      final c = _parsedCount;
                      if (currentMoney != null && c > 0) {
                        if (newMode == _EditInstallmentMode.byTotal) {
                          final totalCents = currentMoney.cents * c;
                          if (totalCents <= Money.maxCents) {
                            _amountController.text = Money(totalCents).plain;
                          }
                        } else {
                          _amountController.text = Money(
                            currentMoney.cents ~/ c,
                          ).plain;
                        }
                      }
                      setState(() => _mode = newMode);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _amountController,
                          decoration: InputDecoration(
                            labelText:
                                _mode == _EditInstallmentMode.byInstallment
                                ? 'Valor da parcela *'
                                : 'Valor total *',
                            prefixText: 'R\$ ',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (v) {
                            final m = Money.fromInput(v ?? '');
                            if (m == null || m.isZero) {
                              return 'Informe um valor válido.';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _countController,
                          decoration: const InputDecoration(
                            labelText: 'Nº Parcelas *',
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n = int.tryParse(v ?? '');
                            if (n == null || n < 1 || n > 1200) {
                              return 'De 1 a 1200';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DateField(
                    label: 'Primeiro Vencimento *',
                    value: _firstDueDate,
                    onChanged: (d) => setState(() => _firstDueDate = d),
                  ),
                  const SizedBox(height: 14),
                  if (total != null && perInst != null) ...[
                    InstallmentSummaryCard(
                      installmentCount: count,
                      installmentAmount: perInst,
                      totalAmount: total,
                      isByInstallmentMode:
                          _mode == _EditInstallmentMode.byInstallment,
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_hasRecalculationChanged)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: Colors.amber.shade900,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'As parcelas em aberto serão recalculadas e redistribuídas deterministicamente.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  _hasRecalculationChanged
                      ? 'Salvar e Recalcular'
                      : 'Salvar alterações',
                ),
        ),
      ],
    );
  }
}
