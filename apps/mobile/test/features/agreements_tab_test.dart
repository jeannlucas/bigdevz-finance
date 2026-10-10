import 'dart:convert';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/agreements/agreements_repository.dart';
import 'package:bigdevz_finance/features/agreements/agreements_tab.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';

const pf = Space(id: 1, kind: 'PF', name: 'Pessoal');

void main() {
  late List<http.Request> requests;
  late MemorySessionStorage storage;

  Map<String, Object?> agreementJson({
    int id = 1,
    String description = 'Serviço prestado',
    String total = '1200.00',
    String received = '400.00',
    String remaining = '800.00',
    int installmentCount = 3,
    int paidInstallments = 1,
    int overdueInstallments = 1,
    String? nextDueDate = '2026-03-10',
    List<Map<String, dynamic>> installments = const [],
  }) => {
    'id': id,
    'description': description,
    'total': total,
    'installment_count': installmentCount,
    'received': received,
    'remaining': remaining,
    'paid_installments': paidInstallments,
    'overdue_installments': overdueInstallments,
    'next_due_date': nextDueDate,
    'installments': installments,
  };

  Map<String, dynamic> installmentJson({
    int id = 10,
    int agreementId = 1,
    int number = 1,
    String dueDate = '2026-02-10',
    String amount = '400.00',
    String received = '0.00',
    String remaining = '400.00',
    String status = 'pending',
    bool overdue = true,
  }) => {
    'id': id,
    'agreement_id': agreementId,
    'number': number,
    'due_date': dueDate,
    'amount': amount,
    'received': received,
    'remaining': remaining,
    'status': status,
    'overdue': overdue,
  };

  Future<void> pumpTab(
    WidgetTester tester, {
    required List<Map<String, dynamic>> agreements,
    int? totalCount,
    String initialFilter = 'open',
    Future<http.Response> Function(http.Request)? overrideHandler,
  }) async {
    requests = [];
    storage = MemorySessionStorage();
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final client = MockClient((request) async {
      requests.add(request);
      if (overrideHandler != null) return overrideHandler(request);
      if (request.url.path == '/api/spaces/1/agreements') {
        final count = totalCount ?? agreements.length;
        return http.Response(
          jsonEncode({
            'data': agreements,
            'meta': {
              'status': request.url.queryParameters['status'] ?? 'open',
              'today': '2026-03-15',
              'total_count': count,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{"message": "Not found"}', 404);
    });

    final api = ApiClient(baseUrl: 'http://api.test/api', client: client);
    final session = SessionController(
      api: api,
      auth: AuthRepository(api),
      storage: storage,
    )..user = const AppUser(id: 1, name: 'Pessoa', email: 'p@example.com');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider.value(value: AgreementsRepository(api)),
          ChangeNotifierProvider.value(value: session),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AgreementsTab(space: pf, initialFilter: initialFilter),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'exibe título "Contas a receber", botão "Nova conta a receber" e filtros corretos',
    (tester) async {
      await pumpTab(tester, agreements: [], totalCount: 2);

      // Ações e títulos no cabeçalho
      expect(find.text('Contas a receber'), findsOneWidget);
      expect(find.text('Nova conta a receber'), findsOneWidget);

      // Chips de filtro (com scroll horizontal na barra de filtros)
      final scrollable = find.byType(Scrollable).first;
      expect(find.text('Em aberto'), findsOneWidget);
      expect(find.text('Vencidas'), findsOneWidget);
      expect(find.text('Hoje'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Próximos 30 dias'),
        100,
        scrollable: scrollable,
      );
      expect(find.text('Próximos 30 dias'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Recebidas'),
        100,
        scrollable: scrollable,
      );
      expect(find.text('Recebidas'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Todas'),
        100,
        scrollable: scrollable,
      );
      expect(find.text('Todas'), findsOneWidget);

      // Estado vazio com totalCount > 0: orienta outro filtro e oferece "Ver todas"
      expect(find.text('Nenhuma conta a receber neste filtro'), findsOneWidget);
      expect(
        find.text('Tente outro filtro ou consulte Todas.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, 'Ver todas'), findsOneWidget);

      // Por padrão consulta status=open
      expect(requests.first.url.queryParameters['status'], 'open');
    },
  );

  testWidgets(
    'espaço sem nenhum cadastro mostra orientação inicial sem botão Ver todas',
    (tester) async {
      await pumpTab(tester, agreements: [], totalCount: 0);

      expect(find.text('Você ainda não tem contas a receber'), findsOneWidget);
      expect(
        find.textContaining(
          'Cadastre sua primeira venda parcelada ou valor a receber',
        ),
        findsOneWidget,
      );
      expect(find.text('Ver todas'), findsNothing);
      // Somente o botão oficial do cabeçalho
      expect(find.text('Nova conta a receber'), findsOneWidget);
    },
  );

  testWidgets('"Ver todas" seleciona o filtro Todas e recarrega a lista', (
    tester,
  ) async {
    await pumpTab(tester, agreements: [], totalCount: 2);

    expect(find.text('Nenhuma conta a receber neste filtro'), findsOneWidget);
    final verTodasBtn = find.widgetWithText(OutlinedButton, 'Ver todas');
    expect(verTodasBtn, findsOneWidget);

    await tester.tap(verTodasBtn);
    await tester.pumpAndSettle();

    expect(requests.last.url.queryParameters['status'], 'all');
  });

  testWidgets('erro de rede ou API exibe estado de erro e não estado vazio', (
    tester,
  ) async {
    await pumpTab(
      tester,
      agreements: [],
      overrideHandler: (req) async =>
          http.Response('{"message": "Erro no servidor"}', 500),
    );

    // Exibe tela de erro com opção de tentar novamente
    expect(find.text('Algo deu errado'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(find.text('Nenhuma conta a receber neste filtro'), findsNothing);
    expect(find.text('Você ainda não tem contas a receber'), findsNothing);
  });

  testWidgets('troca de filtro envia query param correto e atualiza listagem', (
    tester,
  ) async {
    await pumpTab(
      tester,
      agreements: [
        agreementJson(
          id: 1,
          description: 'Consultoria Financeira',
          installments: [
            installmentJson(
              id: 10,
              number: 1,
              overdue: true,
              remaining: '400.00',
            ),
            installmentJson(
              id: 11,
              number: 2,
              overdue: false,
              remaining: '400.00',
            ),
          ],
        ),
      ],
    );

    expect(find.text('Consultoria Financeira'), findsOneWidget);
    expect(find.text('1 conta a receber'), findsOneWidget);

    // Toca no filtro "Vencidas"
    await tester.tap(find.text('Vencidas'));
    await tester.pumpAndSettle();

    expect(requests.last.url.queryParameters['status'], 'overdue');
    // Identifica naturalmente a parcela vencida
    expect(find.text('Parcela 1 vencida'), findsOneWidget);
    expect(find.text('Vencido no filtro'), findsOneWidget);
    expect(find.text('Restante total'), findsOneWidget);
  });
}
