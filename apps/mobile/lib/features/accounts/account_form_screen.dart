import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../ui/date_field.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import 'accounts_repository.dart';

class AccountFormScreen extends StatefulWidget {
  const AccountFormScreen({super.key, required this.space});

  final Space space;

  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _balance = TextEditingController(text: '0,00');
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  bool _saving = false;
  ApiException? _error;

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<AccountsRepository>().create(
        widget.space.id,
        name: _name.text.trim(),
        openingBalance: Money.fromInput(_balance.text)!,
        date: toApiDate(_date),
      );
      if (!mounted) return;
      context.read<SessionController>().dataChanged();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Conta cadastrada.')));
      Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fieldErrors = _error?.fieldErrors ?? const {};
    return Scaffold(
      appBar: AppBar(title: const Text('Nova conta')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SpaceBadge(widget.space, prefix: 'Conta do espaço'),
            const SizedBox(height: 20),
            if (_error != null && fieldErrors.isEmpty) ...[
              FormErrorBanner(_error!.message),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                labelText: 'Nome da conta',
                hintText: 'Ex.: Banco PF',
                errorText: fieldErrors['name'],
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLength: 80,
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Informe um nome.' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _balance,
              decoration: InputDecoration(
                labelText: 'Saldo inicial',
                prefixText: r'R$ ',
                errorText: fieldErrors['opening_balance'],
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [MoneyInputFormatter()],
              validator: (value) => Money.fromInput(value ?? '') == null
                  ? 'Informe o saldo inicial.'
                  : null,
            ),
            const SizedBox(height: 16),
            DateField(
              label: 'Data do saldo inicial',
              value: _date,
              lastDate: DateTime(2100),
              errorText: fieldErrors['opening_balance_date'],
              onChanged: (date) => setState(() => _date = date),
            ),
            const SizedBox(height: 8),
            Text(
              'Recebimentos anteriores a esta data não são aceitos nesta conta.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text('Salvar conta'),
            ),
          ],
        ),
      ),
    );
  }
}
