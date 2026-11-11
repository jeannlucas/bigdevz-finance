import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/text_formatters.dart';
import '../../ui/app_tokens.dart';
import '../../ui/date_field.dart';
import '../accounts/account.dart';
import '../accounts/accounts_repository.dart';
import '../agreements/receipt_attempts.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import 'payable.dart';

/// Modal para pagamento em lote de múltiplas contas a pagar selecionadas.
Future<void> showBatchPayableModal(
  BuildContext context, {
  required Space space,
  required List<Payable> payables,
  VoidCallback? onCompleted,
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
          child: _BatchPayableModalContent(
            space: space,
            payables: payables,
            onCompleted: onCompleted,
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
        child: _BatchPayableModalContent(
          space: space,
          payables: payables,
          onCompleted: onCompleted,
        ),
      ),
    );
  }
}

class _BatchPayableModalContent extends StatefulWidget {
  const _BatchPayableModalContent({
    required this.space,
    required this.payables,
    this.onCompleted,
  });

  final Space space;
  final List<Payable> payables;
  final VoidCallback? onCompleted;

  @override
  State<_BatchPayableModalContent> createState() =>
      _BatchPayableModalContentState();
}

class _BatchPayableModalContentState extends State<_BatchPayableModalContent> {
  List<Account> _accounts = [];
  bool _loading = true;
  String? _error;

  int? _selectedAccountId;
  late DateTime _selectedDate;
  bool _submitting = false;
  String? _submitError;
  bool _success = false;
  int _progress = 0;

  Money get _totalAmount => Money(
    widget.payables.fold<int>(0, (sum, p) => sum + (p.remaining?.cents ?? 0)),
  );

  @override
  void initState() {
    super.initState();
    _selectedDate = DateUtils.dateOnly(DateTime.now());
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final accounts = await context.read<AccountsRepository>().list(
        widget.space.id,
      );
      if (mounted) {
        final activeAccounts = accounts.where((a) => !a.isArchived).toList();
        setState(() {
          _accounts = activeAccounts;
          if (activeAccounts.isNotEmpty) {
            _selectedAccountId = activeAccounts.first.id;
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Não foi possível carregar as contas bancárias.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_selectedAccountId == null) {
      setState(() => _submitError = 'Selecione uma conta bancária de origem.');
      return;
    }

    final userId = context.read<SessionController>().user?.id;
    if (userId == null) {
      setState(() => _submitError = 'Sessão expirada. Faça login novamente.');
      return;
    }

    final account = _accounts.firstWhere((a) => a.id == _selectedAccountId);

    setState(() {
      _submitting = true;
      _submitError = null;
      _progress = 0;
    });

    final attempts = context.read<ReceiptAttempts>();

    for (int i = 0; i < widget.payables.length; i++) {
      final payable = widget.payables[i];
      if (mounted) {
        setState(() => _progress = i + 1);
      }
      try {
        final outcome = await attempts.submitPayment(
          userId: userId,
          spaceId: widget.space.id,
          payableId: payable.id,
          accountId: account.id,
          accountName: account.name,
          amount: payable.remaining ?? payable.amount ?? const Money(0),
          paidOn: toApiDate(_selectedDate),
        );

        if (outcome.state != ReceiptAttemptState.confirmed) {
          if (mounted) {
            setState(() {
              _submitting = false;
              _submitError =
                  'Erro ao pagar "${toFinancialUpper(payable.description)}": ${outcome.message}';
            });
          }
          return;
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _submitting = false;
            _submitError =
                'Erro ao pagar "${toFinancialUpper(payable.description)}": ${e is ApiException ? e.message : e.toString()}';
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
      widget.onCompleted?.call();
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) {
        Navigator.of(context).pop();
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

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _loadAccounts,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    final dangerColor = theme.colorScheme.error;

    return Column(
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
                  color: dangerColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.r12),
                ),
                child: Icon(
                  Icons.playlist_add_check_rounded,
                  color: dangerColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.payables.length == 1
                          ? 'Pagar 1 conta'
                          : 'Pagar ${widget.payables.length} contas',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Pagamento em lote de contas',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
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

        // Conteúdo rolável adaptativo
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(AppTokens.p20),
            children: [
              // Card com Total
              Container(
                padding: const EdgeInsets.all(AppTokens.p16),
                decoration: BoxDecoration(
                  color: dangerColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppTokens.r12),
                  border: Border.all(
                    color: dangerColor.withValues(alpha: 0.25),
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
                            widget.payables.length == 1
                                ? 'Total a pagar (1 conta)'
                                : 'Total a pagar (${widget.payables.length} contas)',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _totalAmount.brl,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: dangerColor,
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
                        color: dangerColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        widget.payables.length == 1
                            ? '1 selecionada'
                            : '${widget.payables.length} selecionadas',
                        style: TextStyle(
                          color: dangerColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Lista resumida das contas incluídas
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
                      'Contas que serão quitadas:',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final p in widget.payables)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${toFinancialUpper(p.description)} · Venc: ${formatDateBr(p.dueDate)}',
                                style: theme.textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              (p.remaining ?? p.amount ?? const Money(0)).brl,
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

              const SizedBox(height: 16),

              // Seletor de Conta Bancária
              DropdownButtonFormField<int>(
                initialValue: _selectedAccountId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Pagar com qual conta bancária? *',
                  prefixIcon: Icon(Icons.account_balance_rounded),
                ),
                items: _accounts
                    .map(
                      (a) => DropdownMenuItem(
                        value: a.id,
                        child: Text(
                          '${toFinancialUpper(a.name)} (${a.balance.brl})',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _submitting
                    ? null
                    : (val) => setState(() => _selectedAccountId = val),
              ),

              const SizedBox(height: 16),

              // Seletor de Data
              DateField(
                label: 'Data do pagamento *',
                value: _selectedDate,
                onChanged: _submitting
                    ? (_) {}
                    : (d) => setState(() => _selectedDate = d),
              ),

              if (_submitError != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(AppTokens.r8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 20,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _submitError!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_submitting) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: widget.payables.isEmpty
                        ? 0.0
                        : _progress / widget.payables.length,
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(dangerColor),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Processando pagamento $_progress de ${widget.payables.length}...',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),

        // Barra inferior de Confirmação
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(AppTokens.p16),
          child: FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              backgroundColor: _success ? const Color(0xFF0F8A5F) : dangerColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.r12),
              ),
            ),
            icon: Icon(
              _success ? Icons.check_circle_rounded : Icons.payment_rounded,
              size: 20,
            ),
            label: Text(
              _success
                  ? 'Pagamentos realizados com sucesso!'
                  : widget.payables.length == 1
                  ? 'Confirmar pagamento de 1 conta'
                  : 'Confirmar pagamento de ${widget.payables.length} contas',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}
