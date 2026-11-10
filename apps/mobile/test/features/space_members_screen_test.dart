import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:bigdevz_finance/features/members/space_member_models.dart';
import 'package:bigdevz_finance/features/members/space_members_repository.dart';
import 'package:bigdevz_finance/features/members/space_members_screen.dart';
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';

class FakeSpaceMembersRepository extends SpaceMembersRepository {
  FakeSpaceMembersRepository({required super.api, required this.members});

  final List<SpaceMember> members;

  @override
  Future<List<SpaceMember>> list({required Space space}) async => members;

  @override
  Future<SpaceMember> saveMember({
    required Space space,
    required String email,
    required String role,
  }) async {
    final member = SpaceMember(
      id: 99,
      name: 'Novo Membro',
      email: email,
      role: role,
      isOwner: false,
    );
    members.add(member);
    return member;
  }

  @override
  Future<void> removeMember({
    required Space space,
    required int memberId,
  }) async {
    members.removeWhere((m) => m.id == memberId);
  }
}

void main() {
  final fakeMembers = [
    const SpaceMember(
      id: 1,
      name: 'Admin Fundador',
      email: 'admin@bigdevz.com',
      role: 'administrador',
      isOwner: true,
    ),
    const SpaceMember(
      id: 2,
      name: 'Operador Silva',
      email: 'silva@bigdevz.com',
      role: 'operador',
      isOwner: false,
    ),
  ];

  Widget buildTestWidget({
    required Space space,
    required List<SpaceMember> members,
  }) {
    final apiClient = ApiClient(baseUrl: 'http://test');
    final session = SessionController(
      api: apiClient,
      auth: AuthRepository(apiClient),
      storage: MemorySessionStorage(),
    );
    session.activeSpace = space;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionController>.value(value: session),
        Provider<ApiClient>.value(value: apiClient),
      ],
      child: MaterialApp(
        home: SpaceMembersScreen(
          repository: FakeSpaceMembersRepository(
            api: apiClient,
            members: members,
          ),
        ),
      ),
    );
  }

  testWidgets(
    'SpaceMembersScreen: blocks operator from accessing members management',
    (tester) async {
      const operatorSpace = Space(
        id: 2,
        kind: 'PJ',
        name: 'Empresa Teste',
        role: 'operador',
      );

      await tester.pumpWidget(
        buildTestWidget(space: operatorSpace, members: List.from(fakeMembers)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Acesso Restrito ao Administrador'), findsOneWidget);
      expect(
        find.text(
          'Apenas administradores podem gerenciar a equipe e os níveis de permissão desta empresa.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'SpaceMembersScreen: renders members and roles for administrator',
    (tester) async {
      const adminSpace = Space(
        id: 2,
        kind: 'PJ',
        name: 'Empresa Teste',
        role: 'administrador',
      );

      await tester.pumpWidget(
        buildTestWidget(space: adminSpace, members: List.from(fakeMembers)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Equipe e Perfis de Acesso'), findsOneWidget);
      expect(find.text('Membros do Espaço (2)'), findsOneWidget);
      expect(find.text('Admin Fundador'), findsOneWidget);
      expect(find.text('Administrador'), findsOneWidget); // Badge do membro
      expect(find.text('Operador Silva'), findsOneWidget);
      expect(find.text('Proprietário'), findsOneWidget);

      // Explicação clara de alçadas está visível
      expect(find.text('Perfis e Alçadas de Acesso'), findsOneWidget);
      expect(
        find.textContaining('• Administrador: Controle completo'),
        findsOneWidget,
      );
      expect(
        find.text(
          '• Operador: Cria lançamentos e baixas; não cancela, estorna nem exporta dados.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('SpaceMembersScreen: prevents removing the only administrator', (
    tester,
  ) async {
    const adminSpace = Space(
      id: 2,
      kind: 'PJ',
      name: 'Empresa Teste',
      role: 'administrador',
    );

    final membersList = List<SpaceMember>.from(fakeMembers);

    await tester.pumpWidget(
      buildTestWidget(space: adminSpace, members: membersList),
    );
    await tester.pumpAndSettle();

    // Clica no botão de remover o Admin Fundador (ícone de lixeira/person_remove)
    final removeButtons = find.byIcon(Icons.person_remove_outlined);
    expect(removeButtons, findsNWidgets(2));

    // Primeiro botão é o do Admin
    await tester.tap(removeButtons.first);
    await tester.pumpAndSettle();

    // Deve exibir snackbar de impedimento
    expect(
      find.text(
        'Não é possível remover o único administrador da organização. Defina outro administrador antes.',
      ),
      findsOneWidget,
    );

    // Nenhum diálogo destrutivo deve ser aberto para o único admin
    expect(find.text('Deseja realmente revogar o acesso'), findsNothing);
  });
}
