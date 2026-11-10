import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/audit/audit_models.dart';
import 'package:bigdevz_finance/features/audit/audit_repository.dart';
import 'package:bigdevz_finance/features/audit/audit_screen.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';

class FakeAuditRepository extends AuditRepository {
  FakeAuditRepository({required super.api, required this.items});

  final List<AuditItem> items;

  @override
  Future<List<AuditItem>> list({
    required Space space,
    String? subject,
    int? subjectId,
    bool? criticalOnly,
    int limit = 100,
  }) async {
    if (criticalOnly == true) {
      return items.where((i) => i.isCritical).toList();
    }
    return items;
  }
}

void main() {
  final fakeItems = [
    AuditItem(
      id: 1,
      subject: 'payable',
      subjectId: 10,
      action: 'cancel',
      isCritical: true,
      userName: 'Gestor Carlos',
      userEmail: 'carlos@empresa.com',
      reason: 'Cancelado por duplicidade',
      before: const {'amount_cents': 15000, 'status': 'pending'},
      after: const {'amount_cents': 15000, 'status': 'cancelled'},
      diff: const {
        'status': {'before': 'pending', 'after': 'cancelled'},
      },
      createdAt: DateTime(2026, 11, 9, 14, 30),
    ),
    AuditItem(
      id: 2,
      subject: 'agreement',
      subjectId: 20,
      action: 'edit',
      isCritical: false,
      userName: 'Operador Lucas',
      userEmail: 'lucas@empresa.com',
      reason: 'Ajuste de descrição',
      before: const {'description': 'Desc antiga'},
      after: const {'description': 'Desc nova'},
      diff: const {
        'description': {'before': 'Desc antiga', 'after': 'Desc nova'},
      },
      createdAt: DateTime(2026, 11, 9, 15, 0),
    ),
  ];

  Widget buildTestWidget({
    required Space space,
    required List<AuditItem> items,
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
        home: AuditScreen(
          repository: FakeAuditRepository(api: apiClient, items: items),
        ),
      ),
    );
  }

  testWidgets('AuditScreen: blocks access for operator profile', (
    tester,
  ) async {
    const operatorSpace = Space(
      id: 1,
      kind: 'PJ',
      name: 'Empresa',
      role: 'operador',
    );

    await tester.pumpWidget(
      buildTestWidget(space: operatorSpace, items: fakeItems),
    );
    await tester.pumpAndSettle();

    expect(find.text('Acesso Restrito'), findsOneWidget);
    expect(
      find.text(
        'A visualização da trilha de auditoria é restrita ao perfil de Administrador e Financeiro.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'AuditScreen: allows access for administrator and renders timeline',
    (tester) async {
      const adminSpace = Space(
        id: 1,
        kind: 'PJ',
        name: 'Empresa',
        role: 'administrador',
      );

      await tester.pumpWidget(
        buildTestWidget(space: adminSpace, items: fakeItems),
      );
      await tester.pumpAndSettle();

      expect(find.text('Auditoria e Conformidade'), findsOneWidget);
      expect(find.text('Apenas Operações Críticas'), findsOneWidget);
      expect(find.text('Operação Crítica'), findsOneWidget);
      expect(find.text('Cancelamento de lançamento'), findsOneWidget);
      expect(find.text('Responsável: Gestor Carlos'), findsOneWidget);
      expect(find.text('Alteração de dados'), findsOneWidget);

      // Clicar no evento de cancelamento para abrir o modal de detalhes
      await tester.tap(find.text('Cancelamento de lançamento'));
      await tester.pumpAndSettle();

      expect(find.text('Tipo de Lançamento'), findsOneWidget);
      expect(find.text('Conta a pagar'), findsNWidgets(2));
      expect(find.text('Cancelado por duplicidade'), findsOneWidget);
      expect(find.text('Situação Contábil'), findsOneWidget);
      expect(find.text('Anterior: Em aberto'), findsOneWidget);
      expect(find.text('Novo: Cancelado'), findsOneWidget);
    },
  );

  testWidgets('AuditScreen: filters critical operations when chip is tapped', (
    tester,
  ) async {
    const financialSpace = Space(
      id: 1,
      kind: 'PJ',
      name: 'Empresa',
      role: 'financeiro',
    );

    await tester.pumpWidget(
      buildTestWidget(space: financialSpace, items: fakeItems),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cancelamento de lançamento'), findsOneWidget);
    expect(find.text('Alteração de dados'), findsOneWidget);

    // Ativa filtro de operações críticas
    await tester.tap(find.text('Apenas Operações Críticas'));
    await tester.pumpAndSettle();

    expect(find.text('Cancelamento de lançamento'), findsOneWidget);
    expect(find.text('Alteração de dados'), findsNothing);
  });
}
