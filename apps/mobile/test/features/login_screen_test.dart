import 'dart:convert';

import 'package:bigdevz_finance/bootstrap.dart';
import 'package:bigdevz_finance/features/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fake_backend.dart';

void main() {
  late FakeBackend backend;
  late MemorySessionStorage storage;

  setUp(() {
    backend = FakeBackend();
    storage = MemorySessionStorage();
  });

  Future<void> launchLogin(
    WidgetTester tester, {
    ({String email, String token})? recoveryLink,
  }) async {
    await tester.pumpWidget(
      buildApp(
        baseUrl: 'http://api.test/api',
        storage: storage,
        client: backend.client,
        recoveryLink: recoveryLink,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('AC-AUTH-001 abre a recuperação a partir do login', (
    tester,
  ) async {
    await launchLogin(tester);
    await tester.tap(find.text('Esqueci minha senha'));
    await tester.pumpAndSettle();
    expect(find.text('Recuperar senha'), findsOneWidget);
    expect(find.text('Enviar link'), findsOneWidget);
  });

  testWidgets('AC-AUTH-001 redefine a senha e retorna ao login', (
    tester,
  ) async {
    final token = 'a' * 64;
    backend.overrides['POST /auth/reset-password'] = (request) {
      expect(jsonDecode(request.body), {
        'email': 'teste@example.com',
        'token': token,
        'password': 'á2345678',
        'password_confirmation': 'á2345678',
      });
      return http.Response('', 204);
    };
    await launchLogin(
      tester,
      recoveryLink: (email: 'teste@example.com', token: token),
    );
    final password = find.widgetWithText(TextFormField, 'Nova senha');
    final confirmation = find.widgetWithText(
      TextFormField,
      'Confirme a nova senha',
    );
    for (final value in ['á234567', '12345678', 'á2345678']) {
      await tester.enterText(password, value);
      await tester.enterText(confirmation, value);
      await tester.tap(find.text('Alterar senha'));
      await tester.pumpAndSettle();
      if (value != 'á2345678') {
        expect(
          find.text('Use pelo menos 8 caracteres e inclua uma letra.'),
          findsOneWidget,
        );
        expect(backend.requests, isEmpty);
      }
    }
    expect(
      find.text('Senha alterada. Entre com sua nova senha.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Voltar ao login'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

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

  testWidgets(
    'AC-UI-017 credita a BigDev.Z e separa a marca do formulário no desktop',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await launchLogin(tester);

      final panel = find.byKey(const ValueKey('login-panel'));
      expect(tester.getCenter(panel).dx, closeTo(720, 1));
      expect(tester.getSize(panel).width, lessThanOrEqualTo(1000));
      expect(find.text('Desenvolvido por'), findsOneWidget);
      expect(find.text('BigDev.Z - IT Consulting'), findsOneWidget);
      expect(
        tester
            .getCenter(find.text('Finanças pessoais e da empresa, separadas.'))
            .dx,
        lessThan(
          tester.getCenter(find.widgetWithText(TextFormField, 'E-mail')).dx,
        ),
      );
    },
  );

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
