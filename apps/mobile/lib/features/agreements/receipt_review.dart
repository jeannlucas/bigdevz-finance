import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import 'agreement.dart';
import 'receipt_attempts.dart';

/// Dados de um recebimento já validados no app.
class ReceiptDraft {
  const ReceiptDraft({
    required this.kind,
    required this.accountId,
    required this.accountName,
    required this.amount,
    required this.receivedOn,
  });

  /// Conteúdo exato de uma tentativa guardada, para exibir sem editar.
  factory ReceiptDraft.of(ReceiptAttempt attempt) => ReceiptDraft(
    // Só recebimentos chegam aqui; registros antigos sempre têm o tipo.
    kind: attempt.kind ?? ReceiptKind.partial,
    accountId: attempt.accountId,
    accountName: attempt.accountName,
    amount: attempt.amount,
    receivedOn: attempt.receivedOn,
  );

  final ReceiptKind kind;
  final int accountId;
  final String accountName;
  final Money amount;
  final String receivedOn;
}

/// Resumo do recebimento. Pronto: nada é gravado até [onConfirm]. Incerto:
/// os dados ficam travados e a única ação de envio é [onVerify], que repete
/// a mesma tentativa.
class ReceiptReview extends StatelessWidget {
  const ReceiptReview({
    super.key,
    required this.space,
    required this.installment,
    required this.draft,
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
  final ReceiptDraft draft;

  /// Há tentativa guardada sem resposta conclusiva da API.
  final bool uncertain;

  /// Envio ou verificação em andamento.
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onBack;
  final VoidCallback onVerify;
  final VoidCallback onLeave;

  /// Mensagem do último resultado incerto.
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remainingAfter = Money(
      installment.remaining.cents - draft.amount.cents,
    );

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SpaceBadge(space, prefix: 'Recebimento no espaço'),
              const SizedBox(height: 16),
              if (uncertain) ...[
                FormErrorBanner(
                  notice ??
                      'Ainda não conseguimos confirmar este recebimento. '
                          'Verifique a tentativa anterior antes de registrar '
                          'outro para esta parcela.',
                ),
                const SizedBox(height: 16),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _Line(
                        id: 'Acordo',
                        label: 'Acordo',
                        value: Text(
                          installment.agreementDescription ?? 'Acordo',
                        ),
                      ),
                      _Line(
                        id: 'Parcela',
                        label: 'Parcela',
                        value: Text(
                          '${installment.number}/${installment.installmentCount ?? '?'}'
                          ' · vence ${formatDateBr(installment.dueDate)}',
                        ),
                      ),
                      _Line(
                        id: 'Tipo',
                        label: 'Tipo',
                        value: Text(
                          draft.kind == ReceiptKind.total ? 'Total' : 'Parcial',
                        ),
                      ),
                      const Divider(height: 24),
                      _Line(
                        id: 'Valor',
                        label: 'Valor a receber',
                        value: MoneyText(
                          draft.amount,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _Line(
                        id: 'Conta',
                        label: 'Conta de destino',
                        value: Text(draft.accountName),
                      ),
                      _Line(
                        id: 'Espaço',
                        label: 'Espaço',
                        value: Text(space.label),
                      ),
                      _Line(
                        id: 'Data',
                        label: 'Data do recebimento',
                        value: Text(formatDateBr(draft.receivedOn)),
                      ),
                      const Divider(height: 24),
                      _Line(
                        id: 'Restante',
                        label: 'Restante da parcela após',
                        value: Text(
                          remainingAfter.isZero
                              ? '${remainingAfter.brl} · parcela quitada'
                              : remainingAfter.brl,
                          style: const TextStyle(
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Ações fixas: confirmar e voltar ficam sempre à vista.
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
                      : Text(
                          uncertain
                              ? 'Verificar recebimento'
                              : 'Confirmar recebimento',
                        ),
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
                      ? 'Verificar reenvia esta mesma tentativa, com a mesma '
                            'identificação: se ela já foi gravada, a API só '
                            'confirma; se não chegou, é registrada uma única vez.'
                      : 'Nada foi gravado ainda. O saldo só muda depois que a '
                            'API confirmar.',
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

class _Line extends StatelessWidget {
  const _Line({required this.id, required this.label, required this.value});

  final String id;
  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: ValueKey('review-$id'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
              child: value,
            ),
          ),
        ],
      ),
    );
  }
}
