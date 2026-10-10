import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../ui/date_field.dart';
import '../../ui/widgets.dart';
import '../accounts/account.dart';
import '../agreements/receipt_attempts.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import 'payable.dart';

/// Estorno (devolve o valor à conta original e reabre o restante) ou
/// correção (estorno + substituto, atômica) de um pagamento, com motivo e
/// revisão dos efeitos por conta. O original fica no histórico.
class PaymentFixScreen extends StatefulWidget {
  const PaymentFixScreen({
    super.key,
    required this.space,
    required this.payable,
    required this.original,
    required this.accounts,
    required this.correction,
    this.today,
  });

  final Space space;
  final Payable payable;
  final Payment original;
  final List<Account> accounts;
  final bool correction;
  final DateTime? today;

  @override
  State<PaymentFixScreen> createState() => _PaymentFixScreenState();
}

class _PaymentFixScreenState extends State<PaymentFixScreen> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late final _amount = TextEditingController(
    text: widget.original.amount.plain,
  );
  late final DateTime _today = DateUtils.dateOnly(
    widget.today ?? DateTime.now(),
  );
  late DateTime _date = parseApiDate(widget.original.paidOn);
  late int? _accountId =
      _selectable.any((a) => a.id == widget.original.accountId)
      ? widget.original.accountId
      : null;
  bool _reviewing = false;
  ReceiptAttemptState _state = ReceiptAttemptState.ready;
  ReceiptAttempt? _attempt;
  String? _notice;
  ApiException? _error;

  List<Account> get _selectable =>
      widget.accounts.where((account) => !account.isArchived).toList();
  Money get _available => Money(
    (widget.payable.remaining?.cents ?? 0) + widget.original.amount.cents,
  );
  bool get _busy => _state == ReceiptAttemptState.sending;
  String get _verb => widget.correction ? 'correção' : 'estorno';
  String _name(int id) =>
      widget.accounts.where((a) => a.id == id).firstOrNull?.name ?? 'Conta';

  ({int accountId, String accountName, Money amount, String receivedOn})?
  get _replacement {
    final attempt = _attempt;
    if (attempt != null) {
      return attempt.operation == ReceiptOperation.paymentCorrection
          ? (
              accountId: attempt.accountId,
              accountName: attempt.accountName,
              amount: attempt.amount,
              receivedOn: attempt.receivedOn,
            )
          : null;
    }
    if (!widget.correction) return null;
    return (
      accountId: _accountId!,
      accountName: _name(_accountId!),
      amount: Money.fromInput(_amount.text) ?? const Money(0),
      receivedOn: toApiDate(_date),
    );
  }

  @override
  void dispose() {
    _reason.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final user = context.read<SessionController>().user;
    if (_state != ReceiptAttemptState.ready || user == null) return;
    setState(() => _state = ReceiptAttemptState.sending);
    final ReceiptAttemptOutcome outcome;
    try {
      outcome = await context.read<ReceiptAttempts>().submitPaymentFix(
        userId: user.id,
        spaceId: widget.space.id,
        payableId: widget.payable.id,
        original: widget.original,
        originalAccountName: _name(widget.original.accountId),
        reason: _reason.text.trim(),
        replacement: _replacement,
      );
    } catch (_) {
      if (mounted) setState(() => _state = ReceiptAttemptState.ready);
      return;
    }
    _apply(outcome);
  }

  Future<void> _verify() async {
    final attempt = _attempt;
    if (_busy || attempt == null) return;
    setState(() => _state = ReceiptAttemptState.sending);
    _apply(await context.read<ReceiptAttempts>().resolve(attempt));
  }

  void _apply(ReceiptAttemptOutcome outcome) {
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
                ? (widget.correction
                      ? 'Corrigir pagamento'
                      : 'Estornar pagamento')
                : uncertain
                ? 'Operação não confirmada'
                : 'Confirme ${widget.correction ? 'a correção' : 'o estorno'}',
          ),
        ),
        body: _reviewing
            ? _buildReview(context, uncertain)
            : _buildForm(context),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final original = widget.original;
    final fieldErrors = _error?.fieldErrors ?? const {};
    final account = widget.accounts
        .where((a) => a.id == _accountId)
        .firstOrNull;
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SpaceBadge(widget.space, prefix: 'Espaço'),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('Pagamento original'),
              subtitle: Text(
                '${original.amount.brl} · ${_name(original.accountId)} · ${formatDateBr(original.paidOn)}',
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_error != null) ...[
            FormErrorBanner(
              'A API recusou a operação e nada foi gravado. '
              '${fieldErrors.values.firstOrNull ?? _error!.message}',
            ),
            const SizedBox(height: 16),
          ],
          if (widget.correction) ...[
            DropdownButtonFormField<int>(
              initialValue: _accountId,
              hint: const Text('Escolha a conta'),
              decoration: const InputDecoration(labelText: 'Conta de origem'),
              items: [
                for (final item in _selectable)
                  DropdownMenuItem(value: item.id, child: Text(item.name)),
              ],
              validator: (value) =>
                  value == null ? 'Escolha a conta de origem.' : null,
              onChanged: (value) => setState(() => _accountId = value),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amount,
              decoration: InputDecoration(
                labelText: 'Valor correto',
                prefixText: r'R$ ',
                helperText: 'Até ${_available.brl} nesta obrigação.',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [MoneyInputFormatter()],
              validator: (value) {
                final amount = Money.fromInput(value ?? '');
                if (amount == null || amount.isZero) {
                  return 'Informe o valor correto.';
                }
                if (amount.cents > _available.cents) {
                  return 'Máximo após o estorno: ${_available.brl}.';
                }
                if (_accountId == original.accountId &&
                    amount.cents == original.amount.cents &&
                    toApiDate(_date) == original.paidOn) {
                  return 'Altere a conta, o valor ou a data. Para só desfazer, use Estornar.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DateField(
              label: 'Data correta do pagamento',
              value: _date,
              firstDate: account != null
                  ? parseApiDate(account.openingBalanceDate)
                  : DateTime(2000),
              lastDate: _today,
              onChanged: (date) => setState(() => _date = date),
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'Motivo'),
            maxLength: 500,
            validator: (value) => (value ?? '').trim().length < 3
                ? 'Informe o motivo (pelo menos 3 caracteres).'
                : null,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              if (_form.currentState!.validate()) {
                setState(() {
                  _error = null;
                  _reviewing = true;
                });
              }
            },
            child: Text('Revisar $_verb'),
          ),
        ],
      ),
    );
  }

  Widget _buildReview(BuildContext context, bool uncertain) {
    final theme = Theme.of(context);
    final original = widget.original;
    final replacement = _replacement;
    // Estorno devolve o valor à conta original; o substituto sai da escolhida.
    final deltas = <int, int>{original.accountId: original.amount.cents};
    if (replacement != null) {
      deltas[replacement.accountId] =
          (deltas[replacement.accountId] ?? 0) - replacement.amount.cents;
    }
    final remaining = widget.payable.remaining ?? const Money(0);
    final remainingAfter = Money(
      _available.cents - (replacement?.amount.cents ?? 0),
    );
    Widget line(String id, String label, String text) => Padding(
      key: ValueKey('payfix-$id'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Flexible(child: Text(text, textAlign: TextAlign.end)),
        ],
      ),
    );
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SpaceBadge(widget.space, prefix: 'Espaço'),
              const SizedBox(height: 16),
              if (uncertain) ...[
                FormErrorBanner(
                  _notice ?? 'Ainda não conseguimos confirmar esta operação.',
                ),
                const SizedBox(height: 16),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      line(
                        'Antes',
                        'Antes',
                        '${original.amount.brl} · ${_name(original.accountId)} · ${formatDateBr(original.paidOn)}',
                      ),
                      line(
                        'Depois',
                        'Depois',
                        replacement == null
                            ? 'Estornado, sem substituto'
                            : '${replacement.amount.brl} · ${replacement.accountName} · ${formatDateBr(replacement.receivedOn)}',
                      ),
                      const Divider(height: 24),
                      for (final MapEntry(key: id, value: delta)
                          in deltas.entries)
                        line('Saldo-$id', _name(id), () {
                          final account = widget.accounts
                              .where((a) => a.id == id)
                              .firstOrNull;
                          final change =
                              '${delta < 0 ? '−' : '+'}${Money(delta.abs()).brl}';
                          return account == null
                              ? change
                              : '$change · ${account.balance.brl} → ${Money(account.balance.cents + delta).brl}';
                        }()),
                      line(
                        'Restante',
                        'Restante da obrigação',
                        '${remaining.brl} → ${remainingAfter.brl}',
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
                'O pagamento original continua no histórico, marcado como ${widget.correction ? 'corrigido' : 'estornado'}.',
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
                          uncertain ? 'Verificar $_verb' : 'Confirmar $_verb',
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
