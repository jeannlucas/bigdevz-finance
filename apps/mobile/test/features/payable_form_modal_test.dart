import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/accounts/accounts_repository.dart';
import 'package:bigdevz_finance/features/agreements/agreements_repository.dart';
import 'package:bigdevz_finance/features/agreements/receipt_attempts.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:bigdevz_finance/features/payables/payable_creations.dart';
import 'package:bigdevz_finance/features/payables/payable_form_screen.dart';
import 'package:bigdevz_finance/features/payables/payables_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';

const pf = Space(id: 1, kind: 'PF', name: 'Pessoal');

void main() {
  testWidgets('showPayableFormModal: abre Dialog em desktop com botão fechar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final backend = FakeBackend();
    final api = ApiClient(
      baseUrl: 'http://example.test',
      client: backend.client,
    );
    final storage = MemorySessionStorage();
    final auth = AuthRepository(api);
    final session = SessionController(api: api, auth: auth, storage: storage)
      ..user = const AppUser(id: 1, name: 'Demo', email: 'demo@example.com');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider.value(value: AgreementsRepository(api)),
          Provider.value(value: AccountsRepository(api)),
          Provider.value(value: PayablesRepository(api)),
          Provider(
            create: (context) => PayableCreations(
              repository: context.read<PayablesRepository>(),
              storage: storage,
            ),
          ),
          Provider(
            create: (context) => ReceiptAttempts(
              repository: context.read<AgreementsRepository>(),
              storage: storage,
              payables: context.read<PayablesRepository>(),
            ),
          ),
          ChangeNotifierProvider<SessionController>.value(value: session),
        ],
        child: MediaQuery(
          data: const MediaQueryData(size: Size(1280, 800)),
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => showPayableFormModal(context, space: pf),
                  child: const Text('Abrir Modal'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir Modal'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Nova conta a pagar'), findsOneWidget);
    expect(find.byTooltip('Fechar'), findsOneWidget);

    tester.view.physicalSize = const Size(1280, 480);
    await tester.pumpAndSettle();
    final scrollable = find
        .descendant(of: find.byType(Dialog), matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    await tester.drag(scrollable, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));

    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets(
    'showPayableFormModal: altura é dinâmica e compacta no avulso e expande no parcelado',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final backend = FakeBackend();
      final api = ApiClient(
        baseUrl: 'http://example.test',
        client: backend.client,
      );
      final storage = MemorySessionStorage();
      final auth = AuthRepository(api);
      final session = SessionController(api: api, auth: auth, storage: storage)
        ..user = const AppUser(id: 1, name: 'Demo', email: 'demo@example.com');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider.value(value: AgreementsRepository(api)),
            Provider.value(value: AccountsRepository(api)),
            Provider.value(value: PayablesRepository(api)),
            Provider(
              create: (context) => PayableCreations(
                repository: context.read<PayablesRepository>(),
                storage: storage,
              ),
            ),
            Provider(
              create: (context) => ReceiptAttempts(
                repository: context.read<AgreementsRepository>(),
                storage: storage,
                payables: context.read<PayablesRepository>(),
              ),
            ),
            ChangeNotifierProvider<SessionController>.value(value: session),
          ],
          child: MediaQuery(
            data: const MediaQueryData(size: Size(1280, 800)),
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => showPayableFormModal(context, space: pf),
                    child: const Text('Abrir Modal'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Modal'));
      await tester.pumpAndSettle();

      final formFinder = find.byType(PayableFormScreen);
      expect(formFinder, findsOneWidget);

      final avulsaHeight = tester.getSize(formFinder).height;
      // Altura em avulsa é compacta, menor que 650px
      expect(avulsaHeight, lessThan(650));

      // Ao alternar para parcelada, a altura expande
      await tester.tap(find.text('Parcelada'));
      await tester.pumpAndSettle();

      final parceladaHeight = tester.getSize(formFinder).height;
      expect(parceladaHeight, greaterThan(avulsaHeight));

      // Ao alternar para recorrente
      await tester.tap(find.text('Recorrente'));
      await tester.pumpAndSettle();
      final recorrenteHeight = tester.getSize(formFinder).height;
      expect(recorrenteHeight, greaterThan(avulsaHeight));
    },
  );

  testWidgets(
    'AC-UI-007: rótulo do campo de valor em modo fixo é "Valor mensal" e em modo variável é "Valor da primeira ocorrência (opcional)"',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final backend = FakeBackend();
      final api = ApiClient(
        baseUrl: 'http://example.test',
        client: backend.client,
      );
      final storage = MemorySessionStorage();
      final auth = AuthRepository(api);
      final session = SessionController(api: api, auth: auth, storage: storage)
        ..user = const AppUser(id: 1, name: 'Demo', email: 'demo@example.com');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider.value(value: AgreementsRepository(api)),
            Provider.value(value: AccountsRepository(api)),
            Provider.value(value: PayablesRepository(api)),
            Provider(
              create: (context) => PayableCreations(
                repository: context.read<PayablesRepository>(),
                storage: storage,
              ),
            ),
            Provider(
              create: (context) => ReceiptAttempts(
                repository: context.read<AgreementsRepository>(),
                storage: storage,
                payables: context.read<PayablesRepository>(),
              ),
            ),
            ChangeNotifierProvider<SessionController>.value(value: session),
          ],
          child: MediaQuery(
            data: const MediaQueryData(size: Size(1280, 800)),
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => showPayableFormModal(context, space: pf),
                    child: const Text('Abrir Modal'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Modal'));
      await tester.pumpAndSettle();

      // 1. Alterna para Recorrente
      await tester.tap(find.text('Recorrente'));
      await tester.pumpAndSettle();

      // Em modo fixo (padrão): rótulo é "Valor mensal"
      expect(find.text('Valor mensal *'), findsOneWidget);

      // 2. Alterna para Valor Variável
      await tester.tap(find.text('Valor Variável'));
      await tester.pumpAndSettle();

      // Em modo variável: rótulo é "Valor da primeira ocorrência (opcional)"
      expect(
        find.text('Valor da primeira ocorrência (opcional)'),
        findsOneWidget,
      );
      expect(find.textContaining('(opcional / a de'), findsNothing);
    },
  );
}
