import 'dart:convert';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/agreements/agreement_form_screen.dart';
import 'package:bigdevz_finance/features/agreements/agreements_repository.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';

const pf = Space(id: 1, kind: 'PF', name: 'Pessoal');

void main() {
  late MemorySessionStorage storage;

  Widget buildScreen({Size size = const Size(375, 812)}) {
    final backend = FakeBackend();
    final api = ApiClient(
      baseUrl: 'http://example.test',
      client: backend.client,
    );
    storage = MemorySessionStorage();
    final auth = AuthRepository(api);
    final session = SessionController(api: api, auth: auth, storage: storage);

    return MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        home: MultiProvider(
          providers: [
            Provider<AgreementsRepository>(
              create: (_) => AgreementsRepository(api),
            ),
            ChangeNotifierProvider<SessionController>.value(value: session),
          ],
          child: const AgreementFormScreen(space: pf),
        ),
      ),
    );
  }

  testWidgets(
    'AgreementFormScreen: inicia no modo Avulsa por padrão e alterna para Parcelada',
    (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // Botão inicial
      expect(find.text('Salvar conta a receber'), findsOneWidget);
      expect(
        find.text('Recebimento à vista ou parcela única.'),
        findsOneWidget,
      );

      // Alterna para Parcelada
      await tester.tap(find.text('Parcelada'));
      await tester.pumpAndSettle();

      // Altera para 3 parcelas
      final countField = find.ancestor(
        of: find.text('Quantidade de parcelas'),
        matching: find.byType(TextFormField),
      );
      expect(countField, findsOneWidget);
      await tester.enterText(countField, '3');
      await tester.pumpAndSettle();

      // Botão atualiza dinamicamente
      final submitBtn = find.text('Gerar parcelas');
      await tester.scrollUntilVisible(
        submitBtn,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(submitBtn, findsOneWidget);
      expect(
        find.textContaining('As 3 parcelas somam o valor total'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'AgreementFormScreen: em desktop web (>= 640px) renderiza card centralizado com maxWidth',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildScreen(size: const Size(1280, 800)));
      await tester.pumpAndSettle();

      // Card executivo
      expect(find.byType(Card), findsOneWidget);

      // ConstrainedBox com maxWidth de 580
      final constrainedBox = tester.widget<ConstrainedBox>(
        find
            .ancestor(
              of: find.byType(Card),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(constrainedBox.constraints.maxWidth, 580);

      // Alterna para parcelada para validar Row com Parcelas e Primeiro vencimento
      await tester.tap(find.text('Parcelada'));
      await tester.pumpAndSettle();

      // Campos Parcelas e Primeiro vencimento em 2 colunas (Row)
      expect(
        find.ancestor(of: find.text('Parcelas'), matching: find.byType(Row)),
        findsWidgets,
      );
      expect(
        find.ancestor(
          of: find.text('Primeiro vencimento'),
          matching: find.byType(Row),
        ),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'showAgreementFormModal: abre Dialog em desktop com botão de fechar',
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
      storage = MemorySessionStorage();
      final auth = AuthRepository(api);
      final session = SessionController(api: api, auth: auth, storage: storage);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1280, 800)),
          child: MaterialApp(
            home: MultiProvider(
              providers: [
                Provider<AgreementsRepository>(
                  create: (_) => AgreementsRepository(api),
                ),
                ChangeNotifierProvider<SessionController>.value(value: session),
              ],
              child: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => showAgreementFormModal(context, space: pf),
                    child: const Text('Abrir'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Nova conta a receber'), findsOneWidget);
      expect(find.byTooltip('Fechar'), findsOneWidget);

      await tester.tap(find.byTooltip('Fechar'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
    },
  );

  testWidgets(
    'AgreementFormScreen: modo por parcela calcula total e exibe InstallmentSummaryCard',
    (tester) async {
      final backend = FakeBackend();
      backend.overrides['POST /spaces/1/agreements'] = (req) {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'data': {
              'id': 99,
              'description': body['description'],
              'total': body['total'],
              'installment_count': body['installment_count'],
              'received': '0.00',
              'remaining': body['total'],
              'paid_installments': 0,
              'overdue_installments': 0,
              'next_due_date': body['first_due_date'],
              'installments': [],
            },
          }),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      };

      final api = ApiClient(
        baseUrl: 'http://example.test',
        client: backend.client,
      );
      final storage = MemorySessionStorage();
      final auth = AuthRepository(api);
      final session = SessionController(api: api, auth: auth, storage: storage);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AgreementsRepository>(
              create: (_) => AgreementsRepository(api),
            ),
            ChangeNotifierProvider<SessionController>.value(value: session),
          ],
          child: const MediaQuery(
            data: MediaQueryData(size: Size(375, 812)),
            child: MaterialApp(home: AgreementFormScreen(space: pf)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Alterna para Parcelada
      await tester.tap(find.text('Parcelada'));
      await tester.pumpAndSettle();

      // Preenche descrição
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Descrição'),
        'Venda Parcelada',
      );

      // Altera quantidade de parcelas para 10
      final countField = find.ancestor(
        of: find.text('Quantidade de parcelas'),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(countField, '10');
      await tester.pumpAndSettle();

      // Verifica que o seletor de modo aparece e o padrão é "Valor da parcela"
      expect(find.text('Valor da parcela'), findsWidgets);

      // Preenche o valor de cada parcela: R$ 250,00
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Valor da parcela'),
        '25000',
      );
      await tester.pumpAndSettle();

      // Card de resumo deve ser exibido com 10 parcelas de R$ 250,00 e Total: R$ 2.500,00
      expect(find.textContaining('10 parcelas de R\$ 250,00'), findsOneWidget);
      expect(find.textContaining('R\$ 2.500,00'), findsOneWidget);

      // Salva
      final submitBtn = find.text('Gerar parcelas');
      await tester.scrollUntilVisible(
        submitBtn,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Verifica requisição enviada à API com total 2500.00 e 10 parcelas
      final creates = backend.requests
          .where((r) => r.url.path.endsWith('/agreements'))
          .toList();
      expect(creates, hasLength(1));
      final payload = jsonDecode(creates[0].body);
      expect(payload['total'], '2500.00');
      expect(payload['installment_count'], 10);
    },
  );
}
