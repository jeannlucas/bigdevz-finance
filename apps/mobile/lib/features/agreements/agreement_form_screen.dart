import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/text_formatters.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../../ui/date_field.dart';
import '../../ui/installment_summary_card.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import '../categories/category_picker_field.dart';
import 'agreement_screen.dart';
import 'agreements_repository.dart';

enum _AgreementKind { single, installment }

enum _InstallmentAmountMode { byInstallment, byTotal }

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
          constraints: BoxConstraints(
            maxWidth: 580,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.85,
          ),
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
  _AgreementKind _kind = _AgreementKind.single;
  _InstallmentAmountMode _installmentAmountMode =
      _InstallmentAmountMode.byInstallment;
  int? _selectedCategoryId;
  DateTime _firstDue = DateUtils.dateOnly(DateTime.now());
  bool _saving = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _count.addListener(_onCountChanged);
    _total.addListener(_onCountChanged);
  }

  void _onCountChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _count.removeListener(_onCountChanged);
    _total.removeListener(_onCountChanged);
    _description.dispose();
    _total.dispose();
    _count.dispose();
    super.dispose();
  }

  Money? get _computedTotal {
    final inputMoney = Money.fromInput(_total.text);
    if (inputMoney == null) return null;
    if (_kind == _AgreementKind.single) return inputMoney;
    final count = int.tryParse(_count.text) ?? 2;
    if (count <= 1) return inputMoney;
    if (_installmentAmountMode == _InstallmentAmountMode.byInstallment) {
      final totalCents = inputMoney.cents * count;
      if (totalCents > Money.maxCents) return null;
      return Money(totalCents);
    }
    return inputMoney;
  }

  Money? get _computedPerInstallmentAmount {
    final inputMoney = Money.fromInput(_total.text);
    if (inputMoney == null) return null;
    if (_kind == _AgreementKind.single) return inputMoney;
    final count = int.tryParse(_count.text) ?? 2;
    if (count <= 1) return inputMoney;
    if (_installmentAmountMode == _InstallmentAmountMode.byInstallment) {
      return inputMoney;
    }
    return Money(inputMoney.cents ~/ count);
  }

  Widget _buildInstallmentModeSelector() {
    return SegmentedButton<_InstallmentAmountMode>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: const [
        ButtonSegment(
          value: _InstallmentAmountMode.byInstallment,
          label: Text('Valor da parcela'),
          icon: Icon(Icons.pin_outlined, size: 16),
        ),
        ButtonSegment(
          value: _InstallmentAmountMode.byTotal,
          label: Text('Valor total'),
          icon: Icon(Icons.all_inclusive, size: 16),
        ),
      ],
      selected: {_installmentAmountMode},
      onSelectionChanged: (newSelection) {
        if (newSelection.isEmpty) return;
        final newMode = newSelection.first;
        if (newMode == _installmentAmountMode) return;
        final currentMoney = Money.fromInput(_total.text);
        final count = int.tryParse(_count.text);
        if (currentMoney != null && count != null && count > 0) {
          if (newMode == _InstallmentAmountMode.byTotal) {
            final totalCents = currentMoney.cents * count;
            if (totalCents <= Money.maxCents) {
              _total.text = Money(totalCents).plain;
            }
          } else {
            final perInstallment = currentMoney.cents ~/ count;
            _total.text = Money(perInstallment).plain;
          }
        }
        setState(() {
          _installmentAmountMode = newMode;
        });
      },
    );
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final count = _kind == _AgreementKind.single
          ? 1
          : (int.tryParse(_count.text) ?? 2);
      final agreement = await context.read<AgreementsRepository>().create(
        widget.space.id,
        description: _description.text.trim(),
        total: _computedTotal ?? Money.fromInput(_total.text)!,
        installmentCount: count,
        firstDueDate: toApiDate(_firstDue),
        categoryId: _selectedCategoryId,
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
    final isInstallment = _kind == _AgreementKind.installment;
    final count = int.tryParse(_count.text) ?? (isInstallment ? 2 : 1);

    final amountField = TextFormField(
      controller: _total,
      decoration: InputDecoration(
        labelText: isInstallment
            ? (_installmentAmountMode == _InstallmentAmountMode.byInstallment
                  ? 'Valor da parcela'
                  : 'Valor total')
            : 'Valor',
        prefixText: r'R$ ',
        hintText: '0,00',
        errorText: fieldErrors['total'],
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [MoneyInputFormatter()],
      validator: (value) {
        final amount = Money.fromInput(value ?? '');
        if (amount == null || amount.isZero) {
          return isInstallment &&
                  _installmentAmountMode == _InstallmentAmountMode.byInstallment
              ? 'Informe o valor da parcela.'
              : 'Informe o valor.';
        }
        if (isInstallment &&
            _installmentAmountMode == _InstallmentAmountMode.byInstallment) {
          if (amount.cents * count > Money.maxCents) {
            return 'Valor total excede o limite suportado.';
          }
        }
        return null;
      },
    );

    final countField = TextFormField(
      controller: _count,
      decoration: InputDecoration(
        labelText: isDesktop ? 'Parcelas' : 'Quantidade de parcelas',
        hintText: '2',
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
    );

    final dateField = DateField(
      label: isInstallment ? 'Primeiro vencimento' : 'Vencimento',
      value: _firstDue,
      errorText: fieldErrors['first_due_date'],
      onChanged: (date) => setState(() => _firstDue = date),
    );

    final formChildren = [
      Align(
        alignment: Alignment.centerLeft,
        child: SpaceBadge(widget.space, prefix: 'Conta a receber do espaço'),
      ),
      const SizedBox(height: 16),
      if (_error != null && fieldErrors.isEmpty) ...[
        FormErrorBanner(_error!.message),
        const SizedBox(height: 16),
      ],
      _AgreementKindSelector(
        selected: _kind,
        onChanged: (kind) {
          setState(() {
            _kind = kind;
            if (kind == _AgreementKind.installment) {
              final parsed = int.tryParse(_count.text) ?? 1;
              if (parsed <= 1) _count.text = '2';
            } else {
              _count.text = '1';
            }
          });
        },
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _description,
        inputFormatters: const [UpperCaseTextFormatter()],
        decoration: InputDecoration(
          labelText: 'Descrição',
          hintText: 'Ex.: Salário, Venda de veículo, Consultoria',
          errorText: fieldErrors['description'],
        ),
        maxLength: 120,
        validator: (value) =>
            (value ?? '').trim().isEmpty ? 'Descreva a conta a receber.' : null,
      ),
      const SizedBox(height: 12),
      CategoryPickerField(
        spaceId: widget.space.id,
        type: 'income',
        selectedCategoryId: _selectedCategoryId,
        onChanged: (catId) => setState(() => _selectedCategoryId = catId),
      ),
      const SizedBox(height: 12),
      if (isDesktop && !isInstallment)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: amountField),
            const SizedBox(width: AppTokens.p16),
            Expanded(flex: 3, child: dateField),
          ],
        )
      else if (isDesktop && isInstallment) ...[
        _buildInstallmentModeSelector(),
        const SizedBox(height: 16),
        amountField,
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: countField),
            const SizedBox(width: AppTokens.p16),
            Expanded(flex: 3, child: dateField),
          ],
        ),
      ] else ...[
        if (isInstallment) ...[
          _buildInstallmentModeSelector(),
          const SizedBox(height: 16),
        ],
        amountField,
        if (isInstallment) ...[const SizedBox(height: 16), countField],
        const SizedBox(height: 16),
        dateField,
      ],
      if (isInstallment &&
          _computedTotal != null &&
          _computedPerInstallmentAmount != null &&
          count > 0) ...[
        const SizedBox(height: 14),
        InstallmentSummaryCard(
          installmentCount: count,
          installmentAmount: _computedPerInstallmentAmount!,
          totalAmount: _computedTotal!,
          isByInstallmentMode:
              _installmentAmountMode == _InstallmentAmountMode.byInstallment,
        ),
      ],
      const SizedBox(height: 8),
      Text(
        !isInstallment
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
          !isInstallment ? 'Salvar conta a receber' : 'Gerar parcelas',
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
          onChanged: () => setState(() {}),
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
      onChanged: () => setState(() {}),
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

class _AgreementKindSelector extends StatelessWidget {
  const _AgreementKindSelector({
    required this.selected,
    required this.onChanged,
  });

  final _AgreementKind selected;
  final ValueChanged<_AgreementKind> onChanged;

  static const _options = [
    (_AgreementKind.single, 'Avulsa'),
    (_AgreementKind.installment, 'Parcelada'),
  ];

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_AgreementKind>(
      showSelectedIcon: false,
      segments: [
        for (final (kind, label) in _options)
          ButtonSegment(
            value: kind,
            label: Text(
              label,
              maxLines: 1,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
      ],
      selected: {selected},
      onSelectionChanged: (set) {
        if (set.isNotEmpty) onChanged(set.first);
      },
    );
  }
}
