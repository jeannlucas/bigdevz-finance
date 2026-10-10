import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../ui/date_field.dart';
import '../../ui/widgets.dart';
import '../accounts/account.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import 'agreement.dart';
import 'receipt_attempts.dart';
import 'receipt_fix_review.dart';

/// Correção (estorno + substituto) ou estorno de um recebimento confirmado,
/// em duas etapas: preencher e revisar. Segue o mesmo protocolo de tentativa
/// do recebimento: guardada antes do envio, travada se a resposta for
/// incerta. Fecha com o [ReceiptAttemptOutcome] confirmado.
class ReceiptFixScreen extends StatefulWidget {
  const ReceiptFixScreen({
    super.key,
    required this.space,
    required this.installment,
    required this.original,
    required this.accounts,
    required this.correction,
    this.today,
  });

  final Space space;
  final Installment installment;
  final Receipt original;
  final List<Account> accounts;

  /// Verdadeiro: corrigir; falso: só estornar.
  final bool correction;
  final DateTime? today;

  @override
  State<ReceiptFixScreen> createState() => _ReceiptFixScreenState();
}

class _ReceiptFixScreenState extends State<ReceiptFixScreen> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late final _amount = TextEditingController(
    text: widget.original.amount.plain,
  );
  late final DateTime _today = DateUtils.dateOnly(
    widget.today ?? DateTime.now(),
  );
  late DateTime _date = parseApiDate(widget.original.receivedOn);

  /// Substituto só em conta ativa; se a original foi arquivada, a escolha
  /// fica em aberto.
  late int? _accountId =
      _selectable.any((a) => a.id == widget.original.accountId)
      ? widget.original.accountId
      : null;

  List<Account> get _selectable =>
      widget.accounts.where((account) => !account.isArchived).toList();

  bool _reviewing = false;
  ReceiptAttemptState _state = ReceiptAttemptState.ready;
  ReceiptAttempt? _attempt;
  String? _notice;
  ApiException? _error;
  String? _localError;

  /// Disponível para o substituto: o restante mais o valor estornado.
  Money get _available =>
      Money(widget.installment.remaining.cents + widget.original.amount.cents);
  bool get _busy => _state == ReceiptAttemptState.sending;
  String get _verb => widget.correction ? 'correção' : 'estorno';

  String _accountName(int id) =>
      widget.accounts.where((a) => a.id == id).firstOrNull?.name ?? 'Conta';

  ReceiptReplacement? get _replacement {
    final attempt = _attempt;
    if (attempt != null) {
      return attempt.operation == ReceiptOperation.correction
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
      accountName: _accountName(_accountId!),
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
    final replacement = _replacement;
    final ReceiptAttemptOutcome outcome;
    try {
      outcome = await context.read<ReceiptAttempts>().submitFix(
        userId: user.id,
        spaceId: widget.space.id,
        installmentId: widget.installment.id,
        original: widget.original,
        originalAccountName: _accountName(widget.original.accountId),
        reason: _reason.text.trim(),
        replacement: replacement,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _state = ReceiptAttemptState.ready;
          _reviewing = false;
          _localError =
              'Não foi possível guardar a operação neste aparelho. Nada foi '
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
      case _ when outcome.attempt.targetReceiptId != widget.original.id:
        // Outra operação pendente na parcela: resolve-se na tela da parcela.
        session.dataChanged();
        setState(() {
          _state = ReceiptAttemptState.ready;
          _reviewing = false;
          _localError =
              'Há outra operação sem confirmação nesta parcela. Volte e '
              'verifique antes de fazer esta.';
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
                      ? 'Corrigir recebimento'
                      : 'Estornar recebimento')
                : uncertain
                ? '${_verb[0].toUpperCase()}${_verb.substring(1)} não confirmad${widget.correction ? 'a' : 'o'}'
                : 'Confirme ${widget.correction ? 'a correção' : 'o estorno'}',
          ),
        ),
        body: _reviewing
            ? ReceiptFixReview(
                space: widget.space,
                installment: widget.installment,
                original: widget.original,
                accounts: widget.accounts,
                reason: _attempt?.reason ?? _reason.text.trim(),
                replacement: _replacement,
                uncertain: uncertain,
                busy: _busy,
                notice: _notice,
                onConfirm: _confirm,
                onBack: () => setState(() => _reviewing = false),
                onVerify: _verify,
                onLeave: () => Navigator.of(context).maybePop(),
              )
            : _buildForm(context),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final original = widget.original;
    final fieldErrors = _error?.fieldErrors ?? const {};
    final account = widget.accounts
        .where((item) => item.id == _accountId)
        .firstOrNull;
    final banner = _error == null
        ? _localError
        : fieldErrors.isEmpty
        ? 'A API recusou a operação e nada foi gravado: ${_error!.message}'
        : 'A API recusou a operação e nada foi gravado. '
              '${fieldErrors['receipt'] ?? 'Corrija os dados e revise de novo.'}';

    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SpaceBadge(widget.space, prefix: 'Espaço'),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('Recebimento original'),
              subtitle: Text(
                '${original.amount.brl} · ${_accountName(original.accountId)} · '
                '${formatDateBr(original.receivedOn)}',
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (banner != null) ...[
            FormErrorBanner(banner),
            const SizedBox(height: 16),
          ],
          if (widget.correction) ...[
            DropdownButtonFormField<int>(
              initialValue: _accountId,
              decoration: InputDecoration(
                labelText: 'Conta de destino',
                errorText: fieldErrors['account_id'],
              ),
              items: [
                for (final item in _selectable)
                  DropdownMenuItem(value: item.id, child: Text(item.name)),
              ],
              hint: const Text('Escolha a conta'),
              validator: (value) =>
                  value == null ? 'Escolha a conta de destino.' : null,
              onChanged: (value) => setState(() => _accountId = value),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amount,
              decoration: InputDecoration(
                labelText: 'Valor correto',
                prefixText: r'R$ ',
                helperText: 'Até ${_available.brl} nesta parcela.',
                errorText: fieldErrors['amount'],
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
                    toApiDate(_date) == original.receivedOn) {
                  return 'Altere a conta, o valor ou a data. Para só desfazer, '
                      'use Estornar.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DateField(
              label: 'Data correta do recebimento',
              value: _date,
              firstDate: account != null
                  ? parseApiDate(account.openingBalanceDate)
                  : DateTime(2000),
              lastDate: _today,
              errorText: fieldErrors['received_on'],
              onChanged: (date) => setState(() => _date = date),
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: _reason,
            decoration: InputDecoration(
              labelText: 'Motivo',
              helperText: widget.correction
                  ? 'Ex.: conta errada, valor digitado errado.'
                  : 'Ex.: recebimento registrado por engano.',
              errorText: fieldErrors['reason'],
            ),
            maxLength: 500,
            validator: (value) => (value ?? '').trim().length < 3
                ? 'Informe o motivo (pelo menos 3 caracteres).'
                : null,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _review, child: Text('Revisar $_verb')),
          const SizedBox(height: 8),
          Text(
            'Você confere antes e depois antes de enviar.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
