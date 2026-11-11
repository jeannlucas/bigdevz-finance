import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/text_formatters.dart';
import '../../ui/app_tokens.dart';
import 'categories_repository.dart';
import 'category.dart';

/// Chip de filtro por categoria com seleção via PopupMenu/Dialog.
class CategoryFilterChip extends StatefulWidget {
  const CategoryFilterChip({
    super.key,
    required this.spaceId,
    this.type,
    required this.selectedCategoryId,
    required this.onChanged,
  });

  final int spaceId;
  final String? type; // 'expense', 'income' ou null para todas
  final int? selectedCategoryId;
  final ValueChanged<int?> onChanged;

  @override
  State<CategoryFilterChip> createState() => _CategoryFilterChipState();
}

class _CategoryFilterChipState extends State<CategoryFilterChip> {
  List<Category> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void didUpdateWidget(covariant CategoryFilterChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spaceId != widget.spaceId || oldWidget.type != widget.type) {
      _loadCategories();
    }
  }

  Future<void> _loadCategories() async {
    try {
      final repo = context.read<CategoriesRepository>();
      final list = await repo.list(widget.spaceId, type: widget.type);
      if (mounted) {
        setState(() => _categories = list);
      }
    } catch (_) {}
  }

  void _showPicker(BuildContext context) {
    final theme = Theme.of(context);

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTokens.r20),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTokens.p16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.p20,
                  vertical: AppTokens.p8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Filtrar por Categoria',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (widget.selectedCategoryId != null)
                      TextButton(
                        onPressed: () {
                          widget.onChanged(null);
                          Navigator.of(ctx).pop();
                        },
                        child: const Text('Limpar filtro'),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.apps_rounded,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      title: const Text('Todas as categorias'),
                      trailing: widget.selectedCategoryId == null
                          ? Icon(Icons.check, color: theme.colorScheme.primary)
                          : null,
                      onTap: () {
                        widget.onChanged(null);
                        Navigator.of(ctx).pop();
                      },
                    ),
                    for (final cat in _categories)
                      ListTile(
                        leading: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: cat.colorValue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            cat.iconData,
                            size: 18,
                            color: cat.colorValue,
                          ),
                        ),
                        title: Text(toFinancialUpper(cat.name)),
                        trailing: widget.selectedCategoryId == cat.id
                            ? Icon(
                                Icons.check,
                                color: theme.colorScheme.primary,
                              )
                            : null,
                        onTap: () {
                          widget.onChanged(cat.id);
                          Navigator.of(ctx).pop();
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCat = widget.selectedCategoryId == null
        ? null
        : _categories.cast<Category?>().firstWhere(
            (c) => c?.id == widget.selectedCategoryId,
            orElse: () => null,
          );

    final isFiltered = selectedCat != null;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isFiltered,
        avatar: isFiltered
            ? Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: selectedCat.colorValue,
                  shape: BoxShape.circle,
                ),
              )
            : const Icon(Icons.label_outline_rounded, size: 16),
        label: Text(
          isFiltered ? toFinancialUpper(selectedCat.name) : 'Categoria',
          style: TextStyle(
            fontSize: 12,
            fontWeight: isFiltered ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        onSelected: (_) => _showPicker(context),
      ),
    );
  }
}
