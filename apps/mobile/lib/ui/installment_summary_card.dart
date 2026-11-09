import 'package:flutter/material.dart';

import '../core/money.dart';
import 'app_tokens.dart';

/// Card compacto e discreto que resume o parcelamento
/// exibindo a quantidade de parcelas, o valor de cada parcela e o total.
class InstallmentSummaryCard extends StatelessWidget {
  const InstallmentSummaryCard({
    super.key,
    required this.installmentCount,
    required this.installmentAmount,
    required this.totalAmount,
    this.isByInstallmentMode = true,
  });

  final int installmentCount;
  final Money installmentAmount;
  final Money totalAmount;
  final bool isByInstallmentMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark
        ? AppTokens.brandPrimary.withValues(alpha: 0.15)
        : AppTokens.brandPrimary.withValues(alpha: 0.08);

    final borderColor = isDark
        ? AppTokens.brandPrimary.withValues(alpha: 0.3)
        : AppTokens.brandPrimary.withValues(alpha: 0.2);

    final primaryColor = isDark
        ? const Color(0xFF818CF8) // tom mais claro para modo escuro
        : AppTokens.brandPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(Icons.calculate_outlined, size: 20, color: primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.3),
                children: [
                  TextSpan(
                    text:
                        '$installmentCount parcelas de ${installmentAmount.brl}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                  const TextSpan(
                    text: ' • Total: ',
                    style: TextStyle(color: AppTokens.neutral),
                  ),
                  TextSpan(
                    text: totalAmount.brl,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
