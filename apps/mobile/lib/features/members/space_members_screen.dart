import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../ui/app_tokens.dart';
import '../auth/session_controller.dart';
import 'space_member_models.dart';
import 'space_members_repository.dart';

class SpaceMembersScreen extends StatefulWidget {
  const SpaceMembersScreen({super.key, this.repository});

  final SpaceMembersRepository? repository;

  @override
  State<SpaceMembersScreen> createState() => _SpaceMembersScreenState();
}

class _SpaceMembersScreenState extends State<SpaceMembersScreen> {
  late final SpaceMembersRepository _repo;
  List<SpaceMember> _members = const [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _repo =
        widget.repository ??
        SpaceMembersRepository(api: context.read<ApiClient>());
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final session = context.read<SessionController?>();
    final space = session?.activeSpace;
    if (space == null) return;

    if (!space.isAdmin) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Acesso restrito: Apenas Administradores têm permissão para gerenciar a equipe e perfis deste espaço.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final members = await _repo.list(space: space);
      if (mounted) {
        setState(() {
          _members = members;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Não foi possível carregar a lista de membros. Tente novamente.';
        });
      }
    }
  }

  int get _adminCount => _members.where((m) => m.isAdmin).length;

  Future<void> _addOrEditMember({SpaceMember? existing}) async {
    final session = context.read<SessionController?>();
    final space = session?.activeSpace;
    if (space == null) return;

    final emailController = TextEditingController(text: existing?.email ?? '');
    String selectedRole = existing?.role ?? 'operador';
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(
                existing == null
                    ? 'Convidar / Adicionar Membro'
                    : 'Alterar Perfil de Acesso',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              content: SizedBox(
                width: 460,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // E-mail
                      if (existing == null) ...[
                        TextFormField(
                          controller: emailController,
                          decoration: InputDecoration(
                            labelText: 'E-mail do usuário',
                            hintText: 'exemplo@empresa.com',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppTokens.r8),
                            ),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Informe o e-mail do usuário.';
                            }
                            if (!val.contains('@') || !val.contains('.')) {
                              return 'Informe um e-mail válido.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ] else ...[
                        Text(
                          'Membro: ${existing.name}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          existing.email,
                          style: const TextStyle(
                            color: AppTokens.neutral,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Dropdown de Perfil
                      DropdownButtonFormField<String>(
                        initialValue: selectedRole,
                        decoration: InputDecoration(
                          labelText: 'Perfil de Acesso',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppTokens.r8),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'administrador',
                            child: Text('Administrador (Acesso Total)'),
                          ),
                          DropdownMenuItem(
                            value: 'financeiro',
                            child: Text('Financeiro (Operações e Conciliação)'),
                          ),
                          DropdownMenuItem(
                            value: 'operador',
                            child: Text('Operador (Lançamentos e Baixas)'),
                          ),
                          DropdownMenuItem(
                            value: 'contador',
                            child: Text(
                              'Contador (Apenas Consulta e Relatórios)',
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() => selectedRole = val);
                          }
                        },
                      ),
                      const SizedBox(height: 12),

                      // Explicação do perfil selecionado
                      Container(
                        padding: const EdgeInsets.all(AppTokens.p12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(AppTokens.r8),
                        ),
                        child: Text(
                          _explainRole(selectedRole),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTokens.neutral,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() ?? false) {
                      // Impedir rebaixar o único administrador
                      if (existing != null &&
                          existing.isAdmin &&
                          selectedRole != 'administrador' &&
                          _adminCount <= 1) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Não é possível alterar o perfil do único administrador. Defina outro administrador antes.',
                            ),
                            backgroundColor: AppTokens.expense,
                          ),
                        );
                        return;
                      }
                      Navigator.of(ctx).pop(true);
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

    if (confirmed == true && mounted) {
      try {
        await _repo.saveMember(
          space: space,
          email: existing?.email ?? emailController.text.trim(),
          role: selectedRole,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permissões do membro salvas com sucesso.'),
              backgroundColor: AppTokens.income,
            ),
          );
          await _loadMembers();
          // Atualiza sessão caso o usuário alterado seja o atual
          await session?.reloadSpaces();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao salvar permissões: ${e.toString()}'),
              backgroundColor: AppTokens.expense,
            ),
          );
        }
      }
    }
  }

  Future<void> _removeMember(SpaceMember member) async {
    final session = context.read<SessionController?>();
    final space = session?.activeSpace;
    if (space == null) return;

    // Se for o único administrador: bloqueia
    if (member.isAdmin && _adminCount <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não é possível remover o único administrador da organização. Defina outro administrador antes.',
          ),
          backgroundColor: AppTokens.expense,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.person_remove_rounded, color: AppTokens.expense),
            SizedBox(width: 8),
            Text('Remover Acesso'),
          ],
        ),
        content: Text(
          'Deseja realmente revogar o acesso de "${member.name}" (${member.email}) a este espaço empresarial?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.expense),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remover Acesso'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _repo.removeMember(space: space, memberId: member.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Acesso do membro revogado com sucesso.'),
              backgroundColor: AppTokens.income,
            ),
          );
          await _loadMembers();
          await session?.reloadSpaces();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao revogar acesso: ${e.toString()}'),
              backgroundColor: AppTokens.expense,
            ),
          );
        }
      }
    }
  }

  String _explainRole(String role) {
    switch (role) {
      case 'administrador':
        return 'Administrador: Controle total da organização, configurações, fechamento de períodos e gestão de equipe.';
      case 'financeiro':
        return 'Financeiro: Opera pagamentos, recebimentos, transferências e conciliação. Não altera saldos de abertura nem gerencia membros.';
      case 'operador':
        return 'Operador: Registra lançamentos e baixas rotineiras. Bloqueado para cancelamentos, estornos, exportação e saldo inicial.';
      case 'contador':
        return 'Contador: Acesso exclusivamente de consulta e exportação. Não pode movimentar dinheiro nem alterar cadastros.';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = context.watch<SessionController?>();
    final space = session?.activeSpace;

    if (space != null && !space.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Equipe e Perfis de Acesso')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.p24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_person_rounded,
                  size: 64,
                  color: AppTokens.warning,
                ),
                const SizedBox(height: 16),
                Text(
                  'Acesso Restrito ao Administrador',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Apenas administradores podem gerenciar a equipe e os níveis de permissão desta empresa.',
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
        title: const Text('Equipe e Perfis de Acesso'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Atualizar',
            onPressed: _loadMembers,
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
              ? _buildErrorView(theme)
              : ListView(
                  padding: const EdgeInsets.all(AppTokens.p16),
                  children: [
                    // Card Explicativo de Papéis
                    _buildRolesExplanationCard(theme),
                    const SizedBox(height: 16),

                    // Cabeçalho da Lista e Botão Adicionar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Membros do Espaço (${_members.length})',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () => _addOrEditMember(),
                          icon: const Icon(Icons.person_add_rounded, size: 18),
                          label: const Text('Adicionar Membro'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Lista de Membros
                    if (_members.isEmpty)
                      _buildEmptyView(theme)
                    else
                      ..._members.map(
                        (member) => _MemberCard(
                          member: member,
                          onEdit: () => _addOrEditMember(existing: member),
                          onRemove: () => _removeMember(member),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildRolesExplanationCard(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.r12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: const Padding(
        padding: EdgeInsets.all(AppTokens.p16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 20,
                  color: AppTokens.brandPrimary,
                ),
                SizedBox(width: 8),
                Text(
                  'Perfis e Alçadas de Acesso',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ],
            ),
            SizedBox(height: 10),
            Text(
              '• Administrador: Controle completo, fechamento contábil e gestão de membros.',
            ),
            SizedBox(height: 4),
            Text(
              '• Financeiro: Opera pagamentos, recebimentos e transferências diárias.',
            ),
            SizedBox(height: 4),
            Text(
              '• Operador: Cria lançamentos e baixas; não cancela, estorna nem exporta dados.',
            ),
            SizedBox(height: 4),
            Text(
              '• Contador: Apenas visualiza e exporta extratos e relatórios; zero movimentações.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.p32),
        child: Column(
          children: [
            const Icon(
              Icons.group_off_rounded,
              size: 48,
              color: AppTokens.neutral,
            ),
            const SizedBox(height: 8),
            Text(
              'Nenhum membro cadastrado',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
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
              size: 48,
              color: AppTokens.expense,
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Erro inesperado.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadMembers,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.onEdit,
    required this.onRemove,
  });

  final SpaceMember member;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.r12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.p14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: _badgeColor(member.role).withValues(alpha: 0.15),
              child: Text(
                member.name.isNotEmpty ? member.name[0].toUpperCase() : 'M',
                style: TextStyle(
                  color: _badgeColor(member.role),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Informações
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          member.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Badge do perfil
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _badgeColor(member.role)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppTokens.r8),
                        ),
                        child: Text(
                          member.roleLabel,
                          style: TextStyle(
                            color: _badgeColor(member.role),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (member.isOwner) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(AppTokens.r8),
                          ),
                          child: const Text(
                            'Proprietário',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    member.email,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTokens.neutral,
                    ),
                  ),
                ],
              ),
            ),

            // Ações
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'Alterar perfil',
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(
                Icons.person_remove_outlined,
                size: 20,
                color: AppTokens.expense,
              ),
              tooltip: 'Remover acesso',
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }

  Color _badgeColor(String role) {
    switch (role) {
      case 'administrador':
        return AppTokens.brandPrimary;
      case 'financeiro':
        return const Color(0xFF0284C7);
      case 'operador':
        return AppTokens.income;
      case 'contador':
        return const Color(0xFF7C3AED);
      default:
        return AppTokens.neutral;
    }
  }
}
