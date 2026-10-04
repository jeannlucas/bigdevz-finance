import 'dart:async';

import 'package:bigdevz_finance/bootstrap.dart';
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

  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(
      buildApp(
        baseUrl: 'http://api.test/api',
        storage: storage,
        client: backend.client,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> login(WidgetTester tester, String password) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'E-mail'),
      'teste@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Senha'),
      password,
    );
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
  }

  testWidgets('valida campos e mostra a recusa da API', (tester) async {
    await start(tester);
    await tester.tap(find.text('Entrar'));
    await tester.pump();
    expect(find.text('Informe seu e-mail.'), findsOneWidget);
    expect(find.text('Informe sua senha.'), findsOneWidget);
    expect(backend.requests, isEmpty);

    await login(tester, 'errada');
    expect(find.text('E-mail ou senha inválidos.'), findsOneWidget);
    expect(storage.values, isEmpty);
  });

  testWidgets('cenário 10: troca PF/PJ não mantém dados do espaço anterior', (
    tester,
  ) async {
    await start(tester);
    await login(tester, 'senha-certa');

    expect(find.text(r'R$ 1.000,00'), findsOneWidget);
    expect(find.text('Pessoal (PF)'), findsOneWidget);
    expect(storage.values['auth_token'], 'token-valido');

    // A troca invalida a tela na hora: enquanto o PJ carrega, nada do PF aparece.
    backend.holds['GET /spaces/2/summary'] = Completer<void>();
    await tester.tap(find.text('PJ'));
    await tester.pump();
    expect(find.text(r'R$ 1.000,00'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    backend.holds.remove('GET /spaces/2/summary')!.complete();
    await tester.pumpAndSettle();
    expect(find.text(r'R$ 5.000,00'), findsOneWidget);
    expect(find.text('Empresa (PJ)'), findsOneWidget);
    expect(find.text(r'R$ 1.000,00'), findsNothing);
    expect(storage.values['active_space_id'], '2');
  });

  testWidgets('resposta atrasada do espaço anterior é descartada', (
    tester,
  ) async {
    await start(tester);
    backend.holds['GET /spaces/1/summary'] = Completer<void>();
    await login(tester, 'senha-certa');
    // Troca antes de o PF responder.
    await tester.tap(find.text('PJ'));
    await tester.pumpAndSettle();
    backend.holds.remove('GET /spaces/1/summary')!.complete();
    await tester.pumpAndSettle();

    expect(find.text(r'R$ 5.000,00'), findsOneWidget);
    expect(find.text(r'R$ 1.000,00'), findsNothing);
  });

  testWidgets('cenário 10: reabrir o app recupera sessão e espaço pela API', (
    tester,
  ) async {
    storage.values['auth_token'] = 'token-valido';
    storage.values['active_space_id'] = '2';
    await start(tester);

    expect(find.text('Empresa (PJ)'), findsOneWidget);
    expect(find.text(r'R$ 5.000,00'), findsOneWidget);
    expect(
      backend.requests.map((request) => request.url.path),
      containsAll(['/api/me', '/api/spaces', '/api/spaces/2/summary']),
    );
  });

  testWidgets('token recusado pela API volta ao login e descarta o token', (
    tester,
  ) async {
    storage.values['auth_token'] = 'token-revogado';
    await start(tester);

    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('Sua sessão expirou. Entre novamente.'), findsOneWidget);
    expect(storage.values.containsKey('auth_token'), isFalse);
  });

  testWidgets(
    'API fora do ar na abertura permite tentar de novo sem perder o token',
    (tester) async {
      storage.values['auth_token'] = 'token-valido';
      backend.overrides['GET /me'] = (_) => throw http.ClientException('rede');
      await start(tester);
      expect(find.text('Tentar novamente'), findsOneWidget);
      expect(storage.values['auth_token'], 'token-valido');

      backend.overrides.remove('GET /me');
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(find.text(r'R$ 1.000,00'), findsOneWidget);
    },
  );

  testWidgets('resposta fora do contrato na abertura não trava o app', (
    tester,
  ) async {
    storage.values['auth_token'] = 'token-valido';
    backend.overrides['GET /me'] = (_) =>
        FakeBackend.json({'data': 'inesperado'});
    await start(tester);
    expect(
      find.text('Não foi possível abrir a sessão. Tente novamente.'),
      findsOneWidget,
    );
    expect(storage.values['auth_token'], 'token-valido');
  });
}
