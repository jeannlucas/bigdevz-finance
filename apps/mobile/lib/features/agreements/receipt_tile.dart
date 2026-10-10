import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../../ui/widgets.dart';
import 'agreement.dart';

/// Recebimento no histórico da parcela. Estornados e corrigidos continuam
/// visíveis, identificados e sem efeito no saldo; só ativos têm ações.
class ReceiptTile extends StatelessWidget {
  const ReceiptTile({
    super.key,
    required this.receipt,
    required this.accountName,
    this.onCorrect,
    this.onReverse,
  });

  final Receipt receipt;
  final String accountName;

  /// Nulos quando o recebimento está estornado ou a parcela tem operação
  /// pendente.
  final VoidCallback? onCorrect;
  final VoidCallback? onReverse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reversal = receipt.reversal;
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      key: ValueKey('receipt-${receipt.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: reversal == null
              ? AppTokens.income.withValues(alpha: 0.12)
              : theme.colorScheme.surfaceContainerHighest,
          child: AppIcon(
            reversal == null ? AppIcons.check : AppIcons.reverse,
            size: 18,
            color: reversal == null ? AppTokens.income : muted,
          ),
        ),
        // Wrap: com texto grande, a etiqueta desce em vez de estourar.
        title: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            MoneyText(
              receipt.amount,
              style: reversal == null
                  ? const TextStyle(fontWeight: FontWeight.w700)
                  : TextStyle(
                      color: muted,
                      decoration: TextDecoration.lineThrough,
                    ),
            ),
            if (reversal != null)
              StatusChip(
                label: reversal.isCorrection ? 'Corrigido' : 'Estornado',
                tone: StatusTone.neutral,
              ),
          ],
        ),
        subtitle: Text(
          [
            '${formatDateBr(receipt.receivedOn)} · $accountName',
            if (receipt.replacesReceiptId != null)
              'Substitui um recebimento corrigido',
            if (reversal != null) 'Motivo: ${reversal.reason}',
          ].join('\n'),
        ),
        isThreeLine: reversal != null || receipt.replacesReceiptId != null,
        trailing: onCorrect == null && onReverse == null
            ? null
            : PopupMenuButton<VoidCallback>(
                tooltip: 'Ações do recebimento',
                icon: const AppIcon(AppIcons.more, size: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTokens.r12),
                ),
                onSelected: (action) => action(),
                itemBuilder: (_) => [
                  if (onCorrect != null)
                    PopupMenuItem<VoidCallback>(
                      value: onCorrect,
                      child: const Row(
                        children: [
                          AppIcon(AppIcons.correction, size: 18),
                          SizedBox(width: 8),
                          Flexible(child: Text('Corrigir recebimento')),
                        ],
                      ),
                    ),
                  if (onReverse != null)
                    PopupMenuItem<VoidCallback>(
                      value: onReverse,
                      child: const Row(
                        children: [
                          AppIcon(AppIcons.reverse, size: 18),
                          SizedBox(width: 8),
                          Flexible(child: Text('Estornar recebimento')),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
