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
import 'account.dart';
import 'opening_adjustments.dart';

/// Correção do saldo inicial e/ou da data de abertura, com revisão. O saldo
/// atual não é editável: muda exatamente pela diferença da abertura.
/// Recebe [pending] para retomar uma correção sem confirmação.
class OpeningAdjustmentScreen extends StatefulWidget {
  const OpeningAdjustmentScreen({
    super.key,
    required this.space,
    required this.account,
    this.pending,
  });

  final Space space;
  final Account account;
  final OpeningAttempt? pending;

  @override
  State<OpeningAdjustmentScreen> createState() =>
      _OpeningAdjustmentScreenState();
}

class _OpeningAdjustmentScreenState extends State<OpeningAdjustmentScreen> {
  final _form = GlobalKey<FormState>();
  late final _balance = TextEditingController(
    text: widget.account.openingBalance.plain,
  );
  final _reason = TextEditingController();
  late DateTime _date = parseApiDate(widget.account.openingBalanceDate);
  late bool _reviewing = widget.pending != null;
  late OpeningAttempt? _attempt = widget.pending;
  late ReceiptAttemptState _state = widget.pending == null
      ? ReceiptAttemptState.ready
      : ReceiptAttemptState.uncertain;
  String? _notice;
  ApiException? _error;
  String? _localError;

  bool get _busy => _state == ReceiptAttemptState.sending;
  DateTime? get _lastDate => widget.account.firstMovementDate == null
      ? null
      : parseApiDate(widget.account.firstMovementDate!);

  Money get _newBalance =>
      _attempt?.openingBalance ??
      Money.fromInput(_balance.text) ??
      const Money(0);
  String get _newDate => _attempt?.openingDate ?? toApiDate(_date);

  @override
  void dispose() {
    _balance.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _review() {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _error = null;
      _localError = null;
      _reviewing = true;
    });
  }

  Future<void> _confirm() async {
    final user = context.read<SessionController>().user;
    if (_state != ReceiptAttemptState.ready || user == null) return;
    setState(() => _state = ReceiptAttemptState.sending);
    final OpeningOutcome outcome;
    try {
      outcome = await context.read<OpeningAdjustments>().submit(
        userId: user.id,
        spaceId: widget.space.id,
        account: widget.account,
        openingBalance: _newBalance,
        openingDate: _newDate,
        reason: _reason.text.trim(),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _state = ReceiptAttemptState.ready;
          _reviewing = false;
          _localError =
              'Não foi possível guardar a correção neste aparelho. Nada foi '
              'enviado; tente de novo.';
        });
      }
      return;
    }
    _apply(outcome);
  }

  Future<void> _verify() async {
    final attempt = _attempt;
    if (_busy || attempt == null) return;
    setState(() => _state = ReceiptAttemptState.sending);
    _apply(await context.read<OpeningAdjustments>().resolve(attempt));
  }

  void _apply(OpeningOutcome outcome) {
    if (!mounted) return;
    final session = context.read<SessionController>();
    switch (outcome.state) {
      case ReceiptAttemptState.confirmed:
        session.dataChanged();
        Navigator.of(context).pop(outcome);
      case ReceiptAttemptState.rejected:
        setState(() {
          _state = ReceiptAttemptState.ready;
          _attempt = null;
          _reviewing = false;
          _error = outcome.error;
        });
      case _:
        session.dataChanged();
        setState(() {
          _state = ReceiptAttemptState.uncertain;
          _attempt = outcome.attempt;
          _notice = outcome.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final uncertain = _attempt != null;
    return PopScope(
      canPop: !_busy && (!_reviewing || uncertain),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _state == ReceiptAttemptState.ready) {
          setState(() => _reviewing = false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            !_reviewing
                ? 'Corrigir abertura'
                : uncertain
                ? 'Correção não confirmada'
                : 'Confirme a correção',
          ),
        ),
        body: _reviewing ? _buildReview(context, uncertain) : _buildForm(),
      ),
    );
  }

  Widget _buildForm() {
    final account = widget.account;
    final fieldErrors = _error?.fieldErrors ?? const {};
    final banner = _error == null
        ? _localError
        : 'A API recusou a correção e nada foi gravado. '
              '${fieldErrors.values.firstOrNull ?? _error!.message}';
    final lastDate = _lastDate;
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SpaceBadge(widget.space, prefix: 'Conta do espaço'),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: Text(account.name),
              subtitle: Text(
                'Abertura atual: ${account.openingBalance.brl} em '
                '${formatDateBr(account.openingBalanceDate)}\n'
                'Saldo atual: ${account.balance.brl}',
              ),
              isThreeLine: true,
            ),
          ),
          const SizedBox(height: 16),
          if (banner != null) ...[
            FormErrorBanner(banner),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: _balance,
            decoration: InputDecoration(
              labelText: 'Saldo inicial correto',
              prefixText: r'R$ ',
              errorText: fieldErrors['opening_balance'],
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [MoneyInputFormatter()],
            validator: (value) {
              final amount = Money.fromInput(value ?? '');
              if (amount == null) return 'Informe o saldo inicial.';
              if (amount.cents == account.openingBalance.cents &&
                  toApiDate(_date) == account.openingBalanceDate) {
                return 'Altere o saldo inicial ou a data de abertura.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          DateField(
            label: 'Data de abertura correta',
            value: _date,
            lastDate: lastDate ?? DateTime(2100),
            errorText: fieldErrors['opening_balance_date'],
            onChanged: (date) => setState(() => _date = date),
          ),
          if (lastDate != null) ...[
            const SizedBox(height: 8),
            Text(
              'Até ${formatDateBr(account.firstMovementDate!)}, data da '
              'primeira movimentação: recebimentos e estornos existentes não '
              'podem ficar antes da abertura.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          TextFormField(
            controller: _reason,
            decoration: InputDecoration(
              labelText: 'Motivo',
              helperText: 'Ex.: saldo do extrato digitado errado.',
              errorText: fieldErrors['reason'],
            ),
            maxLength: 500,
            validator: (value) => (value ?? '').trim().length < 3
                ? 'Informe o motivo (pelo menos 3 caracteres).'
                : null,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _review,
            child: const Text('Revisar correção da abertura'),
          ),
        ],
      ),
    );
  }

  Widget _buildReview(BuildContext context, bool uncertain) {
    final theme = Theme.of(context);
    final account = widget.account;
    final previousBalance = _attempt?.previousBalance ?? account.openingBalance;
    final previousDate = _attempt?.previousDate ?? account.openingBalanceDate;
    final delta = _newBalance.cents - previousBalance.cents;
    final resulting = Money(account.balance.cents + delta);
    Widget line(String id, String label, String value) => Padding(
      key: ValueKey('opening-$id'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Flexible(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SpaceBadge(widget.space, prefix: 'Conta do espaço'),
              const SizedBox(height: 16),
              if (uncertain) ...[
                FormErrorBanner(
                  _notice ??
                      'Ainda não conseguimos confirmar esta correção da '
                          'abertura. Verifique antes de fazer outra.',
                ),
                const SizedBox(height: 16),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      line('Conta', 'Conta', account.name),
                      line(
                        'Saldo-inicial',
                        'Saldo inicial',
                        '${previousBalance.brl} → ${_newBalance.brl}',
                      ),
                      line(
                        'Data',
                        'Data de abertura',
                        '${formatDateBr(previousDate)} → ${formatDateBr(_newDate)}',
                      ),
                      const Divider(height: 24),
                      line(
                        'Saldo-atual',
                        'Saldo atual → resultante',
                        '${account.balance.brl} → ${resulting.brl}',
                      ),
                      line(
                        'Diferenca',
                        'Diferença no saldo',
                        '${delta < 0 ? '−' : '+'}${Money(delta.abs()).brl}',
                      ),
                      line(
                        'Motivo',
                        'Motivo',
                        _attempt?.reason ?? _reason.text.trim(),
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                'Não é recebimento nem despesa: as movimentações não mudam e a '
                'correção fica registrada no histórico da conta.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: _busy ? null : (uncertain ? _verify : _confirm),
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Text(
                          uncertain
                              ? 'Verificar correção'
                              : 'Confirmar correção',
                        ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : uncertain
                      ? () => Navigator.of(context).maybePop()
                      : () => setState(() => _reviewing = false),
                  child: Text(
                    uncertain ? 'Verificar depois' : 'Voltar e corrigir',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
