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

  static String _normalizeSortKey(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c');
  }

  /// Organiza a lista plana de categorias em árvore determinística:
  /// 1. Categorias pai ordenadas alfabeticamente.
  /// 2. Imediatamente após cada pai, suas filhas ordenadas alfabeticamente.
  /// 3. Categorias órfãs agrupadas ordenadamente ao final.
  static List<Category> organizeHierarchy(List<Category> list) {
    if (list.isEmpty) return [];

    final parents = <Category>[];
    final childrenByParent = <int, List<Category>>{};
    final orphans = <Category>[];

    final parentIds = <int>{};
    for (final cat in list) {
      if (!cat.isSubcategory) {
        parentIds.add(cat.id);
      }
    }

    for (final cat in list) {
      if (!cat.isSubcategory) {
        parents.add(cat);
      } else if (cat.parentId != null && parentIds.contains(cat.parentId)) {
        childrenByParent.putIfAbsent(cat.parentId!, () => []).add(cat);
      } else {
        orphans.add(cat);
      }
    }

    parents.sort(
      (a, b) => _normalizeSortKey(a.name).compareTo(_normalizeSortKey(b.name)),
    );

    for (final children in childrenByParent.values) {
      children.sort(
        (a, b) =>
            _normalizeSortKey(a.name).compareTo(_normalizeSortKey(b.name)),
      );
    }

    orphans.sort(
      (a, b) => _normalizeSortKey(a.name).compareTo(_normalizeSortKey(b.name)),
    );

    final ordered = <Category>[];
    for (final parent in parents) {
      ordered.add(parent);
      final children = childrenByParent[parent.id];
      if (children != null) {
        ordered.addAll(children);
      }
    }
    ordered.addAll(orphans);

    return ordered;
  }

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

    final potentialParents =
        (_categories ?? [])
            .where((c) => !c.isSubcategory && c.type == widget.type)
            .toList()
          ..sort(
            (a, b) =>
                CategoryPickerField._normalizeSortKey(a.name)
                    .compareTo(CategoryPickerField._normalizeSortKey(b.name)),
          );

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

    final rawCategories = _categories ?? [];
    final categories = CategoryPickerField.organizeHierarchy(rawCategories);
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
          selectedItemBuilder: (BuildContext context) {
            return [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Sem categoria'),
              ),
              for (final cat in categories)
                Align(
                  alignment: Alignment.centerLeft,
                  child: cat.isSubcategory
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                toFinancialUpper(cat.name),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (cat.parentName != null &&
                                cat.parentName!.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(
                                '• ${toFinancialUpper(cat.parentName!)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.outline,
                                  fontWeight: FontWeight.normal,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        )
                      : Text(
                          toFinancialUpper(cat.name),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
            ];
          },
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
                    if (cat.isSubcategory) ...[
                      const SizedBox(width: 20),
                      Text(
                        '↳',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: cat.colorValue,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(cat.iconData, size: 15, color: cat.colorValue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          toFinancialUpper(cat.name),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ] else ...[
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
                          toFinancialUpper(cat.name),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
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
