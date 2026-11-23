import 'package:flutter/material.dart';

import '../../ui/app_tokens.dart';
import 'category_style_catalog.dart';

/// Seletor visual de ícone e cor de categoria com símbolos Material,
/// nomes em português, prévia de cor e aplicação automática da cor padrão ao selecionar ícone.
class CategoryIconColorPicker extends StatefulWidget {
  const CategoryIconColorPicker({
    super.key,
    required this.selectedIcon,
    required this.selectedColor,
    required this.onIconChanged,
    required this.onColorChanged,
    this.type = 'expense',
  });

  final String selectedIcon;
  final String selectedColor;
  final ValueChanged<String> onIconChanged;
  final ValueChanged<String> onColorChanged;
  final String type;

  @override
  State<CategoryIconColorPicker> createState() =>
      _CategoryIconColorPickerState();
}

class _CategoryIconColorPickerState extends State<CategoryIconColorPicker> {
  bool _customColorPicked = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Seção de Ícone
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Ícone e Símbolo',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            Text(
              CategoryStyleCatalog.getIconInfo(widget.selectedIcon).label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 248,
          decoration: BoxDecoration(
            color: isDark
                ? theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.3,
                  )
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppTokens.r12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Scrollbar(
            thumbVisibility: true,
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                mainAxisExtent: 52,
              ),
              itemCount: CategoryStyleCatalog.icons.length,
              itemBuilder: (context, index) {
                final info = CategoryStyleCatalog.icons[index];
                final isSelected = widget.selectedIcon == info.id;
                final iconColor = CategoryStyleCatalog.colorFromHex(
                  info.defaultColorHex,
                );

                return Tooltip(
                  message: info.label,
                  child: InkWell(
                    onTap: () {
                      widget.onIconChanged(info.id);
                      // Preenche automaticamente a cor padrão caso o usuário não tenha escolhido uma customizada
                      if (!_customColorPicked) {
                        widget.onColorChanged(info.defaultColorHex);
                      }
                    },
                    borderRadius: BorderRadius.circular(AppTokens.r8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.colorScheme.primaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppTokens.r8),
                        border: Border.all(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant.withValues(
                                  alpha: 0.3,
                                ),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            info.iconData,
                            size: 22,
                            color: isSelected
                                ? theme.colorScheme.primary
                                : iconColor,
                          ),
                          const SizedBox(height: 2),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: iconColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Seção de Cor
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Cor de Identificação',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: CategoryStyleCatalog.colorFromHex(widget.selectedColor)
                    .withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppTokens.r8),
                border: Border.all(
                  color: CategoryStyleCatalog.colorFromHex(
                    widget.selectedColor,
                  ),
                  width: 1,
                ),
              ),
              child: Text(
                widget.selectedColor.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? Colors.white
                      : CategoryStyleCatalog.readableOnLight(
                          CategoryStyleCatalog.colorFromHex(
                            widget.selectedColor,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final hex in CategoryStyleCatalog.presetColors)
              Builder(
                builder: (context) {
                  final isSelected =
                      widget.selectedColor.toUpperCase() == hex.toUpperCase();
                  final color = CategoryStyleCatalog.colorFromHex(hex);

                  return InkWell(
                    onTap: () {
                      _customColorPicked = true;
                      widget.onColorChanged(hex);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? (isDark ? Colors.white : Colors.black87)
                              : Colors.transparent,
                          width: isSelected ? 2.5 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.5),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: color.computeLuminance() > 0.5
                                  ? Colors.black87
                                  : Colors.white,
                            )
                          : null,
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}
