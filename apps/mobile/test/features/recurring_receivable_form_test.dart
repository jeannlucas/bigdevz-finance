import 'dart:convert';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/agreements/agreement.dart';
import 'package:bigdevz_finance/features/agreements/agreement_form_screen.dart';
import 'package:bigdevz_finance/features/agreements/agreement_item_adapter.dart';
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
  late FakeBackend backend;
  late MemorySessionStorage storage;

  Widget buildScreen({
    FakeBackend? customBackend,
    Size size = const Size(375, 812),
  }) {
    backend = customBackend ?? FakeBackend();
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

  test('Ocorrência que aguarda valor permanece em aberto na agenda', () {
    final agreement = Agreement.fromJson({
      'id': 1,
      'description': 'Receita variável',
      'kind': 'recurring',
      'received': '0.00',
      'remaining': '0.00',
      'paid_installments': 0,
      'overdue_installments': 0,
      'installments': [
        {
          'id': 1,
          'agreement_id': 1,
          'number': 1,
          'due_date': '2026-11-23',
          'received': '0.00',
          'status': 'awaiting_amount',
          'overdue': false,
        },
      ],
    });
    final item = AgreementInstallmentItemAdapter(
      agreement: agreement,
      installment: agreement.installments.single,
    );

    expect(item.isAwaitingAmount, isTrue);
    expect(item.isSettled, isFalse);
  });

  testWidgets(
    'Alterna para modo recorrente e valida alternância entre Valor Fixo e Variável (AC-UI-012)',
    (tester) async {
      final customBackend = FakeBackend();
      Map<String, dynamic>? previewPayload;
      customBackend.overrides['POST /spaces/1/agreements/recurrence-preview'] =
          (req) {
            previewPayload = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response('{}', 422);
          };
      await tester.pumpWidget(buildScreen(customBackend: customBackend));
      await tester.pumpAndSettle();

      // Clica em Recorrente no seletor
      await tester.tap(find.text('Recorrente'));
      await tester.pumpAndSettle();

      // Modo Fixo ativo por padrão
      expect(find.text('Valor Fixo'), findsOneWidget);
      expect(find.text('Valor Variável'), findsOneWidget);
      expect(find.text('Valor mensal *'), findsOneWidget);
      expect(find.text('Data de início *'), findsOneWidget);
      expect(find.text('Com data de término'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Descrição *'),
        'Receita variável',
      );
      await tester.scrollUntilVisible(
        find.text('Revisar ocorrências'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Revisar ocorrências'), findsOneWidget);
      expect(find.text('Confirmar recorrência'), findsOneWidget);

      // Alterna para Valor Variável
      await tester.tap(find.text('Valor Variável'));
      await tester.pumpAndSettle();

      // Rótulos e campos do modo variável
      expect(find.text('Valor da 1ª ocorrência (opcional)'), findsOneWidget);
      expect(
        find.text('Estimativa de valor (opcional, para planejamento)'),
        findsOneWidget,
      );
      expect(
        find.text('Aguardando valor: o valor exato será informado a cada mês.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Estimativa de valor (opcional, para planejamento)',
        ),
        '50000',
      );
      final review = find.text('Revisar ocorrências');
      await tester.scrollUntilVisible(
        review,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(review);
      await tester.pumpAndSettle();

      expect(previewPayload, isNotNull);
      expect(previewPayload!['amount'], isNull);
      expect(previewPayload!['estimated_amount'], '500.00');
    },
  );

  testWidgets(
    'Revisão de ocorrências renderiza resumo e horizonte calculado pela API (AC-FIN-034, AC-FIN-035)',
    (tester) async {
      final customBackend = FakeBackend();
      customBackend.overrides['POST /spaces/1/agreements/recurrence-preview'] =
          (req) {
            return http.Response(
              jsonEncode({
                'data': {
                  'reference_day': 10,
                  'horizon': '2027-02-01',
                  'approved_until': '2026-05-01',
                  'first_due_date': '2026-02-10',
                  'last_due_date': '2026-05-10',
                  'count': 4,
                  'past_count': 0,
                  'past_total': '0.00',
                  'total': '8000.00',
                  'items': [
                    {'due_date': '2026-02-10', 'past': false},
                    {'due_date': '2026-03-10', 'past': false},
                    {'due_date': '2026-04-10', 'past': false},
                    {'due_date': '2026-05-10', 'past': false},
                  ],
                },
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          };

      await tester.pumpWidget(buildScreen(customBackend: customBackend));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recorrente'));
      await tester.pumpAndSettle();

      // Preenche descrição e valor mensal
      final descField = find.ancestor(
        of: find.text('Descrição *'),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(descField, 'CONSULTORIA MENSAL');

      final amountField = find.ancestor(
        of: find.text('Valor mensal *'),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(amountField, '200000');
      await tester.pumpAndSettle();

      // Clica em Revisar ocorrências
      await tester.scrollUntilVisible(
        find.text('Revisar ocorrências'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Revisar ocorrências'));
      await tester.pumpAndSettle();

      // Valida card de revisão
      expect(find.text('Ocorrências que serão criadas'), findsOneWidget);
      expect(find.text('4 · total R\$ 8.000,00'), findsOneWidget);
      expect(find.text('até 02/2027'), findsOneWidget);
    },
  );

  testWidgets(
    'Alerta e exige confirmação de ocorrências retroativas no preview (AC-FIN-035)',
    (tester) async {
      final customBackend = FakeBackend();
      customBackend.overrides['POST /spaces/1/agreements/recurrence-preview'] =
          (req) {
            return http.Response(
              jsonEncode({
                'data': {
                  'reference_day': 5,
                  'horizon': '2027-02-01',
                  'approved_until': '2026-05-01',
                  'first_due_date': '2025-11-05',
                  'last_due_date': '2026-02-05',
                  'count': 4,
                  'past_count': 2,
                  'past_total': '1000.00',
                  'total': '2000.00',
                  'items': [
                    {'due_date': '2025-11-05', 'past': true},
                    {'due_date': '2025-12-05', 'past': true},
                    {'due_date': '2026-01-05', 'past': false},
                    {'due_date': '2026-02-05', 'past': false},
                  ],
                },
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          };

      await tester.pumpWidget(buildScreen(customBackend: customBackend));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recorrente'));
      await tester.pumpAndSettle();

      final descField = find.ancestor(
        of: find.text('Descrição *'),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(descField, 'ALUGUEL RETROATIVO');

      final amountField = find.ancestor(
        of: find.text('Valor mensal *'),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(amountField, '50000');
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Revisar ocorrências'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Revisar ocorrências'));
      await tester.pumpAndSettle();

      // Confirma banner de aviso e checkbox
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('confirm-past')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('confirm-past')), findsOneWidget);
      expect(
        find.textContaining('2 ocorrências já venceram (total R\$ 1.000,00)'),
        findsOneWidget,
      );

      // Marca o checkbox
      await tester.tap(
        find.byKey(const ValueKey('confirm-past')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Submissão de receita recorrente variável envia payload com is_variable=true (AC-FIN-034)',
    (tester) async {
      final customBackend = FakeBackend();
      http.Request? capturedRequest;
      customBackend.overrides['POST /spaces/1/agreements'] = (req) {
        capturedRequest = req;
        return http.Response(
          jsonEncode({
            'data': {
              'id': 99,
              'kind': 'recurring',
              'description': 'COMISSAO VARIAVEL',
              'is_variable': true,
              'amount': '362.05',
              'estimated_amount': '500.00',
              'start_date': '2026-02-01',
              'reference_day': 1,
              'end_date': null,
              'received': '0.00',
              'remaining': '362.05',
              'paid_installments': 0,
              'overdue_installments': 0,
              'is_cancelled': false,
              'installments': [],
            },
          }),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      };

      await tester.pumpWidget(buildScreen(customBackend: customBackend));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recorrente'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Valor Variável'));
      await tester.pumpAndSettle();

      final descField = find.ancestor(
        of: find.text('Descrição *'),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(descField, 'COMISSAO VARIAVEL');

      // Valor da 1ª ocorrência: 362,05
      final amountField = find.ancestor(
        of: find.text('Valor da 1ª ocorrência (opcional)'),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(amountField, '36205');

      // Estimativa: 500,00
      final estField = find.ancestor(
        of: find.text('Estimativa de valor (opcional, para planejamento)'),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(estField, '50000');
      await tester.pumpAndSettle();

      // Clica em Confirmar recorrência
      final submitBtn = find.text('Confirmar recorrência');
      await tester.scrollUntilVisible(
        submitBtn,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(capturedRequest, isNotNull);
      final payload = jsonDecode(capturedRequest!.body) as Map<String, dynamic>;
      expect(payload['kind'], 'recurring');
      expect(payload['is_variable'], isTrue);
      expect(payload['amount'], '362.05');
      expect(payload['estimated_amount'], '500.00');
    },
  );
}
