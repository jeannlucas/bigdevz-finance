import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/text_formatters.dart';
import 'categories_repository.dart';
import 'category.dart';
import 'category_icon_color_picker.dart';
import 'category_style_catalog.dart';

/// Campo de seleção de categoria financeira com suporte a listagem remota e criação rápida.
class CategoryPickerField extends StatefulWidget {
  const CategoryPickerField({
    super.key,
    required this.spaceId,
    required this.type,
    required this.selectedCategoryId,
    required this.onChanged,
  });

  final int spaceId;
  final String type; // 'income' | 'expense'
  final int? selectedCategoryId;
  final ValueChanged<int?> onChanged;

  @override
  State<CategoryPickerField> createState() => _CategoryPickerFieldState();
}

class _CategoryPickerFieldState extends State<CategoryPickerField> {
  List<Category>? _categories;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      CategoriesRepository? repo;
      try {
        repo = Provider.of<CategoriesRepository?>(context, listen: false);
      } catch (_) {}
      if (repo == null) {
        if (mounted) {
          setState(() {
            _categories = [];
            _isLoading = false;
          });
        }
        return;
      }
      final list = await repo.list(widget.spaceId, type: widget.type);
      if (mounted) {
        setState(() {
          _categories = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showCreateCategoryDialog() async {
    final nameCtrl = TextEditingController();
    String selectedIcon = 'home';
    String selectedColor = CategoryStyleCatalog.getDefaultColorHex(
      'home',
      type: widget.type,
    );
    int? selectedParentId;

    final potentialParents = (_categories ?? [])
        .where((c) => !c.isSubcategory && c.type == widget.type)
        .toList();

    final created = await showDialog<Category>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              title: const Text('Nova Categoria'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      inputFormatters: const [UpperCaseTextFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Nome da Categoria',
                        hintText: 'Ex: Energia, Mercado...',
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int?>(
                      initialValue: selectedParentId,
                      decoration: const InputDecoration(
                        labelText: 'Categoria Pai (opcional)',
                        hintText: 'Nenhuma (categoria principal)',
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Nenhuma (categoria principal)'),
                        ),
                        for (final parent in potentialParents)
                          DropdownMenuItem<int?>(
                            value: parent.id,
                            child: Row(
                              children: [
                                Icon(
                                  parent.iconData,
                                  size: 16,
                                  color: parent.colorValue,
                                ),
                                const SizedBox(width: 8),
                                Text(toFinancialUpper(parent.name)),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (val) =>
                          setDialogState(() => selectedParentId = val),
                    ),
                    const SizedBox(height: 16),
                    CategoryIconColorPicker(
                      selectedIcon: selectedIcon,
                      selectedColor: selectedColor,
                      type: widget.type,
                      onIconChanged: (icon) =>
                          setDialogState(() => selectedIcon = icon),
                      onColorChanged: (col) =>
                          setDialogState(() => selectedColor = col),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    try {
                      final repo = context.read<CategoriesRepository>();
                      final cat = await repo.create(
                        widget.spaceId,
                        name: name,
                        type: widget.type,
                        icon: selectedIcon,
                        color: selectedColor,
                        parentId: selectedParentId,
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop(cat);
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Erro ao salvar: $e')),
                        );
                      }
                    }
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created != null) {
      await _loadCategories();
      widget.onChanged(created.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 52,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Não foi possível carregar as categorias.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 12,
          ),
        ),
      );
    }

    final categories = _categories ?? [];
    Category? selectedCategory;
    if (widget.selectedCategoryId != null) {
      for (final cat in categories) {
        if (cat.id == widget.selectedCategoryId) {
          selectedCategory = cat;
          break;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<int?>(
          initialValue: widget.selectedCategoryId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Categoria (opcional)',
            prefixIcon: selectedCategory != null
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: selectedCategory.colorValue.withValues(
                          alpha: 0.2,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        selectedCategory.iconData,
                        size: 14,
                        color: selectedCategory.colorValue,
                      ),
                    ),
                  )
                : const Icon(Icons.category_outlined, size: 20),
            suffixIcon: IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 20),
              tooltip: 'Criar nova categoria',
              onPressed: _showCreateCategoryDialog,
            ),
          ),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('Sem categoria'),
            ),
            for (final cat in categories)
              DropdownMenuItem<int?>(
                value: cat.id,
                child: Row(
                  children: [
                    if (cat.isSubcategory) const SizedBox(width: 12),
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: cat.colorValue,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(cat.iconData, size: 16, color: cat.colorValue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        toFinancialUpper(cat.fullName),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: widget.onChanged,
        ),
      ],
    );
  }
}
