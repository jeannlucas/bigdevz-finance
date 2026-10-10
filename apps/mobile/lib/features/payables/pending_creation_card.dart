import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../agreements/receipt_attempt.dart' show ReceiptAttemptState;
import 'payable_creations.dart';

/// Cadastro de A pagar sem confirmação da API. Verificar reenvia a mesma
/// tentativa; enquanto pendente, outro cadastro no espaço fica bloqueado.
class PendingCreationCard extends StatefulWidget {
  const PendingCreationCard({
    super.key,
    required this.pending,
    required this.onSettled,
    this.notice,
  });

  final PendingCreation pending;

  /// Motivo da última falha (ex.: sem conexão), quando conhecido.
  final String? notice;

  /// Chamado com o resultado confirmado ou recusado.
  final ValueChanged<CreationOutcome> onSettled;

  @override
  State<PendingCreationCard> createState() => _PendingCreationCardState();
}

class _PendingCreationCardState extends State<PendingCreationCard> {
  bool _verifying = false;
  bool _settled = false;
  late String? _message = widget.notice;

  Future<void> _verify() async {
    if (_verifying || _settled) return;
    setState(() => _verifying = true);
    final outcome = await context.read<PayableCreations>().resolve(
      widget.pending,
    );
    if (!mounted) return;
    setState(() {
      _verifying = false;
      _settled = outcome.state != ReceiptAttemptState.uncertain;
      _message = outcome.message;
    });
    if (_settled) widget.onSettled(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E);
    final bgColor = isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7);
    final borderColor = isDark
        ? const Color(0xFF78350F)
        : const Color(0xFFFDE68A);

    return Container(
      key: const ValueKey('pending-creation'),
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
                  'Cadastro aguardando confirmação',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${widget.pending.description} · ${widget.pending.kindLabel}',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              _message ??
                  'Ainda não conseguimos confirmar este cadastro. Verifique '
                      'antes de cadastrar outro.',
              style: TextStyle(color: color, fontSize: 13),
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
                : const Text('Verificar cadastro'),
          ),
          const SizedBox(height: 8),
          Text(
            'Verificar reenvia o mesmo cadastro, com a mesma identificação: '
            'se já foi gravado, a API só confirma; se não chegou, é '
            'registrado uma única vez.',
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
