import 'package:flutter/material.dart';

import 'receipt_attempts.dart';

/// Escolha obrigatória entre recebimento total e parcial.
class ReceiptKindField extends FormField<ReceiptKind> {
  ReceiptKindField({
    super.key,
    required super.initialValue,
    required ValueChanged<ReceiptKind?> onChanged,
  }) : super(
         validator: (value) => value == null
             ? 'Escolha se o recebimento é total ou parcial.'
             : null,
         builder: (field) {
           final theme = Theme.of(field.context);
           return Column(
             crossAxisAlignment: CrossAxisAlignment.stretch,
             children: [
               Text('Tipo de recebimento', style: theme.textTheme.labelLarge),
               const SizedBox(height: 8),
               SegmentedButton<ReceiptKind>(
                 emptySelectionAllowed: true,
                 segments: const [
                   ButtonSegment(
                     value: ReceiptKind.total,
                     label: Text('Total'),
                     icon: Icon(Icons.done_all),
                   ),
                   ButtonSegment(
                     value: ReceiptKind.partial,
                     label: Text('Parcial'),
                     icon: Icon(Icons.timelapse),
                   ),
                 ],
                 selected: {?field.value},
                 onSelectionChanged: (selection) {
                   field.didChange(selection.firstOrNull);
                   onChanged(selection.firstOrNull);
                 },
               ),
               if (field.hasError) ...[
                 const SizedBox(height: 6),
                 Text(
                   field.errorText!,
                   style: theme.textTheme.bodySmall?.copyWith(
                     color: theme.colorScheme.error,
                   ),
                 ),
               ],
             ],
           );
         },
       );
}
