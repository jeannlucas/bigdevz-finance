import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../ui/date_field.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import 'payable.dart';
import 'payables_repository.dart';

/// Edita esta obrigação (ou ocorrência). Em fatura, informa ou corrige o
/// total. O valor nunca fica abaixo do pago líquido; a alteração fica no
/// histórico e não muda nenhum saldo.
class PayableEditScreen extends StatefulWidget {
  const PayableEditScreen({
    super.key,
    required this.space,
    required this.payable,
  });

  final Space space;
  final Payable payable;

  @override
  State<PayableEditScreen> createState() => _PayableEditScreenState();
}

class _PayableEditScreenState extends State<PayableEditScreen> {
  final _form = GlobalKey<FormState>();
  late final _description = TextEditingController(
    text: widget.payable.description,
  );
  late final _payee = TextEditingController(text: widget.payable.payee ?? '');
  late final _amount = TextEditingController(
    text: widget.payable.amount?.plain ?? '',
  );
  final _reason = TextEditingController();
  late DateTime _due = parseApiDate(widget.payable.dueDate);
  bool _saving = false;
  ApiException? _error;

  @override
  void dispose() {
    for (final controller in [_description, _payee, _amount, _reason]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<PayablesRepository>().update(
        widget.space.id,
        widget.payable.id,
        {
          'description': _description.text.trim(),
          'payee': _payee.text.trim().isEmpty ? null : _payee.text.trim(),
          'amount': Money.fromInput(_amount.text)!.toApi(),
          'due_date': toApiDate(_due),
          if (_reason.text.trim().isNotEmpty) 'reason': _reason.text.trim(),
        },
      );
      if (!mounted) return;
      context.read<SessionController>().dataChanged();
      Navigator.of(context).pop(
        widget.payable.isCardBill
            ? 'Total da fatura salvo.'
            : 'Conta a pagar atualizada.',
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payable = widget.payable;
    final fieldErrors = _error?.fieldErrors ?? const {};
    return Scaffold(
      appBar: AppBar(
        title: Text(
          payable.isCardBill ? 'Total da fatura' : 'Editar conta a pagar',
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SpaceBadge(widget.space, prefix: 'Espaço'),
            const SizedBox(height: 16),
            if (_error != null && fieldErrors.isEmpty) ...[
              FormErrorBanner(_error!.message),
              const SizedBox(height: 16),
            ],
            if (!payable.isCardBill) ...[
              TextFormField(
                controller: _description,
                decoration: InputDecoration(
                  labelText: 'Descrição',
                  errorText: fieldErrors['description'],
                ),
                maxLength: 120,
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Informe a descrição.'
                    : null,
              ),
              TextFormField(
                controller: _payee,
                decoration: const InputDecoration(
                  labelText: 'Beneficiário (opcional)',
                ),
                maxLength: 120,
              ),
            ],
            TextFormField(
              controller: _amount,
              decoration: InputDecoration(
                labelText: payable.isCardBill ? 'Total da fatura' : 'Valor',
                prefixText: r'R$ ',
                helperText: payable.paid.isZero
                    ? null
                    : 'Mínimo: ${payable.paid.brl} (já pago).',
                errorText: fieldErrors['amount'],
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [MoneyInputFormatter()],
              validator: (value) {
                final amount = Money.fromInput(value ?? '');
                if (amount == null || amount.isZero) return 'Informe o valor.';
                if (amount.cents < payable.paid.cents) {
                  return 'Não pode ficar abaixo do pago líquido (${payable.paid.brl}).';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DateField(
              label: 'Vencimento',
              value: _due,
              lastDate: DateTime(2100),
              errorText: fieldErrors['due_date'],
              onChanged: (date) => setState(() => _due = date),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _reason,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional, fica no histórico)',
              ),
              maxLength: 500,
            ),
            if (payable.recurrenceId != null)
              Text(
                'Vale só para esta ocorrência. Para as futuras, use "Alterar ocorrências futuras".',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(
                payable.isCardBill ? 'Salvar total' : 'Salvar alterações',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}
