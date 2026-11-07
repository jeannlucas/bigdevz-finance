import 'package:flutter/material.dart';

import '../../ui/app_tokens.dart';
import 'category.dart';

/// Badge visual para exibição elegante de categoria financeira.
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({
    super.key,
    required this.category,
    this.compact = false,
  });

  final Category category;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final catColor = category.colorValue;

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: catColor.withValues(alpha: isDark ? 0.22 : 0.12),
          borderRadius: BorderRadius.circular(AppTokens.r8),
          border: Border.all(
            color: catColor.withValues(alpha: isDark ? 0.45 : 0.28),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(category.iconData, size: 11, color: catColor),
            const SizedBox(width: 4),
            Text(
              category.name,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: isDark ? catColor.withValues(alpha: 0.95) : catColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: catColor.withValues(alpha: isDark ? 0.20 : 0.10),
        borderRadius: BorderRadius.circular(AppTokens.r10),
        border: Border.all(
          color: catColor.withValues(alpha: isDark ? 0.40 : 0.25),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: catColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(category.iconData, size: 12, color: catColor),
          ),
          const SizedBox(width: 6),
          Text(
            category.name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : theme.colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
