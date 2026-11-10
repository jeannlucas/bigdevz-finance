import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../ui/app_tokens.dart';
import '../auth/session_controller.dart';
import 'audit_models.dart';
import 'audit_repository.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key, this.repository});

  final AuditRepository? repository;

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  late final AuditRepository _repo;
  List<AuditItem> _items = const [];
  bool _isLoading = true;
  String? _errorMessage;

  bool _criticalOnly = false;
  String? _selectedSubject;
  String _searchQuery = '';

  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _repo =
        widget.repository ?? AuditRepository(api: context.read<ApiClient>());
    _loadAudit();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAudit() async {
    final session = context.read<SessionController?>();
    final space = session?.activeSpace;
    if (space == null) return;

    // Acesso permitido para Administrador ou Financeiro
    if (!space.isAdmin && !space.isFinancial) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Acesso restrito: Apenas Administradores e Gestores Financeiros têm permissão para consultar a trilha de auditoria.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await _repo.list(
        space: space,
        subject: _selectedSubject,
        criticalOnly: _criticalOnly,
        limit: 150,
      );
      if (mounted) {
        setState(() {
          _items = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Não foi possível carregar os registros de auditoria. Tente novamente.';
        });
      }
    }
  }

  List<AuditItem> get _filteredItems {
    if (_searchQuery.trim().isEmpty) return _items;
    final query = _searchQuery.toLowerCase();
    return _items.where((item) {
      final author = (item.userName ?? '').toLowerCase();
      final reason = (item.reason ?? '').toLowerCase();
      final subject = item.humanSubject.toLowerCase();
      final action = item.humanAction.toLowerCase();
      return author.contains(query) ||
          reason.contains(query) ||
          subject.contains(query) ||
          action.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = context.watch<SessionController?>();
    final space = session?.activeSpace;

    if (space != null && !space.isAdmin && !space.isFinancial) {
      return Scaffold(
        appBar: AppBar(title: const Text('Auditoria e Conformidade')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.p24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 64,
                  color: AppTokens.warning,
                ),
                const SizedBox(height: 16),
                Text(
                  'Acesso Restrito',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'A visualização da trilha de auditoria é restrita ao perfil de Administrador e Financeiro.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTokens.neutral),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Auditoria e Conformidade'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Atualizar',
            onPressed: _loadAudit,
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            children: [
              // BARRA DE FILTROS E BUSCA
              _buildFilterBar(theme),

              // CONTEÚDO PRINCIPAL
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMessage != null
                    ? _buildErrorView(theme)
                    : _filteredItems.isEmpty
                    ? _buildEmptyView(theme)
                    : _buildTimelineList(theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(AppTokens.p16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Campo de busca
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar por autor, motivo ou lançamento...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppTokens.p12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTokens.r8),
              ),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
          const SizedBox(height: 12),

          // Chips de filtro
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Filtro Apenas Críticas
                FilterChip(
                  selected: _criticalOnly,
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: _criticalOnly ? Colors.white : AppTokens.expense,
                      ),
                      const SizedBox(width: 6),
                      const Text('Apenas Operações Críticas'),
                    ],
                  ),
                  selectedColor: AppTokens.expense,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: _criticalOnly ? Colors.white : null,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (val) {
                    setState(() => _criticalOnly = val);
                    _loadAudit();
                  },
                ),
                const SizedBox(width: 8),

                // Filtros de Assunto / Tipo
                _SubjectFilterChip(
                  label: 'Todos',
                  isSelected: _selectedSubject == null,
                  onSelected: () {
                    setState(() => _selectedSubject = null);
                    _loadAudit();
                  },
                ),
                const SizedBox(width: 6),
                _SubjectFilterChip(
                  label: 'Contas a Pagar',
                  isSelected: _selectedSubject == 'payable',
                  onSelected: () {
                    setState(() => _selectedSubject = 'payable');
                    _loadAudit();
                  },
                ),
                const SizedBox(width: 6),
                _SubjectFilterChip(
                  label: 'Contas a Receber',
                  isSelected: _selectedSubject == 'agreement',
                  onSelected: () {
                    setState(() => _selectedSubject = 'agreement');
                    _loadAudit();
                  },
                ),
                const SizedBox(width: 6),
                _SubjectFilterChip(
                  label: 'Período Contábil',
                  isSelected: _selectedSubject == 'period_closing',
                  onSelected: () {
                    setState(() => _selectedSubject = 'period_closing');
                    _loadAudit();
                  },
                ),
                const SizedBox(width: 6),
                _SubjectFilterChip(
                  label: 'Contas Bancárias',
                  isSelected: _selectedSubject == 'account',
                  onSelected: () {
                    setState(() => _selectedSubject = 'account');
                    _loadAudit();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineList(ThemeData theme) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.p16,
        vertical: AppTokens.p16,
      ),
      itemCount: _filteredItems.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = _filteredItems[index];
        return _AuditCard(item: item, onTap: () => _showAuditDetails(item));
      },
    );
  }

  Widget _buildEmptyView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.p24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.history_rounded,
              size: 56,
              color: AppTokens.neutral,
            ),
            const SizedBox(height: 12),
            Text(
              'Nenhum registro encontrado',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Nenhum evento corresponde aos filtros informados.',
              style: TextStyle(color: AppTokens.neutral),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.p24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: AppTokens.expense,
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Ocorreu um erro.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadAudit,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAuditDetails(AuditItem item) {
    showDialog<void>(
      context: context,
      builder: (context) => _AuditDetailDialog(item: item),
    );
  }
}

class _SubjectFilterChip extends StatelessWidget {
  const _SubjectFilterChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }
}

class _AuditCard extends StatelessWidget {
  const _AuditCard({required this.item, required this.onTap});

  final AuditItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.r12),
        side: BorderSide(
          color: item.isCritical
              ? AppTokens.expense.withValues(alpha: 0.4)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: item.isCritical ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.p16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Linha Superior: Badges e Data
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Badge Crítica
                  if (item.isCritical) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTokens.expense.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppTokens.r8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 13,
                            color: AppTokens.expense,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Operação Crítica',
                            style: TextStyle(
                              color: AppTokens.expense,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Badge de Assunto
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppTokens.r8),
                    ),
                    child: Text(
                      item.humanSubject,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Data e Hora
                  if (item.createdAt != null)
                    Text(
                      formatDateTimeBr(item.createdAt!),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTokens.neutral,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              // Título da Ação
              Text(
                item.humanAction,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: item.isCritical ? AppTokens.expense : null,
                ),
              ),
              const SizedBox(height: 6),

              // Responsável
              Row(
                children: [
                  const Icon(
                    Icons.person_outline_rounded,
                    size: 15,
                    color: AppTokens.neutral,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.userName != null
                        ? 'Responsável: ${item.userName}'
                        : 'Responsável: Sistema / Desconhecido',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),

              // Motivo se houver
              if (item.reason != null && item.reason!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppTokens.p8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(AppTokens.r8),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                  child: Text(
                    'Motivo: ${item.reason}',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AuditDetailDialog extends StatelessWidget {
  const _AuditDetailDialog({required this.item});

  final AuditItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            item.isCritical
                ? Icons.warning_amber_rounded
                : Icons.verified_user_outlined,
            color: item.isCritical ? AppTokens.expense : AppTokens.brandPrimary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.humanAction,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Categoria do lançamento
              _detailRow('Tipo de Lançamento', item.humanSubject),
              const Divider(height: 16),

              // Autor / Responsável
              _detailRow(
                'Responsável',
                item.userName != null
                    ? '${item.userName} (${item.userEmail ?? "sem e-mail"})'
                    : 'Sistema',
              ),
              const Divider(height: 16),

              // Data e Hora
              if (item.createdAt != null) ...[
                _detailRow('Data e Hora', formatDateTimeBr(item.createdAt!)),
                const Divider(height: 16),
              ],

              // Motivo
              if (item.reason != null && item.reason!.isNotEmpty) ...[
                _detailRow('Justificativa informada', item.reason!),
                const Divider(height: 16),
              ],

              // Modificações Realizadas
              const Text(
                'Alterações Registradas',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 8),

              if (item.diff.isNotEmpty)
                ...item.diff.entries.map((entry) {
                  final field = _translateFieldName(entry.key);
                  final beforeVal = _formatValue(
                    entry.key,
                    entry.value['before'],
                  );
                  final afterVal = _formatValue(
                    entry.key,
                    entry.value['after'],
                  );

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Container(
                      padding: const EdgeInsets.all(AppTokens.p12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(AppTokens.r8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            field,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Anterior: $beforeVal',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTokens.expense,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: 14,
                                color: AppTokens.neutral,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Novo: $afterVal',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTokens.income,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                })
              else
                const Text(
                  'Registro histórico consolidado sem divergências pendentes.',
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: AppTokens.neutral,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppTokens.neutral,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  static String _translateFieldName(String field) {
    switch (field) {
      case 'amount_cents':
      case 'total_cents':
        return 'Valor Financeiro';
      case 'status':
        return 'Situação Contábil';
      case 'description':
        return 'Descrição';
      case 'due_date':
        return 'Data de Vencimento';
      case 'closed_until':
        return 'Fechamento Contábil até';
      case 'cancelled_at':
        return 'Cancelado em';
      case 'reason':
        return 'Motivo';
      default:
        return 'Campo: $field';
    }
  }

  static String _formatValue(String key, dynamic value) {
    if (value == null) return 'Não informado';
    if (key == 'amount_cents' || key == 'total_cents') {
      final cents = int.tryParse('$value');
      if (cents != null) return Money(cents).brl;
    }
    if (key == 'status') {
      switch ('$value') {
        case 'pending':
          return 'Em aberto';
        case 'paid':
          return 'Pago';
        case 'received':
          return 'Recebido';
        case 'cancelled':
          return 'Cancelado';
        case 'reversed':
          return 'Estornado';
        default:
          return '$value';
      }
    }
    return '$value';
  }
}
