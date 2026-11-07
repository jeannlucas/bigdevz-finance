import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/profile_edit_dialog.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:bigdevz_finance/features/home/notifications_modal.dart';
import 'package:bigdevz_finance/features/summary/summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';

void main() {
  group('Perfil e Edição de Nome', () {
    late FakeBackend backend;
    late ApiClient api;
    late AuthRepository auth;
    late MemorySessionStorage storage;
    late SessionController session;

    setUp(() async {
      backend = FakeBackend();
      api = ApiClient(baseUrl: 'http://api.test/api', client: backend.client);
      api.token = backend.validToken;
      auth = AuthRepository(api);
      storage = MemorySessionStorage();
      session = SessionController(api: api, auth: auth, storage: storage);
      session.user = const AppUser(
        id: 1,
        name: 'Jeann Lucas',
        email: 'jeann@example.com',
      );
    });

    test('AuthRepository.updateProfile atualiza nome na API', () async {
      final updated = await auth.updateProfile('Jeann Lucas Dev');
      expect(updated.name, 'Jeann Lucas Dev');
      expect(backend.requests.last.method, 'PATCH');
      expect(backend.requests.last.url.path, '/api/me');
    });

    test(
      'SessionController.updateProfile notifica ouvintes e altera user',
      () async {
        var notified = false;
        session.addListener(() => notified = true);

        await session.updateProfile(name: 'Jeann Master');
        expect(notified, isTrue);
        expect(session.user?.name, 'Jeann Master');
      },
    );

    testWidgets(
      'ProfileEditDialog exibe nome/email e salva alteração com sucesso',
      (tester) async {
        await tester.pumpWidget(
          ChangeNotifierProvider<SessionController>.value(
            value: session,
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => showProfileEditDialog(context),
                    child: const Text('Abrir Perfil'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir Perfil'));
        await tester.pumpAndSettle();

        expect(find.text('Editar perfil'), findsOneWidget);
        expect(find.text('jeann@example.com'), findsOneWidget);
        expect(
          find.widgetWithText(TextFormField, 'Jeann Lucas'),
          findsOneWidget,
        );

        // Limpar o nome e tentar salvar (deve validar campo obrigatório)
        await tester.enterText(find.byType(TextFormField), '');
        await tester.tap(find.text('Salvar'));
        await tester.pumpAndSettle();
        expect(find.text('Informe o seu nome.'), findsOneWidget);

        // Preencher novo nome e salvar
        await tester.enterText(find.byType(TextFormField), 'Jeann Alterado');
        await tester.tap(find.text('Salvar'));
        await tester.pumpAndSettle();

        expect(session.user?.name, 'Jeann Alterado');
        expect(find.text('Editar perfil'), findsNothing); // Modal fechado
      },
    );
  });

  group('Modal de Notificações', () {
    testWidgets(
      'exibe contas a pagar e receber vencidas com atalhos de navegação',
      (tester) async {
        const summary = SpaceSummary(
          balance: Money(100000),
          receivableRemaining: Money(50000),
          receivedTotal: Money(0),
          accountsCount: 1,
          agreementsCount: 1,
          overdueInstallments: 2,
          payables: PayablesSummary(
            openTotal: Money(20000),
            overdueTotal: Money(15000),
            overdueCount: 3,
            dueNext30DaysTotal: Money(5000),
            paidTotal: Money(0),
            awaitingAmountCount: 1,
          ),
        );

        int? navigatedTab;
        String? navigatedFilter;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showNotificationsModal(
                    context,
                    summary: summary,
                    onNavigate: (tab, {filter}) {
                      navigatedTab = tab;
                      navigatedFilter = filter;
                    },
                  ),
                  child: const Text('Abrir Notificações'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir Notificações'));
        await tester.pumpAndSettle();

        expect(find.text('Notificações e Vencimentos'), findsOneWidget);
        expect(find.text('Contas a pagar vencidas'), findsOneWidget);
        expect(
          find.text('3 conta(s) em atraso somando R\$ 150,00'),
          findsOneWidget,
        );
        expect(find.text('Contas a receber vencidas'), findsOneWidget);
        expect(
          find.text('2 parcela(s) em atraso aguardando recebimento'),
          findsOneWidget,
        );
        expect(find.text('Faturas pendentes'), findsOneWidget);

        // Clicar em "Ver contas a pagar"
        await tester.tap(find.text('Ver contas a pagar'));
        await tester.pumpAndSettle();

        expect(navigatedTab, 3);
        expect(navigatedFilter, 'overdue');
      },
    );

    testWidgets('exibe "Tudo em dia!" quando não há pendências críticas', (
      tester,
    ) async {
      const cleanSummary = SpaceSummary(
        balance: Money(100000),
        receivableRemaining: Money(0),
        receivedTotal: Money(0),
        accountsCount: 1,
        agreementsCount: 1,
        overdueInstallments: 0,
        payables: PayablesSummary.empty,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showNotificationsModal(
                  context,
                  summary: cleanSummary,
                  onNavigate: (_, {filter}) {},
                ),
                child: const Text('Abrir Notificações'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Notificações'));
      await tester.pumpAndSettle();

      expect(find.text('Tudo em dia!'), findsOneWidget);
      expect(
        find.text(
          'Nenhum vencimento atrasado ou pendência crítica no momento.',
        ),
        findsOneWidget,
      );
    });
  });
}
