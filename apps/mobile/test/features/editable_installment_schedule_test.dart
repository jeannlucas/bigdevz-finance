import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:bigdevz_finance/features/categories/categories_repository.dart';
import 'package:bigdevz_finance/features/payables/payable_creations.dart';
import 'package:bigdevz_finance/features/payables/payable_form_screen.dart';
import 'package:bigdevz_finance/features/payables/payables_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';
import '../support/fake_payables_api.dart';
import 'receipt_attempts_test.dart' show FlakyStorage;

const pf = Space(id: 1, kind: 'PF', name: 'Pessoal');

void main() {
  late FakePayablesApi fake;
  late FlakyStorage storage;

  setUp(() {
    fake = FakePayablesApi();
    storage = FlakyStorage();
  });

  Future<void> pumpForm(
    WidgetTester tester, {
    Size size = const Size(1280, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final client = ApiClient(
      baseUrl: 'http://api.test/api',
      client: fake.client,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider.value(value: PayablesRepository(client)),
          Provider.value(value: CategoriesRepository(client)),
          Provider(
            create: (context) => PayableCreations(
              repository: context.read<PayablesRepository>(),
              storage: storage,
            ),
          ),
          ChangeNotifierProvider(
            create: (_) =>
                SessionController(
                    api: client,
                    auth: AuthRepository(client),
                    storage: MemorySessionStorage(),
                  )
                  ..user = const AppUser(
                    id: 1,
                    name: 'Jeann',
                    email: 'jeann@example.com',
                  ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PayableFormScreen(space: pf)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'PEND-007 / AC-UI-011: Permite editar vencimento e valor das parcelas na prévia e salva carnê customizado',
    (tester) async {
      await pumpForm(tester);

      // 1. Alterna para modo Parcelada
      await tester.tap(find.text('Parcelada'));
      await tester.pumpAndSettle();

      // 2. Preenche descrição, parcelas e valor
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Descrição *'),
        'Carnê IPTU Reajustável',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Número de parcelas *'),
        '3',
      );
      // Alterna modo de valor para Valor total
      await tester.tap(find.text('Valor total'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Valor total *'),
        '409,34',
      );
      await tester.pumpAndSettle();

      final suggestion = find.widgetWithText(
        SwitchListTile,
        'Sugerir próximo dia útil bancário',
      );
      await tester.ensureVisible(suggestion);
      expect(tester.widget<SwitchListTile>(suggestion).value, isFalse);
      await tester.tap(suggestion);
      await tester.pumpAndSettle();

      // 3. Clica em "Ver cronograma"
      await tester.tap(find.text('Ver cronograma'));
      await tester.pumpAndSettle();

      final preview = fake.requests.lastWhere(
        (request) => request.url.path.endsWith('/payables/preview'),
      );
      expect(preview.body, contains('"suggest_next_bank_day":true'));

      // Verifica que as 3 parcelas foram geradas
      expect(find.byKey(const ValueKey('schedule-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('schedule-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('schedule-3')), findsOneWidget);

      // 4. Edita o valor de cada parcela:
      // Parcela 1: 135,17
      // Parcela 2: 136,44
      // Parcela 3: 137,73
      await tester.enterText(
        find.byKey(const ValueKey('schedule-amount-1')),
        '135,17',
      );
      await tester.enterText(
        find.byKey(const ValueKey('schedule-amount-2')),
        '136,44',
      );
      await tester.enterText(
        find.byKey(const ValueKey('schedule-amount-3')),
        '137,73',
      );
      await tester.pumpAndSettle();

      // Total badge deve refletir a soma exata: R$ 409,34
      expect(
        find.byKey(const ValueKey('schedule-total-badge')),
        findsOneWidget,
      );
      expect(find.textContaining('409,34'), findsWidgets);

      final firstDate = find.byKey(const ValueKey('schedule-date-1'));
      await tester.ensureVisible(firstDate);
      await tester.tap(firstDate);
      await tester.pumpAndSettle();
      await tester.tap(find.text('11'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(suggestion);
      await tester.tap(suggestion);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver cronograma'));
      await tester.pumpAndSettle();
      final recalculated = fake.requests.lastWhere(
        (request) => request.url.path.endsWith('/payables/preview'),
      );
      expect(recalculated.body, isNot(contains('suggest_next_bank_day')));
      expect(
        find.descendant(
          of: firstDate,
          matching: find.textContaining('11/03/2026'),
        ),
        findsOneWidget,
      );

      // 5. Confirma o cadastro das parcelas
      final confirmBtn = find.widgetWithText(
        FilledButton,
        'Confirmar cadastro das parcelas',
      );
      expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNotNull);
      await tester.ensureVisible(confirmBtn);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // 6. Verifica requisição enviada à API com o array installments
      final createRequests = fake.writes
          .where((r) => r.url.path.endsWith('/payables'))
          .toList();
      expect(createRequests, isNotEmpty);

      // Inspeciona os payables criados no fake backend (excluindo a seed inicial #40)
      final createdList = fake.payables.values
          .where((p) => p.id != 40)
          .toList();
      expect(createdList.length, 3);
      expect(createdList[0].amountCents, 13517);
      expect(createdList[0].dueDate, '2026-03-11');
      expect(createdList[1].amountCents, 13644);
      expect(createdList[2].amountCents, 13773);
    },
  );
}
