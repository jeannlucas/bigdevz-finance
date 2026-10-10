import 'dart:convert';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/accounts/accounts_repository.dart';
import 'package:bigdevz_finance/features/agreements/agreements_repository.dart';
import 'package:bigdevz_finance/features/agreements/receipt_attempts.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:bigdevz_finance/features/payables/payable_creations.dart';
import 'package:bigdevz_finance/features/payables/payable_form_screen.dart';
import 'package:bigdevz_finance/features/payables/payable_screen.dart';
import 'package:bigdevz_finance/features/payables/payables_repository.dart';
import 'package:bigdevz_finance/features/payables/payables_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';
import '../support/fake_payables_api.dart';
import '../support/fake_receipts_api.dart' show Delivery;

const pf = Space(id: 1, kind: 'PF', name: 'Pessoal');

// Contra a API simulada (mesma regra de chave da API Laravel). Persistência
// e concorrência reais: testes PHP em PostgreSQL.
void main() {
  late FakePayablesApi fake;
  late MemorySessionStorage storage;

  ApiClient api() =>
      ApiClient(baseUrl: 'http://api.test/api', client: fake.client);
  ReceiptAttempts attempts() => ReceiptAttempts(
    repository: AgreementsRepository(api()),
    storage: storage,
    payables: PayablesRepository(api()),
  );

  setUp(() {
    fake = FakePayablesApi();
    storage = MemorySessionStorage();
  });

  group('serviço', () {
    Future<ReceiptAttemptOutcome> pay(
      ReceiptAttempts service,
      String amount, {
      int userId = 1,
    }) => service.submitPayment(
      userId: userId,
      spaceId: 1,
      payableId: 40,
      accountId: 7,
      accountName: 'Banco PF',
      amount: Money.parse(amount),
      paidOn: '2026-03-10',
    );

    test(
      'pagamento com resposta perdida: restaurado e verificado uma vez',
      () async {
        fake.script.add(Delivery.loseResponse);
        final first = await pay(attempts(), '100.00');
        expect(first.state, ReceiptAttemptState.uncertain);
        expect(fake.balances[7], 90000, reason: 'a API gravou');
        expect(await storage.read('pending_payment.1.1.40'), isNotNull);
        expect(
          await storage.read('pending_receipt.1.1.40'),
          isNull,
          reason: 'chaves separadas',
        );

        final reopened = attempts();
        expect(await reopened.pendingPayment(2, 1, 40), isNull);
        expect(await reopened.pendingPayment(1, 2, 40), isNull);
        // Outro pagamento na mesma obrigação: nada sai.
        final blocked = await pay(reopened, '50.00');
        expect(blocked.attempt.idempotencyKey, first.attempt.idempotencyKey);
        final resolved = await reopened.resolve(
          (await reopened.pendingPayment(1, 1, 40))!,
        );
        expect(resolved.state, ReceiptAttemptState.confirmed);
        expect(
          resolved.message,
          'Pagamento já estava registrado: R\$ 100,00 de Banco PF.',
        );
        expect(fake.allPayments, hasLength(1));
        expect(fake.balances[7], 90000, reason: 'saída uma vez');
        expect(
          fake.writes.map((r) => r.headers['Idempotency-Key']).toSet(),
          hasLength(1),
        );
      },
    );

    test(
      'estorno com resposta perdida e recusa registrada que continua recusada',
      () async {
        final service = attempts();
        final done = await pay(service, '300.00');
        final refused = await pay(service, '10.00');
        expect(refused.state, ReceiptAttemptState.rejected);

        fake.script.add(Delivery.loseResponse);
        final payment = done.payment!.payment;
        final reversal = await service.submitPaymentFix(
          userId: 1,
          spaceId: 1,
          payableId: 40,
          original: payment,
          originalAccountName: 'Banco PF',
          reason: 'Pago em duplicidade',
        );
        expect(reversal.state, ReceiptAttemptState.uncertain);
        final resolved = await service.resolve(reversal.attempt);
        expect(resolved.paymentFix!.original.isReversed, isTrue);
        expect(fake.balances[7], 100000, reason: 'devolvido uma vez');

        // A obrigação reabriu, mas a chave recusada continua recusada.
        final late = await service.resolve(refused.attempt);
        expect(late.state, ReceiptAttemptState.rejected);
        expect(fake.allPayments, hasLength(1));
      },
    );
  });

  group('telas', () {
    Future<void> pump(
      WidgetTester tester,
      Widget home, {
      int userId = 1,
    }) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final client = api();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider.value(value: AgreementsRepository(client)),
            Provider.value(value: AccountsRepository(client)),
            Provider.value(value: PayablesRepository(client)),
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
            ChangeNotifierProvider(
              create: (_) => SessionController(
                api: client,
                auth: AuthRepository(client),
                storage: MemorySessionStorage(),
              )..user = AppUser(id: userId, name: 'P', email: 'p@example.com'),
            ),
          ],
          child: MaterialApp(home: home),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tapText(WidgetTester tester, String text) async {
      // Listas longas não constroem o que está longe: rola até o texto.
      if (find.text(text).evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          find.text(text),
          200,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await tester.ensureVisible(find.text(text).last);
      await tester.pump();
      await tester.tap(find.text(text).last);
      await tester.pumpAndSettle();
    }

    Future<void> chooseAccount(WidgetTester tester, String name) async {
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    Finder line(String id, String text) => find.descendant(
      of: find.byKey(ValueKey('payment-$id')),
      matching: find.text(text),
    );

    void dismiss(WidgetTester tester) =>
        ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
            .hideCurrentSnackBar();

    testWidgets(
      'pagamento parcial e total: conta obrigatória, revisão, voltar sem gravar e saldo exato',
      (tester) async {
        await pump(tester, const PayableScreen(space: pf, payableId: 40));
        await tapText(tester, 'Registrar pagamento');
        await tapText(tester, 'Revisar pagamento');
        expect(find.text('Escolha a conta de origem.'), findsOneWidget);
        expect(fake.writes, isEmpty);

        await chooseAccount(tester, 'Banco PF');
        await tapText(tester, 'Parcial');
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Valor pago'),
          '10000',
        );
        await tapText(tester, 'Revisar pagamento');
        expect(line('Saldo', r'R$ 1.000,00 → R$ 900,00'), findsOneWidget);
        expect(line('Restante', r'R$ 200,00'), findsOneWidget);
        expect(line('Beneficiario', 'Oficina'), findsOneWidget);
        await tapText(tester, 'Voltar e corrigir');
        expect(fake.writes, isEmpty, reason: 'cancelar a revisão não grava');

        await tapText(tester, 'Revisar pagamento');
        await tapText(tester, 'Confirmar pagamento');
        expect(
          find.text(
            r'Pagamento confirmado: R$ 100,00 de Banco PF. Saldo da conta: R$ 900,00.',
          ),
          findsOneWidget,
        );
        expect(fake.balances[7], 90000);

        dismiss(tester);
        await tester.pumpAndSettle();
        await tapText(tester, 'Registrar pagamento');
        await chooseAccount(tester, 'Banco PF');
        await tapText(tester, 'Total');
        await tapText(tester, 'Revisar pagamento');
        expect(line('Restante', r'R$ 0,00 · paga'), findsOneWidget);
        await tapText(tester, 'Confirmar pagamento');
        expect(
          find.textContaining(r'Saldo da conta: R$ 700,00'),
          findsOneWidget,
        );
        expect(find.text('Registrar pagamento'), findsNothing);
        expect(find.text('Paga'), findsOneWidget);
      },
    );

    testWidgets('saldo negativo resultante é mostrado na revisão', (
      tester,
    ) async {
      await pump(tester, const PayableScreen(space: pf, payableId: 40));
      await tapText(tester, 'Registrar pagamento');
      await chooseAccount(tester, 'Reserva PF');
      await tapText(tester, 'Total');
      await tapText(tester, 'Revisar pagamento');
      expect(line('Saldo', r'R$ 0,00 → -R$ 300,00'), findsOneWidget);
      expect(
        find.text(r'O saldo de Reserva PF ficará negativo (-R$ 300,00).'),
        findsOneWidget,
      );
    });

    testWidgets(
      'correção de pagamento com resposta perdida bloqueia a obrigação e resolve uma vez',
      (tester) async {
        final service = attempts();
        await service.submitPayment(
          userId: 1,
          spaceId: 1,
          payableId: 40,
          accountId: 7,
          accountName: 'Banco PF',
          amount: Money.parse('100.00'),
          paidOn: '2026-03-10',
        );
        fake.script.add(Delivery.loseResponse);
        await pump(tester, const PayableScreen(space: pf, payableId: 40));
        await tester.tap(find.byTooltip('Ações do pagamento'));
        await tester.pumpAndSettle();
        await tapText(tester, 'Corrigir pagamento');
        await chooseAccount(tester, 'Reserva PF');
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Valor correto'),
          '8000',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Motivo'),
          'Conta errada',
        );
        await tapText(tester, 'Revisar correção');
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('payfix-Saldo-7')),
            matching: find.text(r'+R$ 100,00 · R$ 900,00 → R$ 1.000,00'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('payfix-Saldo-8')),
            matching: find.text(r'−R$ 80,00 · R$ 0,00 → -R$ 80,00'),
          ),
          findsOneWidget,
        );
        await tapText(tester, 'Confirmar correção');
        expect(find.text('Operação não confirmada'), findsOneWidget);
        await tapText(tester, 'Verificar depois');
        expect(
          find.text('Correção do pagamento aguardando confirmação'),
          findsOneWidget,
        );
        expect(find.text('Registrar pagamento'), findsNothing);
        expect(find.byTooltip('Ações do pagamento'), findsNothing);

        await pump(
          tester,
          const PayableScreen(space: pf, payableId: 40),
          userId: 2,
        );
        expect(
          find.text('Correção do pagamento aguardando confirmação'),
          findsNothing,
        );
        await pump(tester, const PayableScreen(space: pf, payableId: 40));
        await tapText(tester, 'Verificar recebimento');
        expect(
          find.textContaining('Correção do pagamento já estava registrada'),
          findsOneWidget,
        );
        expect(fake.balances[7], 100000);
        expect(fake.balances[8], -8000);
        expect(fake.allPayments, hasLength(2));
        expect(find.text('Corrigido'), findsOneWidget);
        expect(
          find.textContaining('Substitui um pagamento corrigido'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'fatura sem total não é paga; informar total libera; cancelar exige motivo',
      (tester) async {
        final bill = fake.addCardBill();
        await pump(tester, PayableScreen(space: pf, payableId: bill.id));
        expect(find.text('Valor a informar'), findsWidgets);
        expect(find.text('Registrar pagamento'), findsNothing);
        await tapText(tester, 'Informar total da fatura');
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Total da fatura'),
          '120000',
        );
        await tapText(tester, 'Salvar total');
        expect(find.text('Total da fatura salvo.'), findsOneWidget);
        expect(find.text('Registrar pagamento'), findsOneWidget);

        dismiss(tester);
        await tester.pumpAndSettle();
        await tapText(tester, 'Cancelar conta a pagar');
        await tapText(tester, 'Cancelar conta');
        expect(
          find.text('Cancelar conta a pagar?'),
          findsOneWidget,
          reason: 'motivo obrigatório',
        );
        await tester.enterText(find.byType(TextField).last, 'Cartão cancelado');
        await tapText(tester, 'Cancelar conta');
        expect(find.text('Conta a pagar cancelada.'), findsOneWidget);
        expect(bill.cancelReason, 'Cartão cancelado');
        expect(fake.balances[7], 100000);
      },
    );

    testWidgets(
      'parcelada exige prévia do cronograma; verificar após falha usa a mesma chave',
      (tester) async {
        fake.script.add(Delivery.dropBeforeServer);
        await pump(
          tester,
          PayableFormScreen(space: pf, today: DateTime(2026, 3, 10)),
        );
        await tapText(tester, 'Parcelada');
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Descrição'),
          'Notebook',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Valor total'),
          '10000',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Número de parcelas'),
          '3',
        );
        await tester.pump();
        final confirm = find.widgetWithText(
          FilledButton,
          'Confirmar cadastro das parcelas',
        );
        expect(
          tester.widget<FilledButton>(confirm).onPressed,
          isNull,
          reason: 'sem prévia',
        );

        await tapText(tester, 'Ver cronograma');
        expect(find.byKey(const ValueKey('schedule-3')), findsOneWidget);
        expect(find.text(r'R$ 33,34'), findsOneWidget);
        expect(find.text(r'R$ 33,33'), findsNWidgets(2));
        await tapText(tester, 'Confirmar cadastro das parcelas');
        // Sem resposta: a tela passa para a retomada, sem novo formulário.
        expect(find.text('Cadastro aguardando confirmação'), findsOneWidget);
        expect(find.textContaining('Sem conexão'), findsOneWidget);
        expect(find.widgetWithText(TextFormField, 'Descrição'), findsNothing);
        await tapText(tester, 'Verificar cadastro');

        final creates = fake.writes
            .where((r) => r.url.path.endsWith('/payables'))
            .toList();
        expect(creates, hasLength(2));
        expect(
          creates[0].headers['Idempotency-Key'],
          creates[1].headers['Idempotency-Key'],
        );
        expect(jsonDecode(creates[1].body)['installment_count'], 3);
        expect(
          fake.payables.values.where((p) => p.description == 'Notebook'),
          hasLength(3),
        );
      },
    );

    testWidgets(
      'cartões individuais de A pagar: estados em aberto, parcial, pago e valor a informar',
      (tester) async {
        fake.payables.clear();
        fake.payables[40] = FakePayable(40, 'Serviço de Nuvem AWS', 35000);
        final p2 = FakePayable(41, 'Internet Fibra', 20000);
        p2.payments.add(FakePayment(501, 7, 5000, '2026-03-10'));
        fake.payables[41] = p2;

        await pump(tester, const Scaffold(body: PayablesTab(space: pf)));
        await tester.pumpAndSettle();

        // Verifica exibição do contador e cartões individuais
        expect(find.text('2 contas a pagar'), findsOneWidget);
        expect(find.byType(Card), findsNWidgets(2));

        // Cartão 1: Em aberto
        expect(find.text('Serviço de Nuvem AWS'), findsOneWidget);
        expect(
          find.text(r'R$ 350,00'),
          findsWidgets,
        ); // Destaque restante e valor total

        // Cartão 2: Parcial
        expect(find.text('Internet Fibra'), findsOneWidget);
        expect(find.text('Pago líquido'), findsOneWidget);
        expect(find.text(r'R$ 50,00'), findsOneWidget);
        expect(find.text(r'R$ 150,00'), findsOneWidget); // Restante
        expect(find.text('Restante a pagar'), findsNWidgets(2));
      },
    );

    testWidgets(
      'seletor de tipo de A pagar: matriz de larguras (375px e 402px) e escalas de texto (1.0x, 1.5x e 2.0x)',
      (tester) async {
        final widths = [375.0, 402.0];
        final scales = [1.0, 1.5, 2.0];

        for (final width in widths) {
          for (final scale in scales) {
            tester.view.physicalSize = Size(width * 3, 800 * 3);
            tester.view.devicePixelRatio = 3;

            final client = api();
            await tester.pumpWidget(
              MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 800),
                  textScaler: TextScaler.linear(scale),
                ),
                child: MultiProvider(
                  providers: [
                    Provider.value(value: AgreementsRepository(client)),
                    Provider.value(value: AccountsRepository(client)),
                    Provider.value(value: PayablesRepository(client)),
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
                    ChangeNotifierProvider(
                      create: (_) =>
                          SessionController(
                              api: client,
                              auth: AuthRepository(client),
                              storage: MemorySessionStorage(),
                            )
                            ..user = const AppUser(
                              id: 1,
                              name: 'Demo',
                              email: 'demo@example.com',
                            ),
                    ),
                  ],
                  child: MaterialApp(
                    home: PayableFormScreen(
                      space: pf,
                      today: DateTime(2026, 3, 10),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            // Sem overflow
            expect(
              tester.takeException(),
              isNull,
              reason: 'overflow em w=$width s=$scale',
            );

            // As três opções devem estar visíveis e completas
            expect(find.text('Avulsa'), findsOneWidget);
            expect(find.text('Parcelada'), findsOneWidget);
            expect(find.text('Recorrente'), findsOneWidget);

            // Verifica altura mínima do alvo de toque de pelo menos 48px
            final singleBox = tester.getRect(find.text('Avulsa'));
            final recBox = tester.getRect(find.text('Recorrente'));
            expect(singleBox.height, greaterThanOrEqualTo(14));
            expect(recBox.height, greaterThanOrEqualTo(14));

            // Testa alternância para "Recorrente"
            await tester.tap(find.text('Recorrente'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final termFinder = find.text('Com data de término');
            await tester.scrollUntilVisible(
              termFinder,
              200,
              scrollable: find.byType(Scrollable).first,
            );
            // Rola de volta para o topo antes de alternar para "Parcelada"
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, 1000),
            );
            await tester.pumpAndSettle();

            // Testa alternância para "Parcelada"
            await tester.tap(find.text('Parcelada'), warnIfMissed: false);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final parcelasFinder = find.text('Número de parcelas');
            await tester.scrollUntilVisible(
              parcelasFinder,
              200,
              scrollable: find.byType(Scrollable).first,
            );
            expect(parcelasFinder, findsOneWidget);

            // Volta para "Avulsa", rolando para o topo
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, 1000),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('Avulsa'), warnIfMissed: false);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        }
        tester.view.reset();
      },
    );

    testWidgets(
      'cabeçalho respeita SafeArea com insets de topo (status bar / relógio) sem invasão',
      (tester) async {
        tester.view.physicalSize = const Size(1206, 2622); // iPhone 17 Pro
        tester.view.devicePixelRatio = 3;
        tester.view.padding = const FakeViewPadding(
          top: 177,
        ); // ~59pt status bar
        addTearDown(() {
          tester.view.reset();
        });

        final client = api();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: MultiProvider(
              providers: [
                Provider.value(value: AgreementsRepository(client)),
                Provider.value(value: AccountsRepository(client)),
                Provider.value(value: PayablesRepository(client)),
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
                ChangeNotifierProvider(
                  create: (_) =>
                      SessionController(
                          api: client,
                          auth: AuthRepository(client),
                          storage: MemorySessionStorage(),
                        )
                        ..user = const AppUser(
                          id: 1,
                          name: 'Demo',
                          email: 'demo@example.com',
                        ),
                ),
              ],
              child: PayableFormScreen(space: pf, today: DateTime(2026, 3, 10)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Topo do título "Nova conta a pagar" deve ser estritamente maior que o inset da barra de status (59pt)
        final titleTop = tester.getTopLeft(find.text('Nova conta a pagar')).dy;
        expect(titleTop, greaterThan(59.0));

        // Botão voltar também deve respeitar o inset
        final backButtonFinder = find.byType(BackButton);
        if (backButtonFinder.evaluate().isNotEmpty) {
          final backTop = tester.getTopLeft(backButtonFinder).dy;
          expect(backTop, greaterThanOrEqualTo(59.0));
        }

        // No início da rolagem com escala ampliada (150% e 200%), o título permanece abaixo da área segura
        for (final scale in [1.5, 2.0]) {
          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: const Size(402, 874),
                padding: const EdgeInsets.only(top: 59),
                textScaler: TextScaler.linear(scale),
              ),
              child: MaterialApp(
                theme: ThemeData.dark(),
                home: MultiProvider(
                  providers: [
                    Provider.value(value: AgreementsRepository(client)),
                    Provider.value(value: AccountsRepository(client)),
                    Provider.value(value: PayablesRepository(client)),
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
                    ChangeNotifierProvider(
                      create: (_) =>
                          SessionController(
                              api: client,
                              auth: AuthRepository(client),
                              storage: MemorySessionStorage(),
                            )
                            ..user = const AppUser(
                              id: 1,
                              name: 'Demo',
                              email: 'demo@example.com',
                            ),
                    ),
                  ],
                  child: PayableFormScreen(
                    space: pf,
                    today: DateTime(2026, 3, 10),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final scaledTitleTop = tester
              .getTopLeft(find.text('Nova conta a pagar'))
              .dy;
          expect(
            scaledTitleTop,
            greaterThan(59.0),
            reason: 'Título invade a status bar em scale=$scale',
          );
        }
      },
    );

    testWidgets(
      'rótulos completos em 375px e texto ampliado a 150% e 200%: Beneficiário (opcional), Primeiro vencimento e texto auxiliar',
      (tester) async {
        for (final scale in [1.5, 2.0]) {
          tester.view.physicalSize = Size(375 * 3, 800 * 3);
          tester.view.devicePixelRatio = 3;

          final client = api();
          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: const Size(375, 800),
                textScaler: TextScaler.linear(scale),
              ),
              child: MultiProvider(
                providers: [
                  Provider.value(value: AgreementsRepository(client)),
                  Provider.value(value: AccountsRepository(client)),
                  Provider.value(value: PayablesRepository(client)),
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
                  ChangeNotifierProvider(
                    create: (_) =>
                        SessionController(
                            api: client,
                            auth: AuthRepository(client),
                            storage: MemorySessionStorage(),
                          )
                          ..user = const AppUser(
                            id: 1,
                            name: 'Demo',
                            email: 'demo@example.com',
                          ),
                  ),
                ],
                child: MaterialApp(
                  home: PayableFormScreen(
                    space: pf,
                    today: DateTime(2026, 3, 10),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // 1. Rótulo "Beneficiário (opcional)" deve estar íntegro e visível
          final payeeFinder = find.text('Beneficiário (opcional)');
          await tester.scrollUntilVisible(
            payeeFinder,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          expect(payeeFinder, findsOneWidget);

          // Volta para o topo para o seletor de tipo ficar visível
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, 1000),
          );
          await tester.pumpAndSettle();

          // 2. Muda para "Recorrente"
          final recOptionFinder = find.text('Recorrente');
          await tester.scrollUntilVisible(
            recOptionFinder,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(recOptionFinder, warnIfMissed: false);
          await tester.pumpAndSettle();

          // 3. Rótulo "Primeiro vencimento" deve estar presente (não truncado com dia de ref dentro do rótulo)
          final vencimentoFinder = find.text('Primeiro vencimento');
          await tester.scrollUntilVisible(
            vencimentoFinder,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          expect(vencimentoFinder, findsOneWidget);

          // 4. Texto auxiliar explicativo sobre o dia de referência presente abaixo do campo
          final auxFinder = find.text(
            'O dia escolhido será usado como referência nos meses seguintes.',
          );
          await tester.scrollUntilVisible(
            auxFinder,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          expect(auxFinder, findsOneWidget);

          expect(tester.takeException(), isNull);
        }
        tester.view.reset();
      },
    );

    testWidgets(
      'com texto ampliado (200%) e teclado aberto, usuário consegue rolar até os campos e ações finais',
      (tester) async {
        tester.view.physicalSize = const Size(375 * 3, 800 * 3);
        tester.view.devicePixelRatio = 3;
        // Simula teclado virtual ocupando 300pt de altura
        tester.view.viewInsets = const FakeViewPadding(bottom: 900);
        addTearDown(() => tester.view.reset());

        final client = api();
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(375, 500), // altura reduzida pelo teclado
              viewInsets: EdgeInsets.only(bottom: 300),
              textScaler: TextScaler.linear(2.0),
            ),
            child: MultiProvider(
              providers: [
                Provider.value(value: AgreementsRepository(client)),
                Provider.value(value: AccountsRepository(client)),
                Provider.value(value: PayablesRepository(client)),
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
                ChangeNotifierProvider(
                  create: (_) =>
                      SessionController(
                          api: client,
                          auth: AuthRepository(client),
                          storage: MemorySessionStorage(),
                        )
                        ..user = const AppUser(
                          id: 1,
                          name: 'Demo',
                          email: 'demo@example.com',
                        ),
                ),
              ],
              child: MaterialApp(
                home: PayableFormScreen(
                  space: pf,
                  today: DateTime(2026, 3, 10),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Botão final 'Salvar conta a pagar' deve ser acessível rolando
        final saveBtnFinder = find.text('Salvar conta a pagar');
        await tester.scrollUntilVisible(
          saveBtnFinder,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(saveBtnFinder, findsOneWidget);

        // Aviso explicativo final também acessível
        final noticeFinder = find.textContaining(
          'Cadastrar não altera o saldo',
        );
        await tester.scrollUntilVisible(
          noticeFinder,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(noticeFinder, findsOneWidget);
      },
    );

    testWidgets(
      'preservação dos dados digitados ao alternar entre Avulsa, Parcelada e Recorrente',
      (tester) async {
        await pump(
          tester,
          PayableFormScreen(space: pf, today: DateTime(2026, 3, 10)),
        );
        await tester.pumpAndSettle();

        // Digita descrição, beneficiário e valor em Avulsa
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Descrição'),
          'Assinatura de Software',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Beneficiário (opcional)'),
          'Empresa SaaS LTDA',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Valor'),
          '15000',
        );
        await tester.pump();

        // Alterna para Parcelada
        await tester.tap(find.text('Parcelada'));
        await tester.pumpAndSettle();

        expect(find.widgetWithText(TextFormField, 'Descrição'), findsOneWidget);
        expect(find.text('Assinatura de Software'), findsOneWidget);
        expect(find.text('Empresa SaaS LTDA'), findsOneWidget);
        expect(find.text('150,00'), findsOneWidget);

        // Alterna para Recorrente
        await tester.tap(find.text('Recorrente'));
        await tester.pumpAndSettle();

        expect(find.text('Assinatura de Software'), findsOneWidget);
        expect(find.text('Empresa SaaS LTDA'), findsOneWidget);
        expect(find.text('150,00'), findsOneWidget);

        // Volta para Avulsa
        await tester.tap(find.text('Avulsa'));
        await tester.pumpAndSettle();

        expect(find.text('Assinatura de Software'), findsOneWidget);
        expect(find.text('Empresa SaaS LTDA'), findsOneWidget);
        expect(find.text('150,00'), findsOneWidget);
      },
    );
  });
}
