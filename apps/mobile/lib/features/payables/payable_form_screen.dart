import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../ui/date_field.dart';
import '../../ui/widgets.dart';
import '../agreements/receipt_attempt.dart' show ReceiptAttemptState;
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import 'payable.dart';
import 'payable_creations.dart';
import 'payables_repository.dart';
import 'pending_creation_card.dart';

enum _Kind { single, installment, recurring }

/// Cadastro de conta a pagar: avulsa, parcelada (prévia do cronograma) ou
/// recorrente (revisão do período, com confirmação das já vencidas). Não
/// altera saldo. O formulário é rascunho; ao salvar, chave e conteúdo são
/// guardados antes do envio ([PayableCreations]) e, sem confirmação, a
/// tentativa fica pendente: esta tela abre na retomada até verificar.
class PayableFormScreen extends StatefulWidget {
  const PayableFormScreen({super.key, required this.space, this.today});

  final Space space;
  final DateTime? today;

  @override
  State<PayableFormScreen> createState() => _PayableFormScreenState();
}

class _PayableFormScreenState extends State<PayableFormScreen> {
  final _form = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _payee = TextEditingController();
  final _amount = TextEditingController();
  final _count = TextEditingController(text: '2');
  late DateTime _date = DateUtils.dateOnly(widget.today ?? DateTime.now());
  DateTime? _endDate;
  _Kind _kind = _Kind.single;
  List<ScheduleItem>? _schedule;
  String? _scheduleFor;
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
    for (final controller in [_description, _payee, _amount, _count]) {
      controller.dispose();
    }
    super.dispose();
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
    if (amount == null) return null;
    final common = {
      'description': _description.text.trim(),
      'payee': _payee.text.trim().isEmpty ? null : _payee.text.trim(),
    };
    return switch (_kind) {
      _Kind.single => {
        'kind': 'single',
        ...common,
        'amount': amount.toApi(),
        'due_date': toApiDate(_date),
      },
      _Kind.installment => {
        'kind': 'installment',
        ...common,
        'total': amount.toApi(),
        'installment_count': int.tryParse(_count.text),
        'first_due_date': toApiDate(_date),
      },
      _Kind.recurring => {
        'kind': 'recurring',
        ...common,
        'amount': amount.toApi(),
        'start_date': toApiDate(_date),
        'end_date': _endDate == null ? null : toApiDate(_endDate!),
      },
    };
  }

  bool get _scheduleCurrent =>
      _schedule != null && _scheduleFor == _draft()?.toString();
  bool get _recurrenceCurrent =>
      _recurrence != null && _recurrenceFor == _draft()?.toString();

  Future<void> _preview() async {
    if (!_form.currentState!.validate()) return;
    final draft = _draft().toString();
    final repository = context.read<PayablesRepository>();
    try {
      if (_kind == _Kind.installment) {
        final schedule = await repository.preview(
          widget.space.id,
          total: Money.fromInput(_amount.text)!,
          count: int.parse(_count.text),
          firstDueDate: toApiDate(_date),
        );
        if (mounted) {
          setState(() {
            _schedule = schedule;
            _scheduleFor = draft;
            _error = null;
          });
        }
      } else {
        final preview = await repository.recurrencePreview(
          widget.space.id,
          amount: Money.fromInput(_amount.text)!,
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
    if (_saving || user == null || !_form.currentState!.validate()) return;
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          pending == null ? 'Nova conta a pagar' : 'Cadastro não confirmado',
        ),
      ),
      body: _loadingPending
          ? const Center(child: CircularProgressIndicator())
          : pending != null
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SpaceBadge(widget.space, prefix: 'Conta a pagar do espaço'),
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
            )
          : _buildForm(context),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final fieldErrors = _error?.fieldErrors ?? const {};
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

    return Form(
      key: _form,
      onChanged: () => setState(() {}),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SpaceBadge(widget.space, prefix: 'Conta a pagar do espaço'),
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
            controller: _description,
            decoration: InputDecoration(
              labelText: 'Descrição',
              hintText: 'Ex.: Aluguel, material da obra',
              errorText: fieldErrors['description'],
            ),
            maxLength: 120,
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Informe a descrição.' : null,
          ),
          AccessibleFieldWrapper(
            label: 'Beneficiário (opcional)',
            isOptional: true,
            child: Builder(
              builder: (context) {
                final textScaler = MediaQuery.textScalerOf(context);
                final isTextEnlarged = textScaler.scale(1.0) > 1.2;
                return TextFormField(
                  controller: _payee,
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
          TextFormField(
            controller: _amount,
            decoration: InputDecoration(
              labelText: switch (_kind) {
                _Kind.single => 'Valor',
                _Kind.installment => 'Valor total',
                _Kind.recurring => 'Valor mensal',
              },
              prefixText: r'R$ ',
              errorText: fieldErrors['amount'] ?? fieldErrors['total'],
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [MoneyInputFormatter()],
            validator: (value) {
              final amount = Money.fromInput(value ?? '');
              return amount == null || amount.isZero
                  ? 'Informe o valor.'
                  : null;
            },
          ),
          if (_kind == _Kind.installment) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _count,
              decoration: InputDecoration(
                labelText: 'Número de parcelas',
                errorText: fieldErrors['installment_count'],
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                final count = int.tryParse(value ?? '');
                return count == null || count < 1 || count > 1200
                    ? 'De 1 a 1200 parcelas.'
                    : null;
              },
            ),
          ],
          const SizedBox(height: 16),
          DateField(
            label: switch (_kind) {
              _Kind.single => 'Vencimento',
              _Kind.installment => 'Primeiro vencimento',
              _Kind.recurring => 'Primeiro vencimento',
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
          ),
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
              child: Column(
                children: [
                  for (final item in schedule!)
                    ListTile(
                      key: ValueKey('schedule-${item.number}'),
                      dense: true,
                      title: Text(
                        'Parcela ${item.number} · ${formatDateBr(item.dueDate)}',
                      ),
                      trailing: MoneyText(item.amount),
                    ),
                ],
              ),
            ),
          ],
          if (_kind == _Kind.recurring && _recurrenceCurrent)
            _RecurrenceReview(
              preview: recurrence!,
              amount: Money.fromInput(_amount.text)!,
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
