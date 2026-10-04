import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../ui/date_field.dart';
import '../../ui/widgets.dart';
import '../accounts/account.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import 'agreement.dart';
import 'agreements_repository.dart';

/// Registro de recebimento total ou parcial. A chave idempotente acompanha o
/// conteúdo: nova tentativa do mesmo conteúdo reenvia a mesma chave (a API
/// não duplica); mudar conta, valor ou data gera uma chave nova.
class ReceiptFormScreen extends StatefulWidget {
  const ReceiptFormScreen({super.key, required this.space, required this.installment, required this.accounts, this.today});

  final Space space;
  final Installment installment;
  final List<Account> accounts;
  final DateTime? today;

  @override
  State<ReceiptFormScreen> createState() => _ReceiptFormScreenState();
}

class _ReceiptFormScreenState extends State<ReceiptFormScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount = TextEditingController(text: widget.installment.remaining.plain);
  late final DateTime _today = DateUtils.dateOnly(widget.today ?? DateTime.now());
  late DateTime _date = _today;
  late int? _accountId = widget.accounts.firstOrNull?.id;
  bool _saving = false;
  ApiException? _error;
  String? _lastPayload;
  String? _key;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  String _keyFor(String payload) {
    if (payload != _lastPayload || _key == null) {
      final random = Random.secure();
      _key = List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      _lastPayload = payload;
    }
    return _key!;
  }

  Future<void> _submit() async {
    if (_saving || !_form.currentState!.validate()) return;
    final amount = Money.fromInput(_amount.text)!;
    final date = toApiDate(_date);
    final key = _keyFor('$_accountId|${amount.cents}|$date');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await context.read<AgreementsRepository>().receive(
            widget.space.id,
            widget.installment.id,
            accountId: _accountId!,
            amount: amount,
            receivedOn: date,
            idempotencyKey: key,
          );
      if (!mounted) return;
      context.read<SessionController>().dataChanged();
      Navigator.of(context).pop(result);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installment = widget.installment;
    final fieldErrors = _error?.fieldErrors ?? const {};
    final account = widget.accounts.where((item) => item.id == _accountId).firstOrNull;

    if (widget.accounts.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Registrar recebimento')),
        body: const EmptyState(
          icon: Icons.account_balance_outlined,
          title: 'Nenhuma conta neste espaço',
          message: 'Cadastre uma conta deste espaço para receber a parcela.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Registrar recebimento')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          SpaceBadge(widget.space, prefix: 'Recebimento no espaço'),
          const SizedBox(height: 12),
          Text(
            'Parcela ${installment.number}${installment.installmentCount != null ? '/${installment.installmentCount}' : ''}'
            '${installment.agreementDescription != null ? ' · ${installment.agreementDescription}' : ''}\n'
            'Falta receber ${installment.remaining.brl}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          if (_error != null && fieldErrors.isEmpty) ...[
            FormErrorBanner(_error!.isNetwork ? '${_error!.message} Tentar de novo não duplica o recebimento.' : _error!.message),
            const SizedBox(height: 16),
          ],
          DropdownButtonFormField<int>(
            initialValue: _accountId,
            decoration: InputDecoration(labelText: 'Conta de destino', errorText: fieldErrors['account_id']),
            items: [
              for (final item in widget.accounts) DropdownMenuItem(value: item.id, child: Text(item.name)),
            ],
            onChanged: _saving ? null : (value) => setState(() => _accountId = value),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _amount,
            enabled: !_saving,
            decoration: InputDecoration(labelText: 'Valor recebido', prefixText: r'R$ ', errorText: fieldErrors['amount']),
            keyboardType: TextInputType.number,
            inputFormatters: [MoneyInputFormatter()],
            validator: (value) {
              final amount = Money.fromInput(value ?? '');
              if (amount == null || amount.isZero) return 'Informe o valor recebido.';
              if (amount.cents > installment.remaining.cents) return 'Máximo para esta parcela: ${installment.remaining.brl}.';
              return null;
            },
          ),
          const SizedBox(height: 16),
          DateField(
            label: 'Data do recebimento',
            value: _date,
            firstDate: account != null ? parseApiDate(account.openingBalanceDate) : DateTime(2000),
            lastDate: _today,
            errorText: fieldErrors['received_on'],
            onChanged: (date) => setState(() => _date = date),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Confirmar recebimento'),
          ),
          const SizedBox(height: 8),
          Text('O saldo só muda depois que a API confirmar.', textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ]),
      ),
    );
  }
}
