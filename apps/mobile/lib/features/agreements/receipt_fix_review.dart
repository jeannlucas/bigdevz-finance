import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../ui/widgets.dart';
import '../accounts/account.dart';
import '../auth/auth_models.dart';
import 'agreement.dart';

/// Substituto proposto numa correção; nulo no estorno.
typedef ReceiptReplacement = ({
  int accountId,
  String accountName,
  Money amount,
  String receivedOn,
});

/// Antes e depois de um estorno ou correção, com os efeitos nos saldos e no
/// restante da parcela. Nada é gravado até [onConfirm]; com tentativa
/// incerta, os dados ficam travados e só [onVerify] envia.
class ReceiptFixReview extends StatelessWidget {
  const ReceiptFixReview({
    super.key,
    required this.space,
    required this.installment,
    required this.original,
    required this.accounts,
    required this.reason,
    required this.replacement,
    required this.uncertain,
    required this.busy,
    required this.onConfirm,
    required this.onBack,
    required this.onVerify,
    required this.onLeave,
    this.notice,
  });

  final Space space;
  final Installment installment;
  final Receipt original;
  final List<Account> accounts;
  final String reason;
  final ReceiptReplacement? replacement;
  final bool uncertain;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onBack;
  final VoidCallback onVerify;
  final VoidCallback onLeave;
  final String? notice;

  bool get _correction => replacement != null;

  String _accountName(int id) =>
      accounts.where((a) => a.id == id).firstOrNull?.name ?? 'Conta';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final replacement = this.replacement;
    final deltas = <int, int>{original.accountId: -original.amount.cents};
    if (replacement != null) {
      deltas[replacement.accountId] =
          (deltas[replacement.accountId] ?? 0) + replacement.amount.cents;
    }
    final remainingAfter = Money(
      installment.remaining.cents +
          original.amount.cents -
          (replacement?.amount.cents ?? 0),
    );
    final verb = _correction ? 'correção' : 'estorno';

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SpaceBadge(space, prefix: 'Espaço'),
              const SizedBox(height: 16),
              if (uncertain) ...[
                FormErrorBanner(
                  notice ??
                      'Ainda não conseguimos confirmar ${_correction ? 'esta correção' : 'este estorno'}.',
                ),
                const SizedBox(height: 16),
              ],
              _Section(
                title: 'Antes',
                children: [
                  _Line('Antes-Valor', 'Valor', MoneyText(original.amount)),
                  _Line(
                    'Antes-Conta',
                    'Conta',
                    Text(_accountName(original.accountId)),
                  ),
                  _Line(
                    'Antes-Data',
                    'Data',
                    Text(formatDateBr(original.receivedOn)),
                  ),
                ],
              ),
              _Section(
                title: 'Depois',
                children: replacement == null
                    ? [
                        _Line(
                          'Depois-Valor',
                          'Recebimento',
                          const Text('Estornado, sem substituto'),
                        ),
                      ]
                    : [
                        _Line(
                          'Depois-Valor',
                          'Valor',
                          MoneyText(replacement.amount),
                        ),
                        _Line(
                          'Depois-Conta',
                          'Conta',
                          Text(replacement.accountName),
                        ),
                        _Line(
                          'Depois-Data',
                          'Data',
                          Text(formatDateBr(replacement.receivedOn)),
                        ),
                      ],
              ),
              _Section(
                title: 'Efeitos',
                children: [
                  for (final MapEntry(key: id, value: delta) in deltas.entries)
                    _Line(
                      'Saldo-$id',
                      _accountName(id),
                      Text(_balanceChange(id, delta)),
                    ),
                  _Line(
                    'Restante',
                    'Restante da parcela',
                    Text(
                      '${installment.remaining.brl} → ${remainingAfter.brl}',
                    ),
                  ),
                  _Line('Motivo', 'Motivo', Text(reason)),
                ],
              ),
              Text(
                'O recebimento original continua no histórico, marcado como '
                '${_correction ? 'corrigido' : 'estornado'}.',
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
                  onPressed: busy ? null : (uncertain ? onVerify : onConfirm),
                  child: busy
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Text(uncertain ? 'Verificar $verb' : 'Confirmar $verb'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: busy ? null : (uncertain ? onLeave : onBack),
                  child: Text(
                    uncertain ? 'Verificar depois' : 'Voltar e corrigir',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  uncertain
                      ? 'Verificar reenvia esta mesma operação, com a mesma '
                            'identificação: a API aplica uma única vez.'
                      : 'Nada foi gravado ainda. Os saldos só mudam depois que '
                            'a API confirmar.',
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

  String _balanceChange(int accountId, int delta) {
    final account = accounts.where((a) => a.id == accountId).firstOrNull;
    final sign = delta < 0 ? '−' : '+';
    final change = '$sign${Money(delta.abs()).brl}';
    if (account == null) return change;
    final after = Money(account.balance.cents + delta);
    return '$change · ${account.balance.brl} → ${after.brl}';
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line(this.id, this.label, this.value);

  final String id;
  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: ValueKey('fix-$id'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: DefaultTextStyle.merge(
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              child: value,
            ),
          ),
        ],
      ),
    );
  }
}
