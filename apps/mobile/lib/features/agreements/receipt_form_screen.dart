import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../ui/app_icons.dart';
import '../../ui/date_field.dart';
import '../../ui/widgets.dart';
import '../accounts/account.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import 'agreement.dart';
import 'receipt_attempts.dart';
import 'receipt_kind_field.dart';
import 'receipt_review.dart';

/// Registro de recebimento total ou parcial, em duas etapas: preencher e
/// revisar. Nada é enviado antes da confirmação na revisão.
///
/// Confirmar guarda a tentativa no aparelho e a envia ([ReceiptAttempts]).
/// Sem resposta conclusiva, a tentativa fica travada: só pode ser verificada
/// com a mesma chave e o mesmo conteúdo, nunca alterada ou trocada por outra.
/// Fecha com o [ReceiptAttemptOutcome] confirmado.
class ReceiptFormScreen extends StatefulWidget {
  const ReceiptFormScreen({
    super.key,
    required this.space,
    required this.installment,
    required this.accounts,
    this.today,
  });

  final Space space;
  final Installment installment;
  final List<Account> accounts;
  final DateTime? today;

  @override
  State<ReceiptFormScreen> createState() => _ReceiptFormScreenState();
}

class _ReceiptFormScreenState extends State<ReceiptFormScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  late final DateTime _today = DateUtils.dateOnly(
    widget.today ?? DateTime.now(),
  );
  late DateTime _date = _today;
  int? _accountId;
  ReceiptKind? _kind;

  /// Recebimento em revisão; nulo enquanto o formulário está na tela.
  ReceiptDraft? _draft;
  ReceiptAttemptState _state = ReceiptAttemptState.ready;

  /// Tentativa guardada sem resposta conclusiva.
  ReceiptAttempt? _attempt;
  String? _notice;

  /// Recusa definitiva da API, exibida no formulário.
  ApiException? _error;
  String? _localError;

  Money get _remaining => widget.installment.remaining;

  /// Contas arquivadas não recebem operações novas (a API também recusa).
  List<Account> get _selectable =>
      widget.accounts.where((account) => !account.isArchived).toList();
  bool get _busy => _state == ReceiptAttemptState.sending;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _review() {
    if (!_form.currentState!.validate()) return;
    final account = _selectable.firstWhere((item) => item.id == _accountId);
    setState(() {
      _error = null;
      _localError = null;
      _draft = ReceiptDraft(
        kind: _kind!,
        accountId: account.id,
        accountName: account.name,
        amount: _kind == ReceiptKind.total
            ? _remaining
            : Money.fromInput(_amount.text)!,
        receivedOn: toApiDate(_date),
      );
    });
  }

  void _backToForm() {
    if (_state == ReceiptAttemptState.ready) setState(() => _draft = null);
  }

  Future<void> _confirm() async {
    final draft = _draft;
    final user = context.read<SessionController>().user;
    if (_state != ReceiptAttemptState.ready || draft == null || user == null) {
      return;
    }
    setState(() => _state = ReceiptAttemptState.sending);
    final ReceiptAttemptOutcome outcome;
    try {
      outcome = await context.read<ReceiptAttempts>().submit(
        userId: user.id,
        spaceId: widget.space.id,
        installmentId: widget.installment.id,
        accountId: draft.accountId,
        accountName: draft.accountName,
        amount: draft.amount,
        receivedOn: draft.receivedOn,
        kind: draft.kind,
      );
    } catch (_) {
      // A tentativa é guardada antes do envio; se guardar falhou, nada saiu.
      if (mounted) {
        setState(() {
          _state = ReceiptAttemptState.ready;
          _draft = null;
          _localError =
              'Não foi possível guardar a tentativa neste aparelho. Nada foi '
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
          _notice = null;
          _draft = null;
          _error = outcome.error;
        });
      case _ when outcome.attempt.operation != ReceiptOperation.receipt:
        // Estorno ou correção pendente na parcela: resolve-se na parcela.
        session.dataChanged();
        setState(() {
          _state = ReceiptAttemptState.ready;
          _draft = null;
          _localError =
              'Há um estorno ou uma correção sem confirmação nesta parcela. '
              'Volte e verifique antes de registrar outro recebimento.';
        });
      case _:
        // Telas por trás passam a mostrar a tentativa pendente.
        session.dataChanged();
        setState(() {
          _state = ReceiptAttemptState.uncertain;
          _attempt = outcome.attempt;
          _draft = ReceiptDraft.of(outcome.attempt);
          _notice = outcome.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectable.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Registrar recebimento')),
        body: widget.accounts.isEmpty
            ? const EmptyState(
                icon: AppIcons.accounts,
                title: 'Nenhuma conta neste espaço',
                message:
                    'Cadastre uma conta deste espaço para receber a parcela.',
              )
            : const EmptyState(
                icon: AppIcons.archive,
                title: 'Nenhuma conta ativa neste espaço',
                message:
                    'As contas deste espaço estão arquivadas. Reative uma ou '
                    'cadastre outra para receber a parcela.',
              ),
      );
    }

    final draft = _draft;
    final uncertain = _attempt != null;
    return PopScope(
      // Durante o envio nada sai. Na revisão pronta, voltar retorna ao
      // formulário; com tentativa incerta, sair a mantém guardada.
      canPop: !_busy && (draft == null || uncertain),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToForm();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            draft == null
                ? 'Registrar recebimento'
                : uncertain
                ? 'Recebimento não confirmado'
                : 'Confirme o recebimento',
          ),
        ),
        body: draft == null
            ? _buildForm(context)
            : ReceiptReview(
                space: widget.space,
                installment: widget.installment,
                draft: draft,
                uncertain: uncertain,
                busy: _busy,
                notice: _notice,
                onConfirm: _confirm,
                onBack: _backToForm,
                onVerify: _verify,
                onLeave: () => Navigator.of(context).maybePop(),
              ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final installment = widget.installment;
    final fieldErrors = _error?.fieldErrors ?? const {};
    final account = _selectable
        .where((item) => item.id == _accountId)
        .firstOrNull;
    final banner = _error == null
        ? _localError
        : fieldErrors.isEmpty
        ? 'A API recusou a tentativa e nada foi gravado: ${_error!.message}'
        : 'A API recusou a tentativa e nada foi gravado. Corrija os dados e '
              'revise de novo.';

    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SpaceBadge(widget.space, prefix: 'Recebimento no espaço'),
          const SizedBox(height: 12),
          Text(
            'Parcela ${installment.number}${installment.installmentCount != null ? '/${installment.installmentCount}' : ''}'
            '${installment.agreementDescription != null ? ' · ${installment.agreementDescription}' : ''}\n'
            'Falta receber ${installment.remaining.brl}',
            style: theme.textTheme.bodyMedium,
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
              labelText: 'Conta de destino',
              errorText: fieldErrors['account_id'],
            ),
            items: [
              for (final item in _selectable)
                DropdownMenuItem(value: item.id, child: Text(item.name)),
            ],
            validator: (value) =>
                value == null ? 'Escolha a conta de destino.' : null,
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
                labelText: 'Valor recebido',
                helperText: 'Valor integral que falta na parcela.',
                errorText: fieldErrors['amount'],
              ),
              child: MoneyText(_remaining),
            )
          else if (_kind == ReceiptKind.partial)
            TextFormField(
              controller: _amount,
              decoration: InputDecoration(
                labelText: 'Valor recebido',
                prefixText: r'R$ ',
                helperText: 'Menor que o valor que falta na parcela.',
                errorText: fieldErrors['amount'],
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [MoneyInputFormatter()],
              validator: (value) {
                final amount = Money.fromInput(value ?? '');
                if (amount == null || amount.isZero) {
                  return 'Informe o valor recebido.';
                }
                if (amount.cents == _remaining.cents) {
                  return 'Esse é o valor integral da parcela: escolha Total.';
                }
                if (amount.cents > _remaining.cents) {
                  return 'Máximo para esta parcela: ${_remaining.brl}.';
                }
                return null;
              },
            ),
          const SizedBox(height: 16),
          DateField(
            label: 'Data do recebimento',
            value: _date,
            firstDate: account != null
                ? parseApiDate(account.openingBalanceDate)
                : DateTime(2000),
            lastDate: _today,
            errorText: fieldErrors['received_on'],
            onChanged: (date) => setState(() => _date = date),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _review,
            child: const Text('Revisar recebimento'),
          ),
          const SizedBox(height: 8),
          Text(
            'Você confere tudo antes de enviar.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
