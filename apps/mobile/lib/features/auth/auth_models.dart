class AppUser {
  const AppUser({required this.id, required this.name, required this.email});

  factory AppUser.fromJson(Map<String, dynamic> json) =>
      AppUser(id: json['id'] as int, name: json['name'] as String, email: json['email'] as String);

  final int id;
  final String name;
  final String email;
}

/// Espaço financeiro: PF (pessoal) ou PJ (empresa). Todo dado pertence a um.
class Space {
  const Space({required this.id, required this.kind, required this.name});

  factory Space.fromJson(Map<String, dynamic> json) =>
      Space(id: json['id'] as int, kind: json['kind'] as String, name: json['name'] as String);

  final int id;
  final String kind;
  final String name;

  bool get isPf => kind == 'PF';
  String get label => isPf ? 'Pessoal (PF)' : 'Empresa (PJ)';
}
