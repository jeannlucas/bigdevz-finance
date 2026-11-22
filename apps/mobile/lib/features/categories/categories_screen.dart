import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/text_formatters.dart';
import '../../ui/app_tokens.dart';
import '../auth/auth_models.dart';
import 'categories_repository.dart';
import 'category.dart';
import 'category_badge.dart';
import 'category_icon_color_picker.dart';
import 'category_style_catalog.dart';

/// Abre o modal/tela de Gerenciamento de Categorias.
Future<void> showCategoriesManagementModal(
  BuildContext context, {
  required Space space,
  VoidCallback? onUpdated,
}) async {
  final isDesktop = MediaQuery.sizeOf(context).width >= 640;

  if (isDesktop) {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Theme.of(dialogCtx).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.r20),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 620,
            maxHeight: MediaQuery.sizeOf(dialogCtx).height * 0.85,
          ),
          child: _CategoriesContent(space: space, onUpdated: onUpdated),
        ),
      ),
    );
  } else {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTokens.r24),
        ),
      ),
      builder: (sheetCtx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.9,
        ),
        child: _CategoriesContent(space: space, onUpdated: onUpdated),
      ),
    );
  }
}

class _CategoriesContent extends StatefulWidget {
  const _CategoriesContent({required this.space, this.onUpdated});

  final Space space;
  final VoidCallback? onUpdated;

  @override
  State<_CategoriesContent> createState() => _CategoriesContentState();
}

class _CategoriesContentState extends State<_CategoriesContent> {
  String _selectedType = 'expense'; // 'expense' ou 'income'
  List<Category> _categories = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = context.read<CategoriesRepository>();
      final list = await repo.list(widget.space.id, type: _selectedType);
      if (mounted) {
        setState(() {
          _categories = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Erro ao carregar categorias.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _showCreateOrEditDialog({
    Category? existing,
    int? preselectedParentId,
  }) async {
    final nameCtrl = TextEditingController(
      text: toFinancialUpper(existing?.name),
    );
    String selectedIcon =
        existing?.icon ?? (_selectedType == 'income' ? 'trending_up' : 'home');
    String selectedColor =
        existing?.color ??
        CategoryStyleCatalog.getDefaultColorHex(
          selectedIcon,
          type: _selectedType,
        );
    int? selectedParentId = existing?.parentId ?? preselectedParentId;
    bool saving = false;
    String? dialogError;

    final hasChildren =
        existing != null && _categories.any((c) => c.parentId == existing.id);
    final eligibleParents = _categories
        .where(
          (c) =>
              !c.isSubcategory &&
              c.type == _selectedType &&
              (existing == null || c.id != existing.id),
        )
        .toList();

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.r20),
          ),
          title: Text(existing == null ? 'Nova Categoria' : 'Editar Categoria'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (dialogError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(AppTokens.r8),
                    ),
                    child: Text(
                      dialogError!,
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.onErrorContainer,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  inputFormatters: const [UpperCaseTextFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Nome da Categoria *',
                    hintText: 'Ex: Moradia, Energia, Marketing...',
                  ),
                ),
                if (!hasChildren) ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int?>(
                    initialValue: selectedParentId,
                    decoration: const InputDecoration(
                      labelText: 'Categoria Principal (opcional)',
                      hintText: 'Nenhuma (categoria principal)',
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Nenhuma (categoria principal)'),
                      ),
                      for (final parent in eligibleParents)
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
                ],
                const SizedBox(height: 16),
                CategoryIconColorPicker(
                  selectedIcon: selectedIcon,
                  selectedColor: selectedColor,
                  type: _selectedType,
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
              onPressed: saving ? null : () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        setDialogState(() => dialogError = 'Informe o nome.');
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        dialogError = null;
                      });

                      try {
                        final repo = context.read<CategoriesRepository>();
                        if (existing == null) {
                          await repo.create(
                            widget.space.id,
                            name: name,
                            type: _selectedType,
                            icon: selectedIcon,
                            color: selectedColor,
                            parentId: selectedParentId,
                          );
                        } else {
                          await repo.update(
                            widget.space.id,
                            existing.id,
                            name: name,
                            icon: selectedIcon,
                            color: selectedColor,
                            parentId: selectedParentId,
                          );
                        }
                        if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                        widget.onUpdated?.call();
                        _load();
                      } catch (e) {
                        setDialogState(() {
                          saving = false;
                          dialogError = e is ApiException
                              ? e.message
                              : 'Falha ao salvar.';
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteCategory(Category category) async {
    final repo = context.read<CategoriesRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Categoria?'),
        content: Text(
          'Deseja excluir a categoria "${toFinancialUpper(category.name)}"?\n\n'
          'As movimentações e contas a pagar vinculadas a ela não serão excluídas, '
          'apenas ficarão sem categoria.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await repo.delete(widget.space.id, category.id);
      widget.onUpdated?.call();
      _load();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Categoria "${toFinancialUpper(category.name)}" excluída.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException ? e.message : 'Falha ao excluir categoria.',
            ),
            backgroundColor: errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cabeçalho
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.p20,
            AppTokens.p16,
            AppTokens.p12,
            AppTokens.p12,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.r12),
                ),
                child: Icon(
                  Icons.category_rounded,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Categorias Financeiras',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Gerencie as categorias de receitas e despesas',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Fechar',
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // Barra de Ações: SegmentedButton Despesas/Receitas + Botão Nova Categoria
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.p20,
            AppTokens.p12,
            AppTokens.p20,
            AppTokens.p8,
          ),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'expense',
                      label: Text('Despesas'),
                      icon: Icon(Icons.arrow_upward_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: 'income',
                      label: Text('Receitas'),
                      icon: Icon(Icons.arrow_downward_rounded, size: 16),
                    ),
                  ],
                  selected: {_selectedType},
                  onSelectionChanged: (set) {
                    setState(() => _selectedType = set.first);
                    _load();
                  },
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _showCreateOrEditDialog(),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text(
                  'Nova',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),

        // Lista de Categorias
        Flexible(
          child: _loading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                )
              : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, style: theme.textTheme.bodyMedium),
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                          onPressed: _load,
                          child: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                )
              : _categories.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Nenhuma categoria encontrada.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : Builder(
                  builder: (context) {
                    final parents = _categories
                        .where((c) => !c.isSubcategory)
                        .toList();
                    final childrenByParent = <int, List<Category>>{};
                    for (final cat in _categories.where(
                      (c) => c.isSubcategory,
                    )) {
                      childrenByParent
                          .putIfAbsent(cat.parentId!, () => [])
                          .add(cat);
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(AppTokens.p20),
                      itemCount: parents.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final parent = parents[index];
                        final children =
                            childrenByParent[parent.id] ?? const [];

                        return Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(AppTokens.r12),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Linha da Categoria Principal
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    CategoryBadge(category: parent),
                                    const Spacer(),
                                    // Botão para adicionar subcategoria rapidamente
                                    TextButton.icon(
                                      onPressed: () => _showCreateOrEditDialog(
                                        preselectedParentId: parent.id,
                                      ),
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                      ),
                                      icon: const Icon(Icons.add, size: 14),
                                      label: const Text(
                                        'Subcategoria',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                    ),
                                    if (parent.isDefault)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: theme
                                              .colorScheme
                                              .surfaceContainerHigh,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.lock_outline_rounded,
                                              size: 12,
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Padrão',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else ...[
                                      IconButton(
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 18,
                                        ),
                                        tooltip: 'Editar categoria',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () =>
                                            _showCreateOrEditDialog(
                                              existing: parent,
                                            ),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          Icons.delete_outline_rounded,
                                          size: 18,
                                          color: theme.colorScheme.error,
                                        ),
                                        tooltip: 'Excluir categoria',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () =>
                                            _deleteCategory(parent),
                                      ),
                                    ],
                                  ],
                                ),
                              ),

                              // Subcategorias filhas indentadas
                              if (children.isNotEmpty) ...[
                                const Divider(
                                  height: 1,
                                  indent: 14,
                                  endIndent: 14,
                                ),
                                for (final child in children)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      28,
                                      6,
                                      14,
                                      6,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons
                                              .subdirectory_arrow_right_rounded,
                                          size: 16,
                                          color: theme.colorScheme.outline,
                                        ),
                                        const SizedBox(width: 6),
                                        CategoryBadge(
                                          category: child,
                                          compact: true,
                                        ),
                                        const Spacer(),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            size: 16,
                                          ),
                                          tooltip: 'Editar subcategoria',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () =>
                                              _showCreateOrEditDialog(
                                                existing: child,
                                              ),
                                        ),
                                        IconButton(
                                          icon: Icon(
                                            Icons.delete_outline_rounded,
                                            size: 16,
                                            color: theme.colorScheme.error,
                                          ),
                                          tooltip: 'Excluir subcategoria',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () =>
                                              _deleteCategory(child),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
