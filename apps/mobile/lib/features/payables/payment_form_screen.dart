import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../ui/app_icons.dart';
import '../../ui/date_field.dart';
import '../../ui/widgets.dart';
import '../accounts/account.dart';
import '../agreements/receipt_attempts.dart';
import '../agreements/receipt_kind_field.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import 'payable.dart';

/// Pagamento total ou parcial: preencher, revisar e confirmar. A conta de
/// origem é escolhida explicitamente (só ativas). Guardado antes do envio;
/// resposta incerta trava a tentativa até a verificação pela mesma chave.
/// Fecha com o [ReceiptAttemptOutcome] confirmado.
class PaymentFormScreen extends StatefulWidget {
  const PaymentFormScreen({
    super.key,
    required this.space,
    required this.payable,
    required this.accounts,
    this.today,
  });

  final Space space;
  final Payable payable;
  final List<Account> accounts;
  final DateTime? today;

  @override
  State<PaymentFormScreen> createState() => _PaymentFormScreenState();
}

class _PaymentFormScreenState extends State<PaymentFormScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  late final DateTime _today = DateUtils.dateOnly(
    widget.today ?? DateTime.now(),
  );
  late DateTime _date = _today;
  int? _accountId;
  ReceiptKind? _kind;
  bool _reviewing = false;
  ReceiptAttemptState _state = ReceiptAttemptState.ready;
  ReceiptAttempt? _attempt;
  String? _notice;
  ApiException? _error;
  String? _localError;

  Money get _remaining => widget.payable.remaining ?? const Money(0);
  bool get _busy => _state == ReceiptAttemptState.sending;
  List<Account> get _selectable =>
      widget.accounts.where((account) => !account.isArchived).toList();
  Account? get _account => widget.accounts
      .where((a) => a.id == (_attempt?.accountId ?? _accountId))
      .firstOrNull;
  Money get _value =>
      _attempt?.amount ??
      (_kind == ReceiptKind.total
          ? _remaining
          : Money.fromInput(_amount.text) ?? const Money(0));

  @override
  void dispose() {
    _amount.dispose();
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
    final account = _account;
    if (_state != ReceiptAttemptState.ready ||
        user == null ||
        account == null) {
      return;
    }
    setState(() => _state = ReceiptAttemptState.sending);
    final ReceiptAttemptOutcome outcome;
    try {
      outcome = await context.read<ReceiptAttempts>().submitPayment(
        userId: user.id,
        spaceId: widget.space.id,
        payableId: widget.payable.id,
        accountId: account.id,
        accountName: account.name,
        amount: _value,
        paidOn: toApiDate(_date),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _state = ReceiptAttemptState.ready;
          _reviewing = false;
          _localError = 'Não foi possível guardar o pagamento neste aparelho. Nada foi enviado.';
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
      case _ when outcome.attempt.operation != ReceiptOperation.payment:
        session.dataChanged();
        setState(() {
          _state = ReceiptAttemptState.ready;
          _reviewing = false;
          _localError =
              'Há um estorno ou correção sem confirmação nesta obrigação. '
              'Volte e verifique antes de pagar.';
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
                ? 'Registrar pagamento'
                : uncertain
                ? 'Pagamento não confirmado'
                : 'Confirme o pagamento',
          ),
        ),
        body: _selectable.isEmpty && !uncertain
            ? const EmptyState(
                icon: AppIcons.accounts,
                title: 'Nenhuma conta ativa neste espaço',
                message:
                    'Cadastre ou reative uma conta para registrar o pagamento.',
              )
            : _reviewing
            ? _buildReview(context, uncertain)
            : _buildForm(context),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final payable = widget.payable;
    final fieldErrors = _error?.fieldErrors ?? const {};
    final banner = _error == null
        ? _localError
        : 'A API recusou o pagamento e nada foi gravado. '
              '${fieldErrors.values.firstOrNull ?? _error!.message}';
    final account = _account;
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SpaceBadge(widget.space, prefix: 'Pagamento no espaço'),
          const SizedBox(height: 12),
          Text(
            '${payable.description} · ${payable.kindLabel}\nFalta pagar ${_remaining.brl}',
          ),
          const SizedBox(height: 20),
          if (banner != null) ...[
            FormErrorBanner(banner),
            const SizedBox(height: 16),
          ],
          DropdownButtonFormField<int>(
            initialValue: _accountId,
            hint: const Text('Escolha a conta'),
            decoration: InputDecoration(
              labelText: 'Conta de origem',
              errorText: fieldErrors['account_id'],
            ),
            items: [
              for (final item in _selectable)
                DropdownMenuItem(value: item.id, child: Text(item.name)),
            ],
            validator: (value) =>
                value == null ? 'Escolha a conta de origem.' : null,
            onChanged: (value) => setState(() => _accountId = value),
          ),
          const SizedBox(height: 16),
          ReceiptKindField(
            initialValue: _kind,
            onChanged: (kind) => setState(() => _kind = kind),
          ),
          const SizedBox(height: 16),
          if (_kind == ReceiptKind.total)
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Valor pago',
                helperText: 'Valor integral que falta pagar.',
                errorText: fieldErrors['amount'],
              ),
              child: MoneyText(_remaining),
            )
          else if (_kind == ReceiptKind.partial)
            TextFormField(
              controller: _amount,
              decoration: InputDecoration(
                labelText: 'Valor pago',
                prefixText: r'R$ ',
                errorText: fieldErrors['amount'],
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [MoneyInputFormatter()],
              validator: (value) {
                final amount = Money.fromInput(value ?? '');
                if (amount == null || amount.isZero) {
                  return 'Informe o valor pago.';
                }
                if (amount.cents == _remaining.cents) {
                  return 'Esse é o valor integral: escolha Total.';
                }
                if (amount.cents > _remaining.cents) {
                  return 'Máximo nesta obrigação: ${_remaining.brl}.';
                }
                return null;
              },
            ),
          const SizedBox(height: 16),
          DateField(
            label: 'Data do pagamento',
            value: _date,
            firstDate: account != null
                ? parseApiDate(account.openingBalanceDate)
                : DateTime(2000),
            lastDate: _today,
            errorText: fieldErrors['paid_on'],
            onChanged: (date) => setState(() => _date = date),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _review,
            child: const Text('Revisar pagamento'),
          ),
        ],
      ),
    );
  }

  Widget _buildReview(BuildContext context, bool uncertain) {
    final theme = Theme.of(context);
    final payable = widget.payable;
    final account = _account;
    final value = _value;
    final balanceAfter = account == null
        ? null
        : Money(account.balance.cents - value.cents);
    final remainingAfter = Money(_remaining.cents - value.cents);
    final date = _attempt?.receivedOn ?? toApiDate(_date);
    Widget line(String id, String label, String text) => Padding(
      key: ValueKey('payment-$id'),
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
              SpaceBadge(widget.space, prefix: 'Pagamento no espaço'),
              const SizedBox(height: 16),
              if (uncertain) ...[
                FormErrorBanner(
                  _notice ?? 'Ainda não conseguimos confirmar este pagamento.',
                ),
                const SizedBox(height: 16),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      line(
                        'Obrigacao',
                        'Obrigação',
                        '${payable.description} · ${payable.kindLabel}',
                      ),
                      line(
                        'Beneficiario',
                        'Beneficiário',
                        payable.payee ?? '—',
                      ),
                      line('Valor', 'Valor pago', value.brl),
                      line(
                        'Conta',
                        'Conta de origem',
                        _attempt?.accountName ?? account?.name ?? '',
                      ),
                      line('Data', 'Data', formatDateBr(date)),
                      if (balanceAfter != null)
                        line(
                          'Saldo',
                          'Saldo da conta',
                          '${account!.balance.brl} → ${balanceAfter.brl}',
                        ),
                      line(
                        'Restante',
                        'Restante após',
                        remainingAfter.isZero
                            ? '${remainingAfter.brl} · paga'
                            : remainingAfter.brl,
                      ),
                    ],
                  ),
                ),
              ),
              if (balanceAfter != null && balanceAfter.isNegative)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FormErrorBanner(
                    'O saldo de ${account!.name} ficará negativo (${balanceAfter.brl}).',
                  ),
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
                              ? 'Verificar pagamento'
                              : 'Confirmar pagamento',
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
                const SizedBox(height: 8),
                Text(
                  uncertain
                      ? 'Verificar reenvia este mesmo pagamento, com a mesma identificação: a API aplica uma única vez.'
                      : 'Nada foi gravado ainda. O saldo só muda depois que a API confirmar.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
