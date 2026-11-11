import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../features/settings/preferences_controller.dart';
import '../app_tokens.dart';
import '../widgets.dart';
import 'financial_item_view.dart';

/// Cabeçalho colapsável para grupos temporais da agenda financeira.
class FinancialGroupHeader extends StatelessWidget {
  const FinancialGroupHeader({
    super.key,
    required this.group,
    required this.count,
    required this.total,
    required this.isExpanded,
    required this.onToggleExpanded,
    this.singularLabel = 'item',
    this.pluralLabel = 'itens',
  });

  final FinancialDueDateGroup group;
  final int count;
  final Money total;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;
  final String singularLabel;
  final String pluralLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final obscure =
        context.watch<PreferencesController?>()?.obscureValues ?? false;

    return InkWell(
      onTap: onToggleExpanded,
      borderRadius: BorderRadius.circular(AppTokens.r12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            // Ícone com cor de destaque do grupo
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: group.accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTokens.r8),
              ),
              child: Icon(group.icon, size: 16, color: group.accentColor),
            ),
            const SizedBox(width: 8),

            // Título do Grupo
            Flexible(
              child: Text(
                group.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),

            // Badge de Contagem compacta
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppTokens.r12),
              ),
              child: Text(
                '$count',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Total do Grupo (se houver valor)
            if (total.cents > 0) ...[
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: MoneyText(
                    total,
                    obscure: obscure,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: group == FinancialDueDateGroup.overdue
                          ? AppTokens.expense
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ] else ...[
              const Spacer(),
            ],

            const SizedBox(width: 4),

            // Ícone de Expandir/Recolher
            Icon(
              isExpanded
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_right_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
