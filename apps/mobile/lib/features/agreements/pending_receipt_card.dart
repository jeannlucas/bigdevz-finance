import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import 'receipt_attempts.dart';

/// Tentativa de recebimento guardada e ainda sem confirmação da API. Ocupa o
/// lugar de "Registrar recebimento" até ser resolvida.
class PendingReceiptCard extends StatefulWidget {
  const PendingReceiptCard({
    super.key,
    required this.attempt,
    required this.onSettled,
  });

  final ReceiptAttempt attempt;

  /// Chamado com o resultado confirmado ou recusado.
  final ValueChanged<ReceiptAttemptOutcome> onSettled;

  @override
  State<PendingReceiptCard> createState() => _PendingReceiptCardState();
}

class _PendingReceiptCardState extends State<PendingReceiptCard> {
  bool _verifying = false;

  /// Resolvida: o cartão some na recarga e não aceita novos toques.
  bool _settled = false;
  String? _message;

  Future<void> _verify() async {
    if (_verifying || _settled) return;
    setState(() => _verifying = true);
    final outcome = await context.read<ReceiptAttempts>().resolve(
      widget.attempt,
    );
    if (!mounted) return;
    setState(() {
      _verifying = false;
      _settled = outcome.state != ReceiptAttemptState.uncertain;
      _message = outcome.message;
    });
    if (outcome.state != ReceiptAttemptState.uncertain) {
      widget.onSettled(outcome);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final attempt = widget.attempt;
    final color = isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E);
    final bgColor = isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7);
    final borderColor = isDark
        ? const Color(0xFF78350F)
        : const Color(0xFFFDE68A);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppTokens.r16),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(AppTokens.p16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIcon(AppIcons.pending, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  switch (attempt.operation) {
                    ReceiptOperation.receipt =>
                      'Recebimento aguardando confirmação',
                    ReceiptOperation.reversal =>
                      'Estorno aguardando confirmação',
                    ReceiptOperation.correction =>
                      'Correção aguardando confirmação',
                    ReceiptOperation.payment =>
                      'Pagamento aguardando confirmação',
                    ReceiptOperation.paymentReversal =>
                      'Estorno do pagamento aguardando confirmação',
                    ReceiptOperation.paymentCorrection =>
                      'Correção do pagamento aguardando confirmação',
                  },
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              _message ??
                  'Ainda não conseguimos confirmar ${attempt.subject}. '
                      'Verifique a tentativa anterior antes de fazer outra '
                      'operação ${attempt.operation.isPayment ? 'nesta obrigação' : 'nesta parcela'}.',
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? Colors.black26 : Colors.white60,
              borderRadius: BorderRadius.circular(AppTokens.r8),
            ),
            child: Text(
              '${attempt.accountName} · ${formatDateBr(attempt.receivedOn)}',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: isDark
                  ? const Color(0xFFD97706)
                  : const Color(0xFFB45309),
              foregroundColor: Colors.white,
            ),
            onPressed: _verifying || _settled ? null : _verify,
            child: _verifying
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text('Verificar recebimento'),
          ),
          const SizedBox(height: 8),
          Text(
            'Verificar reenvia a mesma tentativa, com a mesma identificação: '
            'se a API já gravou, ela só confirma; se não recebeu, grava uma '
            'única vez.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
