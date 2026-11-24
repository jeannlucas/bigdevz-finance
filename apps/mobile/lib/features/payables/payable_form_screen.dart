import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/text_formatters.dart';
import '../../ui/app_tokens.dart';
import '../../ui/date_field.dart';
import '../../ui/installment_summary_card.dart';
import '../../ui/widgets.dart';
import '../agreements/receipt_attempt.dart' show ReceiptAttemptState;
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import '../categories/category_picker_field.dart';
import 'payable.dart';
import 'payable_creations.dart';
import 'payables_repository.dart';
import 'pending_creation_card.dart';

enum _Kind { single, installment, recurring }

enum _InstallmentAmountMode { byInstallment, byTotal }

/// Abre o fluxo de cadastro de conta a pagar (Modal Dialog em Desktop / Bottom Sheet em Mobile).
Future<void> showPayableFormModal(
  BuildContext context, {
  required Space space,
  DateTime? today,
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
            maxWidth: 620,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.85,
          ),
          child: PayableFormScreen(space: space, today: today, asModal: true),
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
        child: FractionallySizedBox(
          heightFactor: 0.92,
          child: PayableFormScreen(space: space, today: today, asModal: true),
        ),
      ),
    );
  }
}

/// Cadastro de conta a pagar: avulsa, parcelada (prévia do cronograma) ou
/// recorrente (revisão do período, com confirmação das já vencidas). Não
/// altera saldo. O formulário é rascunho; ao salvar, chave e conteúdo são
/// guardados antes do envio ([PayableCreations]) e, sem confirmação, a
/// tentativa fica pendente: esta tela abre na retomada até verificar.
class PayableFormScreen extends StatefulWidget {
  const PayableFormScreen({
    super.key,
    required this.space,
    this.today,
    this.asModal = false,
  });

  final Space space;
  final DateTime? today;
  final bool asModal;

  @override
  State<PayableFormScreen> createState() => _PayableFormScreenState();
}

class _PayableFormScreenState extends State<PayableFormScreen> {
  final _form = GlobalKey<FormState>();
  final _descriptionFocus = FocusNode();
  final _amountFocus = FocusNode();
  final _countFocus = FocusNode();
  final _descriptionKey = GlobalKey();
  final _amountKey = GlobalKey();
  final _countKey = GlobalKey();
  final _description = TextEditingController();
  final _payee = TextEditingController();
  final _amount = TextEditingController();
  final _estimatedAmount = TextEditingController();
  final _count = TextEditingController(text: '2');
  int? _selectedCategoryId;
  late DateTime _date = DateUtils.dateOnly(widget.today ?? DateTime.now());
  DateTime? _endDate;
  _Kind _kind = _Kind.single;
  bool _isVariable = false;
  _InstallmentAmountMode _installmentAmountMode =
      _InstallmentAmountMode.byInstallment;
  bool _suggestNextBankDay = false;
  ({int? cents, int? count, DateTime base, bool suggest})? _scheduleSource;
  final _manualScheduleDates = <int, String>{};
  List<ScheduleItem>? _schedule;
  List<TextEditingController> _scheduleAmountControllers = [];
  RecurrencePreview? _recurrence;
  String? _recurrenceFor;
  bool _confirmPast = false;
  bool _saving = false;
  bool _loadingPending = true;
  PendingCreation? _pending;
  String? _pendingNotice;
  ApiException? _error;
  String? _localError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPending());
  }

  @override
  void dispose() {
    _descriptionFocus.dispose();
    _amountFocus.dispose();
    _countFocus.dispose();
    for (final controller in [
      _description,
      _payee,
      _amount,
      _estimatedAmount,
      _count,
    ]) {
      controller.dispose();
    }
    for (final controller in _scheduleAmountControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Money? get _scheduleTotal {
    if (_schedule == null || _schedule!.isEmpty) return null;
    final totalCents = _schedule!.fold<int>(
      0,
      (sum, item) => sum + item.amount.cents,
    );
    return Money(totalCents);
  }

  Money? get _computedInstallmentTotal {
    final inputMoney = Money.fromInput(_amount.text);
    if (inputMoney == null) return null;
    final count = int.tryParse(_count.text);
    if (count == null || count < 1) return null;
    if (_installmentAmountMode == _InstallmentAmountMode.byInstallment) {
      final totalCents = inputMoney.cents * count;
      if (totalCents > Money.maxCents) return null;
      return Money(totalCents);
    }
    return inputMoney;
  }

  Money? get _computedPerInstallmentAmount {
    final inputMoney = Money.fromInput(_amount.text);
    if (inputMoney == null) return null;
    final count = int.tryParse(_count.text);
    if (count == null || count < 1) return null;
    if (_installmentAmountMode == _InstallmentAmountMode.byInstallment) {
      return inputMoney;
    }
    return Money(inputMoney.cents ~/ count);
  }

  Future<void> _loadPending() async {
    final user = context.read<SessionController>().user;
    final pending = user == null
        ? null
        : await context.read<PayableCreations>().pending(
            user.id,
            widget.space.id,
          );
    if (mounted) {
      setState(() {
        _pending = pending;
        _loadingPending = false;
      });
    }
  }

  /// Conteúdo do rascunho, sem a aprovação do período.
  Map<String, Object?>? _draft() {
    final amount = Money.fromInput(_amount.text);
    if (amount == null && !(_kind == _Kind.recurring && _isVariable)) {
      return null;
    }
    final common = {
      'description': _description.text.trim(),
      'payee': _payee.text.trim().isEmpty ? null : _payee.text.trim(),
      if (_selectedCategoryId != null) 'category_id': _selectedCategoryId,
    };
    return switch (_kind) {
      _Kind.single => {
        'kind': 'single',
        ...common,
        'amount': amount?.toApi(),
        'due_date': toApiDate(_date),
      },
      _Kind.installment => {
        'kind': 'installment',
        ...common,
        'total': (_scheduleTotal ?? _computedInstallmentTotal ?? amount)!
            .toApi(),
        'installment_count': int.tryParse(_count.text),
        'first_due_date': _schedule?.isNotEmpty == true
            ? _schedule!.first.dueDate
            : toApiDate(_date),
        if (_schedule != null && _schedule!.isNotEmpty)
          'installments': [
            for (final item in _schedule!)
              {
                'number': item.number,
                'amount': item.amount.toApi(),
                'due_date': item.dueDate,
              },
          ],
      },
      _Kind.recurring => {
        'kind': 'recurring',
        ...common,
        'is_variable': _isVariable,
        'amount': _isVariable
            ? (amount != null && !amount.isZero ? amount.toApi() : null)
            : amount?.toApi(),
        if (_isVariable && Money.fromInput(_estimatedAmount.text) != null)
          'estimated_amount': Money.fromInput(_estimatedAmount.text)!.toApi(),
        'start_date': toApiDate(_date),
        'end_date': _endDate == null ? null : toApiDate(_endDate!),
      },
    };
  }

  ({int? cents, int? count, DateTime base, bool suggest}) get _scheduleInputs =>
      (
        cents: _computedInstallmentTotal?.cents,
        count: int.tryParse(_count.text),
        base: _date,
        suggest: _suggestNextBankDay,
      );

  bool get _scheduleCurrent =>
      _schedule?.isNotEmpty == true && _scheduleSource == _scheduleInputs;
  bool get _recurrenceCurrent =>
      _recurrence != null && _recurrenceFor == _draft()?.toString();

  void _scrollToFirstInvalid() {
    if (_description.text.trim().isEmpty) {
      focusAndEnsureVisible(
        _descriptionFocus,
        context: _descriptionKey.currentContext,
      );
      return;
    }
    if (_kind != _Kind.recurring || !_isVariable) {
      final amount = Money.fromInput(_amount.text);
      if (amount == null || amount.isZero) {
        focusAndEnsureVisible(_amountFocus, context: _amountKey.currentContext);
        return;
      }
      if (_kind == _Kind.installment &&
          _installmentAmountMode == _InstallmentAmountMode.byInstallment) {
        final count = int.tryParse(_count.text) ?? 1;
        if (amount.cents * count > Money.maxCents) {
          focusAndEnsureVisible(
            _amountFocus,
            context: _amountKey.currentContext,
          );
          return;
        }
      }
    }
    if (_kind == _Kind.installment) {
      final count = int.tryParse(_count.text);
      if (count == null || count < 1 || count > 1200) {
        focusAndEnsureVisible(_countFocus, context: _countKey.currentContext);
        return;
      }
    }
  }

  void _onScheduleAmountChanged(int index, String text) {
    final money = Money.fromInput(text) ?? const Money(0);
    setState(() {
      _schedule![index] = (
        number: _schedule![index].number,
        amount: money,
        dueDate: _schedule![index].dueDate,
      );
    });
  }

  void _onScheduleDateChanged(int index, DateTime newDate) {
    final dateStr = toApiDate(newDate);
    setState(() {
      _schedule![index] = (
        number: _schedule![index].number,
        amount: _schedule![index].amount,
        dueDate: dateStr,
      );
      _manualScheduleDates[_schedule![index].number] = dateStr;
    });
  }

  Future<void> _preview() async {
    if (!_form.currentState!.validate()) {
      _scrollToFirstInvalid();
      return;
    }
    final draft = _draft().toString();
    final repository = context.read<PayablesRepository>();
    try {
      if (_kind == _Kind.installment) {
        final source = _scheduleInputs;
        final previousSource = _scheduleSource;
        final total =
            _computedInstallmentTotal ?? Money.fromInput(_amount.text)!;
        final schedule = await repository.preview(
          widget.space.id,
          total: total,
          count: source.count!,
          firstDueDate: toApiDate(source.base),
          suggestNextBankDay: source.suggest,
        );
        if (mounted &&
            _kind == _Kind.installment &&
            source == _scheduleInputs) {
          setState(() {
            final sameDates =
                previousSource?.base == source.base &&
                previousSource?.count == source.count;
            if (!sameDates) _manualScheduleDates.clear();
            final previousSchedule = _schedule;
            final keepAmounts =
                sameDates &&
                previousSource?.cents == source.cents &&
                previousSchedule?.length == schedule.length;
            final reviewed = [
              for (final (index, item) in schedule.indexed)
                (
                  number: item.number,
                  amount: keepAmounts
                      ? previousSchedule![index].amount
                      : item.amount,
                  dueDate: _manualScheduleDates[item.number] ?? item.dueDate,
                ),
            ];
            for (final c in _scheduleAmountControllers) {
              c.dispose();
            }
            _scheduleAmountControllers = [
              for (final item in reviewed)
                TextEditingController(text: item.amount.plain),
            ];
            _scheduleSource = source;
            _schedule = reviewed;
            _error = null;
          });
        }
      } else {
        final amountToUse =
            Money.fromInput(_amount.text) ??
            Money.fromInput(_estimatedAmount.text) ??
            const Money(0);
        final preview = await repository.recurrencePreview(
          widget.space.id,
          amount: amountToUse,
          startDate: toApiDate(_date),
          endDate: _endDate == null ? null : toApiDate(_endDate!),
        );
        if (mounted) {
          setState(() {
            _recurrence = preview;
            _recurrenceFor = draft;
            _confirmPast = false;
            _error = null;
          });
        }
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _save() async {
    final user = context.read<SessionController>().user;
    if (_saving || user == null) return;
    if (!_form.currentState!.validate()) {
      _scrollToFirstInvalid();
      return;
    }
    final body = {
      ..._draft()!,
      // O conjunto criado é exatamente o período revisado.
      if (_kind == _Kind.recurring) ...{
        'approved_until': _recurrence!.approvedUntil,
        'confirm_past': _confirmPast,
      },
    };
    setState(() {
      _saving = true;
      _error = null;
      _localError = null;
    });
    final CreationOutcome outcome;
    try {
      outcome = await context.read<PayableCreations>().submit(
        user.id,
        widget.space.id,
        body,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _localError =
              'Não foi possível guardar o cadastro neste aparelho. Nada foi '
              'enviado; tente de novo.';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    _apply(outcome, fromThisDraft: true);
  }

  void _apply(CreationOutcome outcome, {required bool fromThisDraft}) {
    final session = context.read<SessionController>();
    switch (outcome.state) {
      case ReceiptAttemptState.confirmed:
        session.dataChanged();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(outcome.message)));
        if (fromThisDraft) {
          Navigator.of(context).pop();
        } else {
          setState(() => _pending = null);
        }
      case ReceiptAttemptState.rejected:
        setState(() {
          _pending = null;
          _error = outcome.error;
          if (!fromThisDraft) {
            _localError =
                'O cadastro pendente foi recusado pela API e nada foi '
                'gravado: ${outcome.error?.message ?? ''}';
          }
        });
      case _:
        session.dataChanged();
        setState(() {
          _pending = outcome.pending;
          _pendingNotice = outcome.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    final isDesktop = MediaQuery.sizeOf(context).width >= 640;

    if (widget.asModal) {
      return Padding(
        padding: const EdgeInsets.all(AppTokens.p24),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      pending == null
                          ? 'Nova conta a pagar'
                          : 'Cadastro não confirmado',
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
              const SizedBox(height: 12),
              Flexible(
                child: _loadingPending
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : pending != null
                    ? _buildPending(context, pending, isModal: true)
                    : _buildForm(context, isModal: true),
              ),
            ],
          ),
        ),
      );
    }

    final bodyContent = _loadingPending
        ? const Center(child: CircularProgressIndicator())
        : pending != null
        ? _buildPending(context, pending, isModal: false)
        : _buildForm(context, isModal: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          pending == null ? 'Nova conta a pagar' : 'Cadastro não confirmado',
        ),
      ),
      body: isDesktop
          ? Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.p24,
                  vertical: AppTokens.p32,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
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
                      child: bodyContent,
                    ),
                  ),
                ),
              ),
            )
          : bodyContent,
    );
  }

  Widget _buildPending(
    BuildContext context,
    PendingCreation pending, {
    required bool isModal,
  }) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 640;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      shrinkWrap: isModal || isDesktop,
      physics: isDesktop && !isModal
          ? const NeverScrollableScrollPhysics()
          : null,
      padding: isModal
          ? EdgeInsets.only(
              bottom: (MediaQuery.viewInsetsOf(context).bottom > 0 ? 32 : 0),
            )
          : EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom:
                  16 + (MediaQuery.viewInsetsOf(context).bottom > 0 ? 32 : 0),
            ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SpaceBadge(widget.space, prefix: 'Conta a pagar do espaço'),
        ),
        const SizedBox(height: 16),
        PendingCreationCard(
          key: ValueKey(pending.idempotencyKey),
          pending: pending,
          notice: _pendingNotice,
          onSettled: (outcome) => _apply(outcome, fromThisDraft: false),
        ),
        const SizedBox(height: 8),
        Text(
          'Há um cadastro sem confirmação neste espaço. Para não '
          'duplicar, verifique-o antes de cadastrar outro.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
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
        final currentMoney = Money.fromInput(_amount.text);
        final count = int.tryParse(_count.text);
        if (currentMoney != null && count != null && count > 0) {
          if (newMode == _InstallmentAmountMode.byTotal) {
            final totalCents = currentMoney.cents * count;
            if (totalCents <= Money.maxCents) {
              _amount.text = Money(totalCents).plain;
            }
          } else {
            final perInstallment = currentMoney.cents ~/ count;
            _amount.text = Money(perInstallment).plain;
          }
        }
        setState(() {
          _installmentAmountMode = newMode;
          _schedule = null;
        });
      },
    );
  }

  Widget _buildForm(BuildContext context, {required bool isModal}) {
    final theme = Theme.of(context);
    final fieldErrors = _error?.fieldErrors ?? const {};
    final isDesktop = MediaQuery.sizeOf(context).width >= 640;
    final banner =
        _localError ??
        (_error == null
            ? null
            : fieldErrors.isEmpty
            ? _error!.message
            : 'A API recusou o cadastro e nada foi gravado. '
                  '${fieldErrors.values.first}');
    final schedule = _schedule;
    final recurrence = _recurrence;
    final canSave = switch (_kind) {
      _Kind.single => true,
      _Kind.installment => _scheduleCurrent,
      _Kind.recurring =>
        _recurrenceCurrent && (recurrence!.pastCount == 0 || _confirmPast),
    };

    final amountField = TextFormField(
      key: _amountKey,
      focusNode: _amountFocus,
      controller: _amount,
      decoration: InputDecoration(
        labelText: switch (_kind) {
          _Kind.single => 'Valor *',
          _Kind.installment =>
            _installmentAmountMode == _InstallmentAmountMode.byInstallment
                ? 'Valor da parcela *'
                : 'Valor total *',
          _Kind.recurring =>
            _isVariable
                ? 'Valor da primeira ocorrência (opcional)'
                : 'Valor mensal *',
        },
        prefixText: r'R$ ',
        errorText: fieldErrors['amount'] ?? fieldErrors['total'],
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [MoneyInputFormatter()],
      validator: (value) {
        if (_kind == _Kind.recurring && _isVariable) {
          return null;
        }
        final amount = Money.fromInput(value ?? '');
        if (amount == null || amount.isZero) return 'Informe o valor.';
        if (_kind == _Kind.installment &&
            _installmentAmountMode == _InstallmentAmountMode.byInstallment) {
          final count = int.tryParse(_count.text) ?? 1;
          if (amount.cents * count > Money.maxCents) {
            return 'Valor total excede o limite suportado.';
          }
        }
        return null;
      },
    );

    final countField = TextFormField(
      key: _countKey,
      focusNode: _countFocus,
      controller: _count,
      decoration: InputDecoration(
        labelText: 'Número de parcelas *',
        errorText: fieldErrors['installment_count'],
      ),
      keyboardType: TextInputType.number,
      validator: (value) {
        final count = int.tryParse(value ?? '');
        return count == null || count < 1 || count > 1200
            ? 'De 1 a 1200 parcelas.'
            : null;
      },
    );

    final dateField = DateField(
      label: switch (_kind) {
        _Kind.single => 'Vencimento *',
        _Kind.installment => 'Primeiro vencimento *',
        _Kind.recurring => 'Primeiro vencimento *',
      },
      helperText: _kind == _Kind.recurring
          ? 'O dia escolhido será usado como referência nos meses seguintes.'
          : null,
      value: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      errorText:
          fieldErrors['due_date'] ??
          fieldErrors['first_due_date'] ??
          fieldErrors['start_date'],
      onChanged: (date) => setState(() => _date = date),
    );

    return Form(
      key: _form,
      onChanged: () => setState(() {}),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        shrinkWrap: isModal || isDesktop,
        physics: isDesktop && !isModal
            ? const NeverScrollableScrollPhysics()
            : null,
        padding: isModal
            ? EdgeInsets.only(
                bottom: (MediaQuery.viewInsetsOf(context).bottom > 0 ? 32 : 0),
              )
            : EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom:
                    16 + (MediaQuery.viewInsetsOf(context).bottom > 0 ? 32 : 0),
              ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SpaceBadge(widget.space, prefix: 'Conta a pagar do espaço'),
          ),
          const SizedBox(height: 16),
          if (banner != null) ...[
            FormErrorBanner(banner),
            const SizedBox(height: 16),
          ],
          _KindSelector(
            selected: _kind,
            onChanged: (kind) => setState(() => _kind = kind),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: _descriptionKey,
            focusNode: _descriptionFocus,
            controller: _description,
            inputFormatters: const [UpperCaseTextFormatter()],
            decoration: InputDecoration(
              labelText: 'Descrição *',
              hintText: 'Ex.: Aluguel, material da obra',
              errorText: fieldErrors['description'],
            ),
            maxLength: 120,
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Informe a descrição.' : null,
          ),
          const SizedBox(height: 12),
          AccessibleFieldWrapper(
            label: 'Beneficiário (opcional)',
            isOptional: true,
            child: Builder(
              builder: (context) {
                final textScaler = MediaQuery.textScalerOf(context);
                final isTextEnlarged = textScaler.scale(1.0) > 1.2;
                return TextFormField(
                  controller: _payee,
                  inputFormatters: const [UpperCaseTextFormatter()],
                  decoration: InputDecoration(
                    labelText: isTextEnlarged
                        ? null
                        : 'Beneficiário (opcional)',
                  ),
                  maxLength: 120,
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          CategoryPickerField(
            spaceId: widget.space.id,
            type: 'expense',
            selectedCategoryId: _selectedCategoryId,
            onChanged: (catId) => setState(() => _selectedCategoryId = catId),
          ),
          const SizedBox(height: 12),
          if (isDesktop && _kind == _Kind.single)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: amountField),
                const SizedBox(width: AppTokens.p16),
                Expanded(flex: 3, child: dateField),
              ],
            )
          else if (isDesktop && _kind == _Kind.installment) ...[
            _buildInstallmentModeSelector(),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: amountField),
                const SizedBox(width: AppTokens.p16),
                Expanded(flex: 2, child: countField),
              ],
            ),
            const SizedBox(height: 16),
            dateField,
          ] else if (isDesktop && _kind == _Kind.recurring) ...[
            SegmentedButton<bool>(
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
              onSelectionChanged: (set) => setState(() {
                _isVariable = set.first;
                _schedule = null;
                _recurrence = null;
              }),
            ),
            if (_isVariable) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _estimatedAmount,
                decoration: InputDecoration(
                  labelText:
                      'Estimativa de valor (opcional, para planejamento)',
                  prefixText: r'R$ ',
                  helperText: 'Aguardando valor: o valor exato será informado a cada mês.',
                  errorText: fieldErrors['estimated_amount'],
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [MoneyInputFormatter()],
              ),
            ],
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
            if (_kind == _Kind.installment) ...[
              _buildInstallmentModeSelector(),
              const SizedBox(height: 16),
            ],
            if (_kind == _Kind.recurring) ...[
              SegmentedButton<bool>(
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
                onSelectionChanged: (set) => setState(() {
                  _isVariable = set.first;
                  _schedule = null;
                  _recurrence = null;
                }),
              ),
              if (_isVariable) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _estimatedAmount,
                  decoration: InputDecoration(
                    labelText:
                        'Estimativa de valor (opcional, para planejamento)',
                    prefixText: r'R$ ',
                    helperText: 'Aguardando valor: o valor exato será informado a cada mês.',
                    errorText: fieldErrors['estimated_amount'],
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [MoneyInputFormatter()],
                ),
              ],
              const SizedBox(height: 16),
            ],
            amountField,
            if (_kind == _Kind.installment) ...[
              const SizedBox(height: 16),
              countField,
            ],
            const SizedBox(height: 16),
            dateField,
          ],
          if (_kind == _Kind.installment &&
              _computedInstallmentTotal != null &&
              _computedPerInstallmentAmount != null &&
              (int.tryParse(_count.text) ?? 0) > 0) ...[
            const SizedBox(height: 14),
            InstallmentSummaryCard(
              installmentCount: int.parse(_count.text),
              installmentAmount: _computedPerInstallmentAmount!,
              totalAmount: _computedInstallmentTotal!,
              isByInstallmentMode:
                  _installmentAmountMode ==
                  _InstallmentAmountMode.byInstallment,
            ),
          ],
          if (_kind == _Kind.recurring) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Com data de término'),
              value: _endDate != null,
              onChanged: (on) => setState(() => _endDate = on ? _date : null),
            ),
            if (_endDate != null)
              DateField(
                label: 'Última ocorrência até',
                value: _endDate!,
                firstDate: _date,
                lastDate: DateTime(2100),
                errorText: fieldErrors['end_date'],
                onChanged: (date) => setState(() => _endDate = date),
              ),
          ],
          if (_kind == _Kind.installment)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sugerir próximo dia útil bancário'),
              subtitle: const Text(
                'Para boletos comuns. Em tributos, use as datas da guia.',
              ),
              value: _suggestNextBankDay,
              onChanged: (value) => setState(() => _suggestNextBankDay = value),
            ),
          if (_kind != _Kind.single) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _preview,
              child: Text(
                _kind == _Kind.installment
                    ? 'Ver cronograma'
                    : 'Revisar ocorrências',
              ),
            ),
          ],
          if (_kind == _Kind.installment && _scheduleCurrent) ...[
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Text(
                          'Parcelas calculadas',
                          style: theme.textTheme.titleSmall,
                        ),
                        if (_scheduleTotal != null)
                          Container(
                            key: const ValueKey('schedule-total-badge'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Total: ${_scheduleTotal!.brl}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Você pode ajustar a data e o valor de cada parcela antes de confirmar.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const Divider(height: 16),
                    for (var i = 0; i < schedule!.length; i++)
                      _buildScheduleItemRow(i, theme),
                  ],
                ),
              ),
            ),
          ],
          if (_kind == _Kind.recurring && _recurrenceCurrent)
            _RecurrenceReview(
              preview: recurrence!,
              amount:
                  Money.fromInput(_amount.text) ??
                  Money.fromInput(_estimatedAmount.text) ??
                  const Money(0),
              confirmPast: _confirmPast,
              onConfirmPast: (value) => setState(() => _confirmPast = value),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving || !canSave ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Text(switch (_kind) {
                    _Kind.single => 'Salvar conta a pagar',
                    _Kind.installment => 'Confirmar cadastro das parcelas',
                    _Kind.recurring => 'Confirmar recorrência',
                  }),
          ),
          const SizedBox(height: 8),
          Text(
            'Cadastrar não altera o saldo. A conta de origem é escolhida ao '
            'registrar o pagamento.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleItemRow(int index, ThemeData theme) {
    final item = _schedule![index];
    while (_scheduleAmountControllers.length <= index) {
      _scheduleAmountControllers.add(
        TextEditingController(
          text: _schedule![_scheduleAmountControllers.length].amount.plain,
        ),
      );
    }
    final controller = _scheduleAmountControllers[index];
    final isDesktop = MediaQuery.sizeOf(context).width >= 640;

    return Padding(
      key: ValueKey('schedule-${item.number}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.35,
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Parcela ${item.number}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                MoneyText(
                  item.amount,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (isDesktop)
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: OutlinedButton.icon(
                      key: ValueKey('schedule-date-${item.number}'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        alignment: Alignment.centerLeft,
                      ),
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text(
                        'Vencimento: ${formatDateBr(item.dueDate)}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      onPressed: () async {
                        final current = parseApiDate(item.dueDate);
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: current,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          _onScheduleDateChanged(index, picked);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      key: ValueKey('schedule-amount-${item.number}'),
                      controller: controller,
                      inputFormatters: [MoneyInputFormatter()],
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Valor',
                        prefixText: 'R\$ ',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (text) =>
                          _onScheduleAmountChanged(index, text),
                    ),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    key: ValueKey('schedule-date-${item.number}'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      alignment: Alignment.centerLeft,
                    ),
                    icon: const Icon(Icons.calendar_today_outlined, size: 16),
                    label: Text(
                      'Vencimento: ${formatDateBr(item.dueDate)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    onPressed: () async {
                      final current = parseApiDate(item.dueDate);
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: current,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        _onScheduleDateChanged(index, picked);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: ValueKey('schedule-amount-${item.number}'),
                    controller: controller,
                    inputFormatters: [MoneyInputFormatter()],
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Valor da parcela',
                      prefixText: 'R\$ ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (text) => _onScheduleAmountChanged(index, text),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Revisão do conjunto inicial de uma recorrência, calculada pela API.
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
            line('Valor', 'Valor mensal', amount.brl),
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
                'sem pagamento e sem mudar saldo.',
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
            if (preview.items.length < preview.count)
              Text(
                'Mostrando ${preview.items.length} de ${preview.count}; os totais '
                'acima cobrem todas.',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Text(
              'Depois deste conjunto, novas ocorrências são geradas '
              'automaticamente, mantendo sempre 12 meses à frente.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Seletor adaptativo de tipo de conta a pagar.
///
/// Em escalas padrão e larguras convencionais, exibe um [SegmentedButton] horizontal.
/// Quando a escala de texto é ampliada (ex.: 150%, 200%) ou o espaço horizontal não comporta
/// as opções sem corte, adota composição vertical acessível com alvos de toque de pelo
/// menos 48 pixels lógicos e textos completos.
class _KindSelector extends StatelessWidget {
  const _KindSelector({required this.selected, required this.onChanged});

  final _Kind selected;
  final ValueChanged<_Kind> onChanged;

  static const _options = [
    (_Kind.single, 'Avulsa'),
    (_Kind.installment, 'Parcelada'),
    (_Kind.recurring, 'Recorrente'),
  ];

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final isTextEnlarged = textScaler.scale(1.0) > 1.2;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useVertical = isTextEnlarged || constraints.maxWidth < 330;

        if (!useVertical) {
          return SegmentedButton<_Kind>(
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
            onSelectionChanged: (value) => onChanged(value.first),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _options.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _KindVerticalOption(
                label: _options[i].$2,
                isSelected: selected == _options[i].$1,
                onTap: () => onChanged(_options[i].$1),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _KindVerticalOption extends StatelessWidget {
  const _KindVerticalOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 20,
                    color: colorScheme.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
