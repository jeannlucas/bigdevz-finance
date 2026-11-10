import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../ui/app_tokens.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import 'accounting_period_repository.dart';

class AccountingPeriodDialog extends StatefulWidget {
  const AccountingPeriodDialog({
    super.key,
    required this.space,
    this.repository,
  });

  final Space space;
  final AccountingPeriodRepository? repository;

  static Future<void> show(BuildContext context, {required Space space}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AccountingPeriodDialog(space: space),
    );
  }

  @override
  State<AccountingPeriodDialog> createState() => _AccountingPeriodDialogState();
}

class _AccountingPeriodDialogState extends State<AccountingPeriodDialog> {
  late final AccountingPeriodRepository _repo;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  String? _currentClosedUntil;
  bool _isClosed = false;

  DateTime? _selectedCloseDate;
  final _reasonController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _repo =
        widget.repository ??
        AccountingPeriodRepository(api: context.read<ApiClient>());
    _loadStatus();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await _repo.getStatus(space: widget.space);
      if (mounted) {
        setState(() {
          _currentClosedUntil = data['closed_until'] as String?;
          _isClosed =
              (data['is_closed'] as bool?) ?? (_currentClosedUntil != null);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Não foi possível consultar o status contábil.';
        });
      }
    }
  }

  Future<void> _submitClosePeriod() async {
    if (_selectedCloseDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione a data limite para o fechamento contábil.'),
          backgroundColor: AppTokens.expense,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final session = context.read<SessionController?>();

    try {
      await _repo.closePeriod(
        space: widget.space,
        closedUntil: toApiDate(_selectedCloseDate!),
        reason: _reasonController.text.trim().isEmpty
            ? null
            : _reasonController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Período contábil fechado com sucesso.'),
            backgroundColor: AppTokens.income,
          ),
        );
        await session?.reloadSpaces();
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao fechar período: ${e.toString()}'),
            backgroundColor: AppTokens.expense,
          ),
        );
      }
    }
  }

  Future<void> _submitReopenPeriod() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    final session = context.read<SessionController?>();

    try {
      await _repo.reopenPeriod(
        space: widget.space,
        reason: _reasonController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Período contábil reaberto com sucesso.'),
            backgroundColor: AppTokens.income,
          ),
        );
        await session?.reloadSpaces();
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao reabrir período: ${e.toString()}'),
            backgroundColor: AppTokens.expense,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!widget.space.isAdmin) {
      return AlertDialog(
        title: const Text('Acesso Restrito'),
        content: const Text(
          'Apenas administradores podem fechar ou reabrir períodos contábeis.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_clock_rounded, color: AppTokens.brandPrimary),
          SizedBox(width: 10),
          Text(
            'Período Contábil',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: _isLoading
            ? const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              )
            : _errorMessage != null
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AppTokens.expense,
                      size: 36,
                    ),
                    const SizedBox(height: 8),
                    Text(_errorMessage!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _loadStatus,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              )
            : Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status Atual
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppTokens.p12),
                      decoration: BoxDecoration(
                        color: _isClosed
                            ? AppTokens.warning.withValues(alpha: 0.12)
                            : AppTokens.income.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppTokens.r8),
                        border: Border.all(
                          color: _isClosed
                              ? AppTokens.warning.withValues(alpha: 0.4)
                              : AppTokens.income.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isClosed
                                ? Icons.lock_rounded
                                : Icons.lock_open_rounded,
                            color: _isClosed
                                ? AppTokens.warning
                                : AppTokens.income,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isClosed && _currentClosedUntil != null
                                  ? 'Período contábil fechado até: ${formatDateBr(_currentClosedUntil!)}'
                                  : 'Período contábil totalmente aberto.',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _isClosed
                                    ? AppTokens.warning
                                    : AppTokens.income,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (!_isClosed) ...[
                      // FLUXO DE FECHAMENTO
                      const Text(
                        'Ao fechar o período, nenhuma movimentação financeira (criação, baixa, estorno ou cancelamento) poderá ser lançada com data igual ou anterior à data escolhida.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTokens.neutral,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Seleção de Data de Fechamento
                      ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTokens.r8),
                          side: BorderSide(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        leading: const Icon(Icons.calendar_today_rounded),
                        title: Text(
                          _selectedCloseDate != null
                              ? 'Fechar até: ${formatDateBr(toApiDate(_selectedCloseDate!))}'
                              : 'Selecionar data de fechamento',
                          style: TextStyle(
                            fontWeight: _selectedCloseDate != null
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now().subtract(
                              const Duration(days: 1),
                            ),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setState(() => _selectedCloseDate = picked);
                          }
                        },
                      ),
                      const SizedBox(height: 12),

                      // Motivo Opcional
                      TextFormField(
                        controller: _reasonController,
                        decoration: InputDecoration(
                          labelText: 'Motivo do fechamento (opcional)',
                          hintText: 'Ex.: Fechamento mensal de Outubro',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppTokens.r8),
                          ),
                        ),
                      ),
                    ] else ...[
                      // FLUXO DE REABERTURA
                      const Text(
                        'A reabertura de período contábil permite registrar correções em datas passadas. Por conformidade, exige-se justificativa obrigatória registrada em auditoria permanente.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTokens.neutral,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Justificativa Obrigatória
                      TextFormField(
                        controller: _reasonController,
                        decoration: InputDecoration(
                          labelText: 'Justificativa da reabertura *',
                          hintText: 'Mínimo de 5 caracteres explicando a necessidade...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppTokens.r8),
                          ),
                        ),
                        maxLines: 3,
                        validator: (val) {
                          if (val == null || val.trim().length < 5) {
                            return 'A justificativa deve conter no mínimo 5 caracteres.';
                          }
                          return null;
                        },
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        if (!_isLoading && _errorMessage == null)
          FilledButton(
            onPressed: _isSubmitting
                ? null
                : _isClosed
                ? _submitReopenPeriod
                : _submitClosePeriod,
            style: _isClosed
                ? FilledButton.styleFrom(backgroundColor: AppTokens.warning)
                : null,
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _isClosed ? 'Reabrir Período Contábil' : 'Fechar Período',
                  ),
          ),
      ],
    );
  }
}
