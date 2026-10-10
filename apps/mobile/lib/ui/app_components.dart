import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Cartão padronizado com borda suave e cantos elegantes.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTokens.p16),
    this.margin,
    this.color,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppTokens.r16),
        border: Border.all(
          color: theme.brightness == Brightness.dark
              ? AppTokens.darkBorder
              : AppTokens.lightBorder,
          width: 1,
        ),
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return card;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.r16),
      child: card,
    );
  }
}

/// Linha de detalhe/revisão com label e valor alinhados.
class ReviewRow extends StatelessWidget {
  const ReviewRow({
    super.key,
    required this.label,
    required this.value,
    this.valueWidget,
    this.isEmphasized = false,
  });

  final String label;
  final String value;
  final Widget? valueWidget;
  final bool isEmphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child:
                  valueWidget ??
                  Text(
                    value,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isEmphasized
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: isEmphasized ? theme.colorScheme.primary : null,
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
