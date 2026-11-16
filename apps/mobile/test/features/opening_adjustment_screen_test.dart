import 'dart:convert';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/accounts/account.dart';
import 'package:bigdevz_finance/features/accounts/accounts_repository.dart';
import 'package:bigdevz_finance/features/accounts/opening_adjustment_screen.dart';
import 'package:bigdevz_finance/features/accounts/opening_adjustments.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';

void main() {
  const space = Space(id: 1, kind: 'PF', name: 'Pessoal');

  const account = Account(
    id: 10,
    name: 'Sicredi',
    openingBalance: Money(0),
    openingBalanceDate: '2026-11-01',
    balance: Money(0),
    archivedAt: null,
    firstMovementDate: null,
  );

  Widget buildTestWidget({required ApiClient api, required Widget child}) {
    final storage = MemorySessionStorage();
    final session =
        SessionController(api: api, auth: AuthRepository(api), storage: storage)
          ..user = const AppUser(
            id: 1,
            name: 'Jeann Lucas',
            email: 'jeann@example.com',
          );

    return MultiProvider(
      providers: [
        Provider.value(value: api),
        Provider(create: (_) => AccountsRepository(api)),
        Provider(
          create: (context) => OpeningAdjustments(
            repository: context.read<AccountsRepository>(),
            storage: storage,
          ),
        ),
        ChangeNotifierProvider.value(value: session),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  testWidgets(
    'OpeningAdjustmentScreen permite alternar para saldo negativo e submeter ajuste',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final requests = <http.Request>[];
      final client = MockClient((request) async {
        if (request.url.path.contains('/opening-adjustment')) {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'data': {
                'account': {
                  'id': 10,
                  'name': 'Sicredi',
                  'opening_balance': '-995.98',
                  'opening_balance_date': '2026-11-01',
                  'balance': '-995.98',
                  'archived_at': null,
                  'first_movement_date': null,
                  'opening_adjustments': [],
                },
                'adjustment': {
                  'id': 1,
                  'previous_opening_balance': '0.00',
                  'previous_opening_balance_date': '2026-11-01',
                  'new_opening_balance': '-995.98',
                  'new_opening_balance_date': '2026-11-01',
                  'reason': 'Cheque especial utilizado antes da abertura',
                  'adjusted_at': '2026-11-15T18:00:00Z',
                },
                'replayed': false,
              },
            }),
            200,
          );
        }
        return http.Response('{"message": "Not found"}', 404);
      });

      final api = ApiClient(baseUrl: 'http://api.test/api', client: client);

      await tester.pumpWidget(
        buildTestWidget(
          api: api,
          child: const OpeningAdjustmentScreen(space: space, account: account),
        ),
      );
      await tester.pumpAndSettle();

      // Verifica elementos iniciais
      expect(find.text('Saldo positivo (+)'), findsOneWidget);
      expect(find.text('Saldo negativo / devedor (-)'), findsOneWidget);

      // Alterna para saldo negativo
      await tester.tap(find.text('Saldo negativo / devedor (-)'));
      await tester.pumpAndSettle();

      // Digita o valor de 995,98
      final balanceInput = find.widgetWithText(
        TextFormField,
        'Saldo inicial correto',
      );
      await tester.enterText(balanceInput, '99598');
      await tester.pumpAndSettle();

      // Digita o motivo
      final reasonInput = find.widgetWithText(TextFormField, 'Motivo');
      await tester.enterText(
        reasonInput,
        'Cheque especial utilizado antes da abertura',
      );
      await tester.pumpAndSettle();

      // Toca em revisar
      await tester.tap(find.text('Revisar correção da abertura'));
      await tester.pumpAndSettle();

      // Na tela de revisão deve mostrar a transição para -R$ 995,98
      expect(find.textContaining('-R\$ 995,98'), findsWidgets);

      // Confirma a correção
      await tester.tap(find.text('Confirmar correção'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // Verifica se a API recebeu a requisição com o valor negativo exato
      expect(requests, hasLength(1));
      final payload = jsonDecode(requests.first.body) as Map<String, dynamic>;
      expect(payload['opening_balance'], '-995.98');
      expect(payload['opening_balance_date'], '2026-11-01');
      expect(payload['reason'], 'Cheque especial utilizado antes da abertura');
    },
  );
}
