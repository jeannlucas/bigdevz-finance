import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../../ui/date_field.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import 'agreement_screen.dart';
import 'agreements_repository.dart';

/// Abre o fluxo de cadastro de conta a receber (Modal Dialog em Desktop / Bottom Sheet em Mobile).
Future<void> showAgreementFormModal(
  BuildContext context, {
  required Space space,
}) {
  final isDesktop = MediaQuery.sizeOf(context).width >= 640;
  if (isDesktop) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.r24),
        ),
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: SingleChildScrollView(
            child: AgreementFormScreen(space: space, asModal: true),
          ),
        ),
      ),
    );
  } else {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTokens.r24),
        ),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SingleChildScrollView(
          child: AgreementFormScreen(space: space, asModal: true),
        ),
      ),
    );
  }
}

class AgreementFormScreen extends StatefulWidget {
  const AgreementFormScreen({
    super.key,
    required this.space,
    this.asModal = false,
  });

  final Space space;
  final bool asModal;

  @override
  State<AgreementFormScreen> createState() => _AgreementFormScreenState();
}

class _AgreementFormScreenState extends State<AgreementFormScreen> {
  final _form = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _total = TextEditingController();
  final _count = TextEditingController(text: '1');
  DateTime _firstDue = DateUtils.dateOnly(DateTime.now());
  bool _saving = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _count.addListener(_onCountChanged);
  }

  void _onCountChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _count.removeListener(_onCountChanged);
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
      if (widget.asModal) {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          spaceRoute(
            isPf: widget.space.isPf,
            child: AgreementScreen(
              space: widget.space,
              agreementId: agreement.id,
            ),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          spaceRoute(
            isPf: widget.space.isPf,
            child: AgreementScreen(
              space: widget.space,
              agreementId: agreement.id,
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fieldErrors = _error?.fieldErrors ?? const {};
    final isDesktop = MediaQuery.sizeOf(context).width >= 640;
    final count = int.tryParse(_count.text) ?? 1;
    final isSingleInstallment = count <= 1;

    final formChildren = [
      Align(
        alignment: Alignment.centerLeft,
        child: SpaceBadge(widget.space, prefix: 'Conta a receber do espaço'),
      ),
      const SizedBox(height: 20),
      if (_error != null && fieldErrors.isEmpty) ...[
        FormErrorBanner(_error!.message),
        const SizedBox(height: 16),
      ],
      TextFormField(
        controller: _description,
        decoration: InputDecoration(
          labelText: 'Descrição',
          hintText: 'Ex.: Salário, Venda de veículo, Consultoria',
          errorText: fieldErrors['description'],
        ),
        textCapitalization: TextCapitalization.sentences,
        maxLength: 120,
        validator: (value) =>
            (value ?? '').trim().isEmpty ? 'Descreva a conta a receber.' : null,
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: _total,
        decoration: InputDecoration(
          labelText: 'Valor total',
          prefixText: r'R$ ',
          hintText: '0,00',
          errorText: fieldErrors['total'],
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [MoneyInputFormatter()],
        validator: (value) => (Money.fromInput(value ?? '')?.cents ?? 0) > 0
            ? null
            : 'Informe o valor total.',
      ),
      const SizedBox(height: 16),
      if (isDesktop)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _count,
                decoration: InputDecoration(
                  labelText: 'Parcelas',
                  hintText: '1',
                  errorText: fieldErrors['installment_count'],
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                validator: (value) {
                  final parsed = int.tryParse(value ?? '');
                  return parsed == null || parsed < 1 || parsed > 1200
                      ? 'Informe de 1 a 1200.'
                      : null;
                },
              ),
            ),
            const SizedBox(width: AppTokens.p16),
            Expanded(
              flex: 3,
              child: DateField(
                label: 'Primeiro vencimento',
                value: _firstDue,
                errorText: fieldErrors['first_due_date'],
                onChanged: (date) => setState(() => _firstDue = date),
              ),
            ),
          ],
        )
      else ...[
        TextFormField(
          controller: _count,
          decoration: InputDecoration(
            labelText: 'Quantidade de parcelas',
            hintText: '1',
            errorText: fieldErrors['installment_count'],
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          validator: (value) {
            final parsed = int.tryParse(value ?? '');
            return parsed == null || parsed < 1 || parsed > 1200
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
      ],
      const SizedBox(height: 8),
      Text(
        isSingleInstallment
            ? 'Recebimento à vista ou parcela única.'
            : 'As $count parcelas somam o valor total. Nos meses sem o dia escolhido, o vencimento será no último dia do mês.',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const AppIcon(AppIcons.check, size: 18),
        label: Text(
          isSingleInstallment ? 'Salvar conta a receber' : 'Gerar parcelas',
        ),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    ];

    if (widget.asModal) {
      return Padding(
        padding: const EdgeInsets.all(AppTokens.p24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Nova conta a receber',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...formChildren,
            ],
          ),
        ),
      );
    }

    final content = Form(
      key: _form,
      child: isDesktop
          ? Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.p24,
                  vertical: AppTokens.p32,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 580),
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.r20),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant
                            .withValues(alpha: 0.6),
                      ),
                    ),
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.all(AppTokens.p24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: formChildren,
                      ),
                    ),
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(AppTokens.p16),
              children: formChildren,
            ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Nova conta a receber')),
      body: content,
    );
  }
}
