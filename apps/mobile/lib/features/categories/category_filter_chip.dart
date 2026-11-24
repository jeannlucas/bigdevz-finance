import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/text_formatters.dart';
import '../../ui/app_tokens.dart';
import 'categories_repository.dart';
import 'category.dart';
import 'category_picker_field.dart';

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
    final desktop = MediaQuery.sizeOf(context).width >= 840;
    final categories = CategoryPickerField.organizeHierarchy(_categories);
    var query = '';

    Widget content(BuildContext pickerContext) => StatefulBuilder(
      builder: (ctx, update) {
        final theme = Theme.of(ctx);
        final matches = categories
            .where(
              (category) => category.fullName.toLowerCase().contains(query),
            )
            .toList();
        void select(int? id) {
          Navigator.of(pickerContext).pop();
          if (mounted) widget.onChanged(id);
        }

        return Padding(
          padding: const EdgeInsets.all(AppTokens.p16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Filtrar por Categoria', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Buscar categoria',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (text) =>
                    update(() => query = text.trim().toLowerCase()),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      title: const Text('Todas as categorias'),
                      selected: widget.selectedCategoryId == null,
                      onTap: () => select(null),
                    ),
                    for (final cat in matches)
                      ListTile(
                        contentPadding: EdgeInsets.only(
                          left: cat.isSubcategory ? 32 : 16,
                          right: 16,
                        ),
                        leading: Icon(cat.iconData, color: cat.colorValue),
                        title: Text(toFinancialUpper(cat.name)),
                        subtitle: cat.isSubcategory ? Text(cat.fullName) : null,
                        selected: widget.selectedCategoryId == cat.id,
                        onTap: () => select(cat.id),
                      ),
                    if (matches.isEmpty && query.isNotEmpty)
                      const ListTile(
                        title: Text('Nenhuma categoria corresponde à busca.'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    if (desktop) {
      showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
            child: content(ctx),
          ),
        ),
      );
    } else {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: FractionallySizedBox(heightFactor: 0.75, child: content(ctx)),
        ),
      );
    }
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
