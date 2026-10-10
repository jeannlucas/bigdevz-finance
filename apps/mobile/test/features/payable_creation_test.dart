import 'dart:async';
import 'dart:convert';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/agreements/receipt_attempt.dart'
    show ReceiptAttemptState, UncertainReason;
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:bigdevz_finance/features/payables/payable_creations.dart';
import 'package:bigdevz_finance/features/payables/payable_form_screen.dart';
import 'package:bigdevz_finance/features/payables/payables_repository.dart';
import 'package:bigdevz_finance/features/payables/payables_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';
import '../support/fake_payables_api.dart';
import '../support/fake_receipts_api.dart' show Delivery;
import 'receipt_attempts_test.dart' show FlakyStorage;

const pf = Space(id: 1, kind: 'PF', name: 'Pessoal');

// Contra a API simulada (decisão por chave como na API Laravel). Atomicidade,
// replay e concorrência reais: PayableCreationRecoveryTest e
// ConcurrentPaymentsTest em PostgreSQL.
void main() {
  late FakePayablesApi fake;
  late FlakyStorage storage;

  PayableCreations service() => PayableCreations(
    repository: PayablesRepository(
      ApiClient(baseUrl: 'http://api.test/api', client: fake.client),
    ),
    storage: storage,
  );

  List<String> createKeys() => [
    for (final r in fake.writes.where((r) => r.url.path.endsWith('/payables')))
      r.headers['Idempotency-Key']!,
  ];
  Set<String> createBodies() => {
    for (final r in fake.writes.where((r) => r.url.path.endsWith('/payables')))
      r.body,
  };
  int count(String description) =>
      fake.payables.values.where((p) => p.description == description).length;

  setUp(() {
    fake = FakePayablesApi();
    storage = FlakyStorage();
  });

  group('serviço', () {
    const single = {
      'kind': 'single',
      'description': 'Conserto IT',
      'payee': null,
      'amount': '300.00',
      'due_date': '2026-03-20',
    };

    test('falha ao guardar não envia nada', () async {
      storage.failWrites = true;
      await expectLater(service().submit(1, 1, single), throwsStateError);
      expect(fake.writes, isEmpty);
    });

    test('nunca chegou: a verificação conclui uma única vez', () async {
      fake.script.add(Delivery.dropBeforeServer);
      final first = await service().submit(1, 1, single);
      expect(first.state, ReceiptAttemptState.uncertain);
      expect(count('Conserto IT'), 0);
      final resolved = await service().resolve(first.pending);
      expect(resolved.replayed, isFalse);
      expect(count('Conserto IT'), 1);
      expect(createKeys().toSet(), hasLength(1));
    });

    test('verificação que falha de novo mantém pendente; 401/409/422 sem decisão também', () async {
      fake.script.addAll([
        Delivery.loseResponse,
        Delivery.serverError,
        Delivery.unauthorized,
        Delivery.conflict,
        Delivery.unrecordedRejection,
      ]);
      final first = await service().submit(1, 1, single);
      for (final reason in [
        UncertainReason.server,
        UncertainReason.unauthorized,
        UncertainReason.conflict,
        UncertainReason.server,
      ]) {
        final outcome = await service().resolve(first.pending);
        expect(outcome.state, ReceiptAttemptState.uncertain);
        expect(outcome.reason, reason);
        expect(await service().pending(1, 1), isNotNull);
      }
      expect(
        (await service().resolve(first.pending)).message,
        startsWith('Cadastro já estava registrado'),
      );
      expect(count('Conserto IT'), 1);
      expect(createKeys().toSet(), hasLength(1));
      expect(createBodies(), hasLength(1));
    });

    test('recusa registrada libera; nova tentativa usa chave nova', () async {
      final refused = await service().submit(1, 1, {
        ...single,
        'amount': '0.01',
      });
      expect(refused.state, ReceiptAttemptState.rejected);
      expect(await service().pending(1, 1), isNull);
      final next = await service().submit(1, 1, single);
      expect(next.state, ReceiptAttemptState.confirmed);
      expect(createKeys().toSet(), hasLength(2));
    });

    test('app fechado após sucesso remoto, antes da limpeza local', () async {
      storage.failDeletes = true;
      final done = await service().submit(1, 1, single);
      expect(done.state, ReceiptAttemptState.confirmed);
      storage.failDeletes = false;
      final pending = (await service().pending(1, 1))!;
      final resolved = await service().resolve(pending);
      expect(resolved.replayed, isTrue);
      expect(resolved.payables.single.id, done.payables.single.id);
      expect(count('Conserto IT'), 1);
      expect(await service().pending(1, 1), isNull);
    });

    test(
      'cadastro pendente bloqueia outro no espaço, não em outro usuário/espaço',
      () async {
        fake.script.add(Delivery.loseResponse);
        final first = await service().submit(1, 1, single);
        final blocked = await service().submit(1, 1, {
          ...single,
          'description': 'Outra',
        });
        expect(blocked.pending.idempotencyKey, first.pending.idempotencyKey);
        expect(count('Outra'), 0);
        expect(await service().pending(2, 1), isNull);
        expect(await service().pending(1, 2), isNull);
        final simultaneous = await Future.wait([
          service().resolve(first.pending),
          service().resolve(first.pending),
        ]);
        expect(simultaneous.map((o) => o.state).toSet(), {
          ReceiptAttemptState.confirmed,
        });
        expect(count('Conserto IT'), 1);
      },
    );
  });

  group('telas', () {
    Future<void> pump(
      WidgetTester tester,
      Widget home, {
      int userId = 1,
      double height = 2532,
    }) async {
      tester.view.physicalSize = Size(1170, height);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final client = ApiClient(
        baseUrl: 'http://api.test/api',
        client: fake.client,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider.value(value: PayablesRepository(client)),
            Provider(
              create: (context) => PayableCreations(
                repository: context.read<PayablesRepository>(),
                storage: storage,
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
          child: MaterialApp(home: Scaffold(body: home)),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder scrollable() => find.byType(Scrollable).first;

    Future<void> tapText(WidgetTester tester, String text) async {
      final target = find.text(text);
      if (target.evaluate().isEmpty) {
        for (var i = 0; i < 20 && target.evaluate().isEmpty; i++) {
          await tester.drag(
            scrollable(),
            const Offset(0, -300),
            warnIfMissed: false,
          );
          await tester.pumpAndSettle();
        }
      }
      if (target.evaluate().isNotEmpty) {
        await tester.ensureVisible(target.last);
        await tester.pumpAndSettle();
        await tester.tap(target.last, warnIfMissed: false);
        await tester.pumpAndSettle();
      }
    }

    /// O botão de confirmar, rolando a lista até ele se ainda não foi construído.
    Future<FilledButton> button(WidgetTester tester, String label) async {
      final btnFinder = find.widgetWithText(FilledButton, label);
      for (var i = 0; i < 20 && btnFinder.evaluate().isEmpty; i++) {
        await tester.drag(
          scrollable(),
          const Offset(0, -300),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
      }
      if (btnFinder.evaluate().isNotEmpty) {
        await tester.ensureVisible(btnFinder.last);
        await tester.pumpAndSettle();
        return tester.widget<FilledButton>(btnFinder.last);
      }
      for (var i = 0; i < 20 && btnFinder.evaluate().isEmpty; i++) {
        await tester.drag(
          scrollable(),
          const Offset(0, 300),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
      }
      if (btnFinder.evaluate().isNotEmpty) {
        await tester.ensureVisible(btnFinder.last);
        await tester.pumpAndSettle();
        return tester.widget<FilledButton>(btnFinder.last);
      }
      throw StateError('Botão "$label" não encontrado');
    }

    Future<void> fill(
      WidgetTester tester,
      String description,
      String cents,
    ) async {
      final descField = find.widgetWithText(TextFormField, 'Descrição');
      if (descField.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          descField,
          -200,
          scrollable: scrollable(),
          maxScrolls: 50,
        );
      }
      await tester.ensureVisible(descField.last);
      await tester.pumpAndSettle();
      await tester.enterText(descField.last, description);

      final valField = find.byWidgetPredicate(
        (w) => w is TextField && (w.decoration?.prefixText == r'R$ '),
      );
      if (valField.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          valField,
          -200,
          scrollable: scrollable(),
          maxScrolls: 50,
        );
      }
      await tester.ensureVisible(valField.last);
      await tester.pumpAndSettle();
      await tester.enterText(valField.last, cents);
      await tester.pump();
    }

    testWidgets('avulsa: resposta perdida, tela fechada e app recriado; outro usuário não vê; '
        'retomada usa a mesma chave e cria uma obrigação', (tester) async {
      fake.script.add(Delivery.loseResponse);
      await pump(
        tester,
        PayableFormScreen(space: pf, today: DateTime(2026, 3, 15)),
      );
      await fill(tester, 'Conserto IT', '30000');
      await tapText(tester, 'Salvar conta a pagar');
      expect(find.text('Cadastro aguardando confirmação'), findsOneWidget);
      expect(count('Conserto IT'), 1, reason: 'a API gravou');

      // App recriado com outro usuário: nada aparece.
      await pump(tester, const PayablesTab(space: pf), userId: 2);
      expect(find.text('Cadastro aguardando confirmação'), findsNothing);
      // O usuário original reabre: o formulário vira retomada obrigatória.
      await pump(
        tester,
        PayableFormScreen(space: pf, today: DateTime(2026, 3, 15)),
      );
      expect(find.text('Cadastro aguardando confirmação'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Descrição'), findsNothing);

      await pump(tester, const PayablesTab(space: pf));
      expect(find.textContaining('Conserto IT · Avulsa'), findsOneWidget);
      final gate = fake.hold = Completer<void>();
      await tester.tap(find.text('Verificar cadastro'));
      await tester.pump();
      // Segundo toque com a primeira verificação ainda pendente na rede simulada:
      final again = find.descendant(
        of: find.byKey(const ValueKey('pending-creation')),
        matching: find.byType(FilledButton),
      );
      expect(again, findsOneWidget);
      await tester.tap(again, warnIfMissed: false);
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        find.text('Cadastro já estava registrado: Conserto IT, 1 obrigação.'),
        findsOneWidget,
      );
      expect(count('Conserto IT'), 1);
      expect(
        createKeys(),
        hasLength(2),
        reason: 'primeiro envio + verificação (segundo toque durante o envio foi ignorado)',
      );
      expect(createKeys().toSet(), hasLength(1));
      expect(createBodies(), hasLength(1));
      expect(find.text('Cadastro aguardando confirmação'), findsNothing);
    });

    testWidgets('recorrente no passado: revisão mostra período e vencidas, exige confirmação '
        'e a retomada cria o conjunto aprovado uma vez', (tester) async {
      fake.script.add(Delivery.loseResponse);
      await pump(
        tester,
        PayableFormScreen(space: pf, today: DateTime(2026, 1, 10)),
      );
      await tapText(tester, 'Recorrente');
      await fill(tester, 'Aluguel IT', '150000');
      expect(
        (await button(tester, 'Confirmar recorrência')).onPressed,
        isNull,
        reason: 'sem revisão',
      );

      await tapText(tester, 'Revisar ocorrências');
      expect(find.text('15 · total R\$ 22.500,00'), findsOneWidget);
      expect(find.text('10/01/2026 a 10/03/2027'), findsOneWidget);
      expect(
        find.textContaining('3 ocorrências já venceram (total R\$ 4.500,00)'),
        findsOneWidget,
      );
      expect(
        (await button(tester, 'Confirmar recorrência')).onPressed,
        isNull,
        reason: 'falta confirmar as vencidas',
      );
      await tapText(tester, 'Confirmo a criação das 3 ocorrências vencidas');

      // Mudar o valor invalida a revisão.
      await fill(tester, 'Aluguel IT', '160000');
      expect((await button(tester, 'Confirmar recorrência')).onPressed, isNull);
      await fill(tester, 'Aluguel IT', '150000');
      await tapText(tester, 'Revisar ocorrências');
      await tapText(tester, 'Confirmo a criação das 3 ocorrências vencidas');
      await tapText(tester, 'Confirmar recorrência');
      expect(find.text('Cadastro aguardando confirmação'), findsOneWidget);

      await pump(tester, const PayablesTab(space: pf));
      await tapText(tester, 'Verificar cadastro');
      expect(
        find.text('Cadastro já estava registrado: Aluguel IT, 15 obrigações.'),
        findsOneWidget,
      );
      expect(count('Aluguel IT'), 15);
      final sent = jsonDecode(fake.writes.last.body) as Map<String, dynamic>;
      expect(sent['approved_until'], '2027-03-01');
      expect(sent['confirm_past'], isTrue);
      expect(createKeys().toSet(), hasLength(1));
    });
  });
}
