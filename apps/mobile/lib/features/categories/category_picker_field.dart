import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'categories_repository.dart';
import 'category.dart';

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
      final repo = context.read<CategoriesRepository>();
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
    String selectedIcon = 'category';
    String selectedColor = widget.type == 'income' ? '#0F8A5F' : '#E57373';

    final availableIcons = [
      'work',
      'trending_up',
      'monetization_on',
      'home',
      'restaurant',
      'directions_car',
      'health_and_safety',
      'school',
      'local_activity',
      'shopping_cart',
      'business_center',
      'group',
      'local_shipping',
      'account_balance',
      'cloud',
      'campaign',
      'fitness_center',
      'local_gas_station',
      'category',
    ];

    final availableColors = [
      '#0F8A5F',
      '#1E5BB8',
      '#7C3AED',
      '#D97706',
      '#E57373',
      '#EC4899',
      '#06B6D4',
      '#10B981',
      '#6366F1',
      '#64748B',
    ];

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
                      decoration: const InputDecoration(
                        labelText: 'Nome da Categoria',
                        hintText: 'Ex: Consultoria, Combustível...',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Ícone',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final iconKey in availableIcons)
                          InkWell(
                            onTap: () =>
                                setDialogState(() => selectedIcon = iconKey),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: selectedIcon == iconKey
                                    ? Theme.of(ctx).colorScheme.primaryContainer
                                    : null,
                                border: Border.all(
                                  color: selectedIcon == iconKey
                                      ? Theme.of(ctx).colorScheme.primary
                                      : Colors.grey.withValues(alpha: 0.3),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Category.iconToMaterial(iconKey),
                                size: 20,
                                color: selectedIcon == iconKey
                                    ? Theme.of(ctx).colorScheme.primary
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Cor',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final colHex in availableColors)
                          InkWell(
                            onTap: () =>
                                setDialogState(() => selectedColor = colHex),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: _parseColor(colHex),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selectedColor == colHex
                                      ? Colors.white
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                                boxShadow: selectedColor == colHex
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.4,
                                          ),
                                          blurRadius: 4,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          ),
                      ],
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

  static Color _parseColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return Colors.blue;
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
                      child: Text(cat.name, overflow: TextOverflow.ellipsis),
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
