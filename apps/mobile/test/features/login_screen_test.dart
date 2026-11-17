import 'package:bigdevz_finance/bootstrap.dart';
import 'package:bigdevz_finance/features/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';

void main() {
  late FakeBackend backend;
  late MemorySessionStorage storage;

  setUp(() {
    backend = FakeBackend();
    storage = MemorySessionStorage();
  });

  Future<void> launchLogin(WidgetTester tester) async {
    await tester.pumpWidget(
      buildApp(
        baseUrl: 'http://api.test/api',
        storage: storage,
        client: backend.client,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('LoginScreen: renderiza identidade visual oficial e campos', (
    tester,
  ) async {
    await launchLogin(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('BigDev'), findsOneWidget);
    expect(find.text('.Z'), findsOneWidget);
    expect(find.text('FINANCE'), findsOneWidget);
    expect(
      find.text('Finanças pessoais e da empresa, separadas.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, 'E-mail'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Senha'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
  });

  testWidgets('LoginScreen: valida campos obrigatórios ao submeter vazio', (
    tester,
  ) async {
    await launchLogin(tester);

    // Tenta submeter sem preencher
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Informe seu e-mail.'), findsOneWidget);
    expect(find.text('Informe sua senha.'), findsOneWidget);
  });

  testWidgets(
    'LoginScreen: SingleChildScrollView suporta rolagem e keyboard onDrag',
    (tester) async {
      await launchLogin(tester);

      final scrollFinder = find.byType(SingleChildScrollView);
      expect(scrollFinder, findsOneWidget);

      final scrollWidget = tester.widget<SingleChildScrollView>(scrollFinder);
      expect(
        scrollWidget.keyboardDismissBehavior,
        ScrollViewKeyboardDismissBehavior.onDrag,
      );
    },
  );
}
