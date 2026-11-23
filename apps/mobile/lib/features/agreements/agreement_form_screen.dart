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
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import '../categories/category_picker_field.dart';
import '../payables/payable.dart' show RecurrencePreview;
import 'agreements_repository.dart';

enum _AgreementKind { single, installment, recurring }

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
  final _descriptionFocus = FocusNode();
  final _totalFocus = FocusNode();
  final _countFocus = FocusNode();
  final _descriptionKey = GlobalKey();
  final _totalKey = GlobalKey();
  final _countKey = GlobalKey();
  final _description = TextEditingController();
  final _total = TextEditingController();
  final _estimatedAmount = TextEditingController();
  final _count = TextEditingController(text: '1');
  _AgreementKind _kind = _AgreementKind.single;
  _InstallmentAmountMode _installmentAmountMode =
      _InstallmentAmountMode.byInstallment;
  bool _isVariable = false;
  int? _selectedCategoryId;
  DateTime _firstDue = DateUtils.dateOnly(DateTime.now());
  DateTime? _endDate;
  RecurrencePreview? _recurrence;
  String? _recurrenceFor;
  bool _confirmPast = false;
  bool _saving = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _count.addListener(_onCountChanged);
    _total.addListener(_onCountChanged);
    _estimatedAmount.addListener(_onCountChanged);
  }

  void _onCountChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _count.removeListener(_onCountChanged);
    _total.removeListener(_onCountChanged);
    _descriptionFocus.dispose();
    _totalFocus.dispose();
    _countFocus.dispose();
    _estimatedAmount.removeListener(_onCountChanged);
    _description.dispose();
    _total.dispose();
    _estimatedAmount.dispose();
    _count.dispose();
    super.dispose();
  }

  Money? get _computedTotal {
    final inputMoney = Money.fromInput(_total.text);
    if (inputMoney == null) return null;
    if (_kind == _AgreementKind.single || _kind == _AgreementKind.recurring) {
      return inputMoney;
    }
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
    if (_kind == _AgreementKind.single || _kind == _AgreementKind.recurring) {
      return inputMoney;
    }
    final count = int.tryParse(_count.text) ?? 2;
    if (count <= 1) return inputMoney;
    if (_installmentAmountMode == _InstallmentAmountMode.byInstallment) {
      return inputMoney;
    }
    return Money(inputMoney.cents ~/ count);
  }

  String _recurrenceKey() =>
      '${_isVariable}_${_total.text}_${_estimatedAmount.text}_${toApiDate(_firstDue)}_${_endDate == null ? '' : toApiDate(_endDate!)}';

  bool get _recurrenceCurrent =>
      _recurrence != null && _recurrenceFor == _recurrenceKey();

  Future<void> _previewRecurrence() async {
    if (!_form.currentState!.validate()) {
      if (_description.text.trim().isEmpty) {
        focusAndEnsureVisible(
          _descriptionFocus,
          context: _descriptionKey.currentContext,
        );
      } else if (!_isVariable) {
        focusAndEnsureVisible(_totalFocus, context: _totalKey.currentContext);
      }
      return;
    }
    final key = _recurrenceKey();
    final repository = context.read<AgreementsRepository>();
    try {
      final amountInput = Money.fromInput(_total.text);
      final estimatedInput = Money.fromInput(_estimatedAmount.text);
      final preview = await repository.recurrencePreview(
        widget.space.id,
        amount: amountInput?.isZero == true ? null : amountInput,
        startDate: toApiDate(_firstDue),
        endDate: _endDate == null ? null : toApiDate(_endDate!),
        isVariable: _isVariable,
        estimatedAmount: estimatedInput?.isZero == true ? null : estimatedInput,
      );
      if (mounted) {
        setState(() {
          _recurrence = preview;
          _recurrenceFor = key;
          _confirmPast = false;
          _error = null;
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    }
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

  Widget _buildRecurringModeSelector() {
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: false,
          label: Text('Valor Fixo'),
          icon: Icon(Icons.lock_outline_rounded, size: 16),
        ),
        ButtonSegment(
          value: true,
          label: Text('Valor Variável'),
          icon: Icon(Icons.tune_rounded, size: 16),
        ),
      ],
      selected: {_isVariable},
      onSelectionChanged: (set) {
        if (set.isNotEmpty) {
          setState(() {
            _isVariable = set.first;
            _recurrence = null;
          });
        }
      },
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final isInstallment = _kind == _AgreementKind.installment;
    final count = int.tryParse(_count.text) ?? (isInstallment ? 2 : 1);
    if (!_form.currentState!.validate()) {
      if (_description.text.trim().isEmpty) {
        focusAndEnsureVisible(
          _descriptionFocus,
          context: _descriptionKey.currentContext,
        );
      } else {
        final amount = Money.fromInput(_total.text);
        if (amount == null ||
            amount.isZero ||
            (isInstallment &&
                _installmentAmountMode ==
                    _InstallmentAmountMode.byInstallment &&
                amount.cents * count > Money.maxCents)) {
          focusAndEnsureVisible(_totalFocus, context: _totalKey.currentContext);
        } else if (isInstallment) {
          final parsedCount = int.tryParse(_count.text);
          if (parsedCount == null || parsedCount < 1 || parsedCount > 1200) {
            focusAndEnsureVisible(
              _countFocus,
              context: _countKey.currentContext,
            );
          }
        }
      }
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final agreement = await switch (_kind) {
        _AgreementKind.single => context.read<AgreementsRepository>().create(
          widget.space.id,
          kind: 'single',
          description: _description.text.trim(),
          total: Money.fromInput(_total.text)!,
          installmentCount: 1,
          firstDueDate: toApiDate(_firstDue),
          categoryId: _selectedCategoryId,
        ),
        _AgreementKind.installment =>
          context.read<AgreementsRepository>().create(
            widget.space.id,
            kind: 'installment',
            description: _description.text.trim(),
            total: _computedTotal ?? Money.fromInput(_total.text)!,
            installmentCount: int.tryParse(_count.text) ?? 2,
            firstDueDate: toApiDate(_firstDue),
            categoryId: _selectedCategoryId,
          ),
        _AgreementKind.recurring => () {
          final amountInput = Money.fromInput(_total.text);
          final estimatedInput = Money.fromInput(_estimatedAmount.text);
          return context.read<AgreementsRepository>().create(
            widget.space.id,
            kind: 'recurring',
            description: _description.text.trim(),
            isVariable: _isVariable,
            amount: _isVariable
                ? (amountInput != null && !amountInput.isZero
                      ? amountInput
                      : null)
                : amountInput,
            estimatedAmount:
                _isVariable && estimatedInput != null && !estimatedInput.isZero
                ? estimatedInput
                : null,
            startDate: toApiDate(_firstDue),
            endDate: _endDate == null ? null : toApiDate(_endDate!),
            approvedUntil: _recurrenceCurrent
                ? _recurrence?.approvedUntil
                : null,
            confirmPast: _confirmPast,
            categoryId: _selectedCategoryId,
          );
        }(),
      };
      if (!mounted) return;
      context.read<SessionController>().dataChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _kind == _AgreementKind.recurring
                ? 'Receita recorrente cadastrada com sucesso.'
                : 'Conta a receber cadastrada com sucesso.',
          ),
        ),
      );
      Navigator.of(context).pop(agreement);
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
    final isRecurring = _kind == _AgreementKind.recurring;
    final count = int.tryParse(_count.text) ?? (isInstallment ? 2 : 1);

    final amountField = TextFormField(
      key: _totalKey,
      focusNode: _totalFocus,
      controller: _total,
      decoration: InputDecoration(
        labelText: switch (_kind) {
          _AgreementKind.single => 'Valor *',
          _AgreementKind.installment =>
            _installmentAmountMode == _InstallmentAmountMode.byInstallment
                ? 'Valor da parcela *'
                : 'Valor total *',
          _AgreementKind.recurring =>
            _isVariable
                ? 'Valor da 1ª ocorrência (opcional)'
                : 'Valor mensal *',
        },
        prefixText: r'R$ ',
        hintText: '0,00',
        helperText: isRecurring && _isVariable
            ? 'Se preenchido, aplica-se apenas à 1ª ocorrência. As demais aguardarão valor.'
            : null,
        errorText: fieldErrors['total'] ?? fieldErrors['amount'],
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [MoneyInputFormatter()],
      validator: (value) {
        final amount = Money.fromInput(value ?? '');
        if (isRecurring && _isVariable) {
          if (amount != null && amount.cents > Money.maxCents) {
            return 'Valor excede o limite suportado.';
          }
          return null;
        }
        if (amount == null || amount.isZero) {
          if (isRecurring) {
            return 'Informe o valor mensal.';
          }
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

    final estimatedAmountField = TextFormField(
      controller: _estimatedAmount,
      decoration: InputDecoration(
        labelText: 'Estimativa de valor (opcional, para planejamento)',
        prefixText: r'R$ ',
        hintText: '0,00',
        helperText:
            'Aguardando valor: o valor exato será informado a cada mês.',
        errorText: fieldErrors['estimated_amount'],
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [MoneyInputFormatter()],
      validator: (value) {
        final amount = Money.fromInput(value ?? '');
        if (amount != null && amount.cents > Money.maxCents) {
          return 'Valor excede o limite suportado.';
        }
        return null;
      },
    );

    final countField = TextFormField(
      key: _countKey,
      focusNode: _countFocus,
      controller: _count,
      decoration: InputDecoration(
        labelText: isDesktop ? 'Parcelas *' : 'Quantidade de parcelas *',
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
      label: switch (_kind) {
        _AgreementKind.single => 'Vencimento *',
        _AgreementKind.installment => 'Primeiro vencimento *',
        _AgreementKind.recurring => 'Data de início *',
      },
      helperText: isRecurring
          ? 'O dia escolhido será usado como referência nos meses seguintes.'
          : null,
      value: _firstDue,
      errorText:
          fieldErrors['first_due_date'] ??
          fieldErrors['due_date'] ??
          fieldErrors['start_date'],
      onChanged: (date) => setState(() {
        _firstDue = date;
        _recurrence = null;
      }),
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
            _recurrence = null;
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
        key: _descriptionKey,
        focusNode: _descriptionFocus,
        controller: _description,
        inputFormatters: const [UpperCaseTextFormatter()],
        decoration: InputDecoration(
          labelText: 'Descrição *',
          hintText: 'Ex.: Salário, Venda de veículo, Consultoria',
          errorText: fieldErrors['description'],
        ),
        maxLength: 120,
        validator: (value) =>
            (value ?? '').trim().isEmpty ? 'Informe a descrição.' : null,
      ),
      const SizedBox(height: 12),
      CategoryPickerField(
        spaceId: widget.space.id,
        type: 'income',
        selectedCategoryId: _selectedCategoryId,
        onChanged: (catId) => setState(() => _selectedCategoryId = catId),
      ),
      const SizedBox(height: 12),
      if (isDesktop && _kind == _AgreementKind.single)
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
      ] else if (isDesktop && isRecurring) ...[
        _buildRecurringModeSelector(),
        if (_isVariable) ...[const SizedBox(height: 12), estimatedAmountField],
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: amountField),
            const SizedBox(width: AppTokens.p16),
            Expanded(flex: 3, child: dateField),
          ],
        ),
      ] else ...[
        if (isInstallment) ...[
          _buildInstallmentModeSelector(),
          const SizedBox(height: 16),
        ],
        if (isRecurring) ...[
          _buildRecurringModeSelector(),
          if (_isVariable) ...[
            const SizedBox(height: 12),
            estimatedAmountField,
          ],
          const SizedBox(height: 16),
        ],
        amountField,
        if (isInstallment) ...[const SizedBox(height: 16), countField],
        const SizedBox(height: 16),
        dateField,
      ],
      if (isRecurring) ...[
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Com data de término'),
          value: _endDate != null,
          onChanged: (on) => setState(() {
            _endDate = on ? _firstDue : null;
            _recurrence = null;
          }),
        ),
        if (_endDate != null) ...[
          const SizedBox(height: 8),
          DateField(
            label: 'Última ocorrência até',
            value: _endDate!,
            firstDate: _firstDue,
            lastDate: DateTime(2100),
            errorText: fieldErrors['end_date'],
            onChanged: (date) => setState(() {
              _endDate = date;
              _recurrence = null;
            }),
          ),
        ],
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: _previewRecurrence,
          child: const Text('Revisar ocorrências'),
        ),
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
      if (isRecurring && _recurrenceCurrent) ...[
        const SizedBox(height: 8),
        _RecurrenceReview(
          preview: _recurrence!,
          amount:
              Money.fromInput(_total.text) ??
              Money.fromInput(_estimatedAmount.text) ??
              const Money(0),
          confirmPast: _confirmPast,
          onConfirmPast: (val) => setState(() => _confirmPast = val),
        ),
      ],
      const SizedBox(height: 8),
      Text(
        switch (_kind) {
          _AgreementKind.single => 'Recebimento à vista ou parcela única.',
          _AgreementKind.installment =>
            'As $count parcelas somam o valor total. Nos meses sem o dia escolhido, o vencimento será no último dia do mês.',
          _AgreementKind.recurring => 'Cadastrar não altera o saldo. O recebimento é registrado a cada ocorrência.',
        },
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
        label: Text(switch (_kind) {
          _AgreementKind.single => 'Salvar conta a receber',
          _AgreementKind.installment => 'Gerar parcelas',
          _AgreementKind.recurring => 'Confirmar recorrência',
        }),
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
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(
                left: AppTokens.p16,
                right: AppTokens.p16,
                top: AppTokens.p16,
                bottom:
                    AppTokens.p16 +
                    (MediaQuery.viewInsetsOf(context).bottom > 0 ? 32 : 0),
              ),
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
    (_AgreementKind.recurring, 'Recorrente'),
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

class _RecurrenceReview extends StatelessWidget {
  const _RecurrenceReview({
    required this.preview,
    required this.amount,
    required this.confirmPast,
    required this.onConfirmPast,
  });

  final RecurrencePreview preview;
  final Money amount;
  final bool confirmPast;
  final ValueChanged<bool> onConfirmPast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget line(String id, String label, String value) => Padding(
      key: ValueKey('recurrence-$id'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Flexible(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
    final horizon = parseApiDate(preview.horizon);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ocorrências que serão criadas',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            line('Inicio', 'Início', formatDateBr(preview.firstDueDate)),
            line('Dia', 'Dia de referência', '${preview.referenceDay}'),
            line('Valor', 'Valor base', amount.brl),
            line(
              'Fim',
              'Término',
              preview.endDate == null
                  ? 'sem término'
                  : formatDateBr(preview.endDate!),
            ),
            line(
              'Periodo',
              'Período deste cadastro',
              '${formatDateBr(preview.firstDueDate)} a ${formatDateBr(preview.lastDueDate)}',
            ),
            line(
              'Quantidade',
              'Ocorrências',
              '${preview.count} · total ${preview.total.brl}',
            ),
            line(
              'Horizonte',
              'Horizonte',
              'até ${horizon.month.toString().padLeft(2, '0')}/${horizon.year}',
            ),
            if (preview.pastCount > 0) ...[
              const SizedBox(height: 8),
              FormErrorBanner(
                '${preview.pastCount} ${preview.pastCount == 1 ? 'ocorrência já venceu' : 'ocorrências já venceram'} '
                '(total ${preview.pastTotal.brl}). Elas serão criadas em aberto, '
                'sem recebimento e sem mudar saldo.',
              ),
              CheckboxListTile(
                key: const ValueKey('confirm-past'),
                contentPadding: EdgeInsets.zero,
                value: confirmPast,
                onChanged: (value) => onConfirmPast(value ?? false),
                title: Text(
                  'Confirmo a criação das ${preview.pastCount} ocorrências vencidas',
                ),
              ),
            ],
            const SizedBox(height: 8),
            for (final item in preview.items)
              Text(
                '${formatDateBr(item.dueDate)}${item.past ? ' · vencida' : ''}',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
