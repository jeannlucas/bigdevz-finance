import 'package:flutter/material.dart';

import '../core/dates.dart';
import 'app_icons.dart';
import 'app_tokens.dart';

/// Campo de data de calendário com seletor em pt-BR e Hugeicons.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.errorText,
    this.helperText,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String? errorText;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final isTextEnlarged = textScaler.scale(1.0) > 1.2;

    final field = InkWell(
      borderRadius: BorderRadius.circular(AppTokens.r12),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: firstDate ?? DateTime(2000),
          lastDate: lastDate ?? DateTime(2100),
        );
        if (picked != null) onChanged(DateUtils.dateOnly(picked));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: isTextEnlarged ? null : label,
          prefixIconConstraints: const BoxConstraints(
            minWidth: 48,
            minHeight: 48,
          ),
          prefixIcon: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox.square(
              dimension: 22,
              child: Center(child: AppIcon(AppIcons.calendar, size: 20)),
            ),
          ),
          errorText: errorText,
          helperText: helperText,
          helperMaxLines: 3,
        ),
        child: Text(
          formatDateBr(toApiDate(value)),
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w500),
        ),
      ),
    );

    if (isTextEnlarged) {
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 6),
            field,
          ],
        ),
      );
    }

    return field;
  }
}
