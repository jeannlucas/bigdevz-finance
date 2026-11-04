import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../ui/app_icons.dart';
import '../../ui/date_field.dart';
import '../accounts/account.dart';
import '../accounts/accounts_repository.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';

/// Tela para realização de transferências financeiras entre contas do mesmo espaço.
class TransferFormScreen extends StatefulWidget {
  const TransferFormScreen({
    super.key,
    required this.space,
    this.accounts,
    this.initialSourceAccountId,
  });

  final Space space;
  final List<Account>? accounts;
  final int? initialSourceAccountId;

  @override
  State<TransferFormScreen> createState() => _TransferFormScreenState();
}

class _TransferFormScreenState extends State<TransferFormScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  DateTime _date = DateUtils.dateOnly(DateTime.now());

  int? _sourceAccountId;
  int? _destinationAccountId;

  bool _loading = false;
  bool _saving = false;
  ApiException? _error;
  List<Account> _accounts = [];

  @override
  void initState() {
    super.initState();
    _sourceAccountId = widget.initialSourceAccountId;
    if (widget.accounts != null) {
      _accounts = widget.accounts!.where((a) => !a.isArchived).toList();
      _ensureValidSelection();
    } else {
      _loadAccounts();
    }
  }

  void _ensureValidSelection() {
    if (_sourceAccountId != null &&
        !_accounts.any((a) => a.id == _sourceAccountId)) {
      _sourceAccountId = null;
    }
  }

  Future<void> _loadAccounts() async {
    setState(() => _loading = true);
    try {
      final list = await context.read<AccountsRepository>().list(
        widget.space.id,
      );
      if (!mounted) return;
      setState(() {
        _accounts = list.where((a) => !a.isArchived).toList();
        _ensureValidSelection();
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || !_form.currentState!.validate()) return;

    final parsedAmount = Money.fromInput(_amount.text);
    if (parsedAmount == null || parsedAmount.cents <= 0) {
      setState(() {
        _error = const ApiException(
          'Informe um valor maior que zero.',
          status: 422,
          fieldErrors: {'amount': 'Informe um valor maior que zero.'},
        );
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final idempotencyKey =
          'transfer-${DateTime.now().microsecondsSinceEpoch}';

      await context.read<AccountsRepository>().transfer(
        widget.space.id,
        sourceAccountId: _sourceAccountId!,
        destinationAccountId: _destinationAccountId!,
        amount: parsedAmount,
        date: toApiDate(_date),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        idempotencyKey: idempotencyKey,
      );

      if (!mounted) return;
      context.read<SessionController>().dataChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transferência realizada com sucesso.')),
      );
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fieldErrors = _error?.fieldErrors ?? const {};

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transferir')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_accounts.length < 2) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transferir')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: AppIcon(AppIcons.alert, size: 48)),
              const SizedBox(height: 16),
              Text(
                'Contas insuficientes',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'É necessário possuir ao menos duas contas ativas para realizar uma transferência.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Voltar'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Transferir entre contas')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!.message,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Conta de Origem
            DropdownButtonFormField<int>(
              key: const ValueKey('transfer_source_account'),
              initialValue: _sourceAccountId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Conta de origem',
                errorText: fieldErrors['source_account_id'],
              ),
              items: _accounts
                  .map(
                    (a) => DropdownMenuItem(
                      value: a.id,
                      child: Text(
                        '${a.name} (${a.balance.brl})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (id) => setState(() => _sourceAccountId = id),
              validator: (v) =>
                  v == null ? 'Selecione a conta de origem' : null,
            ),
            const SizedBox(height: 16),

            // Conta de Destino
            DropdownButtonFormField<int>(
              key: const ValueKey('transfer_destination_account'),
              initialValue: _destinationAccountId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Conta de destino',
                errorText: fieldErrors['destination_account_id'],
              ),
              items: _accounts
                  .map(
                    (a) => DropdownMenuItem(
                      value: a.id,
                      child: Text(
                        '${a.name} (${a.balance.brl})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (id) => setState(() => _destinationAccountId = id),
              validator: (v) {
                if (v == null) return 'Selecione a conta de destino';
                if (v == _sourceAccountId) {
                  return 'A conta de destino deve ser diferente da origem';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Valor
            TextFormField(
              key: const ValueKey('transfer_amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [MoneyInputFormatter()],
              decoration: InputDecoration(
                labelText: 'Valor (R\$)',
                hintText: '0,00',
                errorText: fieldErrors['amount'],
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Informe o valor';
                final parsed = Money.fromInput(v);
                if (parsed == null || parsed.cents <= 0) {
                  return 'Informe um valor maior que zero';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Data
            DateField(
              key: const ValueKey('transfer_date'),
              label: 'Data da transferência',
              value: _date,
              onChanged: (d) => setState(() => _date = d),
              errorText: fieldErrors['transferred_at'],
            ),
            const SizedBox(height: 16),

            // Observações
            TextFormField(
              key: const ValueKey('transfer_notes'),
              controller: _notes,
              maxLines: 2,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: 'Observação (opcional)',
                errorText: fieldErrors['notes'],
              ),
            ),
            const SizedBox(height: 24),

            FilledButton(
              key: const ValueKey('transfer_submit_button'),
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Confirmar transferência'),
            ),
          ],
        ),
      ),
    );
  }
}
