class SpaceMember {
  const SpaceMember({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isOwner,
  });

  factory SpaceMember.fromJson(Map<String, dynamic> json) => SpaceMember(
    id: json['id'] as int,
    name: (json['name'] as String?) ?? '',
    email: (json['email'] as String?) ?? '',
    role: (json['role'] as String?) ?? 'operador',
    isOwner: (json['is_owner'] as bool?) ?? false,
  );

  final int id;
  final String name;
  final String email;
  final String role;
  final bool isOwner;

  bool get isAdmin => role == 'administrador';
  bool get isFinancial => role == 'financeiro';
  bool get isOperator => role == 'operador';
  bool get isAccountant => role == 'contador';

  String get roleLabel {
    switch (role) {
      case 'administrador':
        return 'Administrador';
      case 'financeiro':
        return 'Financeiro';
      case 'operador':
        return 'Operador';
      case 'contador':
        return 'Contador';
      default:
        return role;
    }
  }

  String get roleDescription {
    switch (role) {
      case 'administrador':
        return 'Acesso completo a todas as funções, configurações, fechamento de períodos e gestão de equipe.';
      case 'financeiro':
        return 'Opera lançamentos diários, pagamentos, recebimentos, transferências e conciliação. Não altera saldos iniciais de contas nem gerencia membros.';
      case 'operador':
        return 'Realiza lançamentos e baixas rotineiras. Não pode cancelar lançamentos, estornar valores, exportar dados nem alterar saldos iniciais.';
      case 'contador':
        return 'Acesso somente para consulta e exportação de relatórios e extratos. Não possui permissão para movimentar dinheiro ou alterar cadastros.';
      default:
        return '';
    }
  }
}
