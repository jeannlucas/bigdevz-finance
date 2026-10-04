import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../ui/date_field.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import 'agreement_screen.dart';
import 'agreements_repository.dart';

class AgreementFormScreen extends StatefulWidget {
  const AgreementFormScreen({super.key, required this.space});

  final Space space;

  @override
  State<AgreementFormScreen> createState() => _AgreementFormScreenState();
}

class _AgreementFormScreenState extends State<AgreementFormScreen> {
  final _form = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _total = TextEditingController();
  final _count = TextEditingController(text: '12');
  DateTime _firstDue = DateUtils.dateOnly(DateTime.now());
  bool _saving = false;
  ApiException? _error;

  @override
  void dispose() {
    _description.dispose();
    _total.dispose();
    _count.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final agreement = await context.read<AgreementsRepository>().create(
        widget.space.id,
        description: _description.text.trim(),
        total: Money.fromInput(_total.text)!,
        installmentCount: int.parse(_count.text),
        firstDueDate: toApiDate(_firstDue),
      );
      if (!mounted) return;
      context.read<SessionController>().dataChanged();
      Navigator.of(context).pushReplacement(
        spaceRoute(
          isPf: widget.space.isPf,
          child: AgreementScreen(
            space: widget.space,
            agreementId: agreement.id,
          ),
        ),
      );
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
      appBar: AppBar(title: const Text('Novo acordo a receber')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SpaceBadge(widget.space, prefix: 'Acordo do espaço'),
            const SizedBox(height: 20),
            if (_error != null && fieldErrors.isEmpty) ...[
              FormErrorBanner(_error!.message),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _description,
              decoration: InputDecoration(
                labelText: 'Descrição',
                hintText: 'Ex.: Venda de veículo',
                errorText: fieldErrors['description'],
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLength: 120,
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Descreva o acordo.' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _total,
              decoration: InputDecoration(
                labelText: 'Valor total',
                prefixText: r'R$ ',
                errorText: fieldErrors['total'],
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [MoneyInputFormatter()],
              validator: (value) =>
                  (Money.fromInput(value ?? '')?.cents ?? 0) > 0
                  ? null
                  : 'Informe o valor total.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _count,
              decoration: InputDecoration(
                labelText: 'Quantidade de parcelas',
                errorText: fieldErrors['installment_count'],
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              validator: (value) {
                final count = int.tryParse(value ?? '');
                return count == null || count < 1 || count > 1200
                    ? 'Informe de 1 a 1200 parcelas.'
                    : null;
              },
            ),
            const SizedBox(height: 16),
            DateField(
              label: 'Primeiro vencimento',
              value: _firstDue,
              errorText: fieldErrors['first_due_date'],
              onChanged: (date) => setState(() => _firstDue = date),
            ),
            const SizedBox(height: 8),
            Text(
              'As parcelas são calculadas pela API: centavos restantes vão para as primeiras, e o dia do primeiro '
              'vencimento é mantido (no mês sem esse dia, usa o último dia do mês).',
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
                  : const Text('Gerar parcelas'),
            ),
          ],
        ),
      ),
    );
  }
}
