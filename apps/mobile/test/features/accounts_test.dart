import 'dart:convert';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/accounts/account.dart';
import 'package:bigdevz_finance/features/accounts/accounts_repository.dart';
import 'package:bigdevz_finance/features/accounts/accounts_tab.dart';
import 'package:bigdevz_finance/features/accounts/opening_adjustments.dart';
import 'package:bigdevz_finance/features/agreements/agreements_repository.dart';
import 'package:bigdevz_finance/features/agreements/installment_screen.dart';
import 'package:bigdevz_finance/features/agreements/receipt_attempts.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';
import '../support/fake_receipts_api.dart';

const pf = Space(id: 1, kind: 'PF', name: 'Pessoal');

// Contra a API simulada (mesmas regras de chave, abertura e arquivamento da
// API Laravel). Persistência e concorrência reais: testes PHP em PostgreSQL.
void main() {
  late FakeReceiptsApi fake;
  late MemorySessionStorage storage;

  ApiClient api() =>
      ApiClient(baseUrl: 'http://api.test/api', client: fake.client);

  setUp(() {
    fake = FakeReceiptsApi();
    storage = MemorySessionStorage();
  });

  group('serviços', () {
    OpeningAdjustments openings() => OpeningAdjustments(
      repository: AccountsRepository(api()),
      storage: storage,
    );

    Future<Account> account(int id) => AccountsRepository(api()).find(1, id);

    test(
      'correção de abertura com resposta perdida aplica a diferença uma vez',
      () async {
        fake.seed(7, 50000, '2026-03-10');
        fake.script.add(Delivery.loseResponse);
        final service = openings();
        final first = await service.submit(
          userId: 1,
          spaceId: 1,
          account: await account(7),
          openingBalance: Money.parse('1200.00'),
          openingDate: '2026-01-01',
          reason: 'Saldo digitado errado',
        );
        expect(first.state, ReceiptAttemptState.uncertain);
        expect(fake.balanceCents, 170000, reason: 'a API aplicou +R\$ 200,00');

        // App reaberto: mesma chave e conteúdo restaurados e verificados.
        final reopened = openings();
        expect(
          await reopened.pending(2, 1, 7),
          isNull,
          reason: 'outro usuário',
        );
        expect(await reopened.pending(1, 2, 7), isNull, reason: 'outro espaço');
        final restored = (await reopened.pending(1, 1, 7))!;
        expect(restored.toJson(), first.attempt.toJson());
        final resolved = await reopened.resolve(restored);
        expect(resolved.state, ReceiptAttemptState.confirmed);
        expect(resolved.replayed, isTrue);
        expect(fake.balanceCents, 170000, reason: 'diferença aplicada uma vez');
        expect(fake.accounts[7]!.adjustments, hasLength(1));
        expect(
          fake.receiptRequests.map((r) => r.headers['Idempotency-Key']).toSet(),
          hasLength(1),
        );
        expect(await reopened.pending(1, 1, 7), isNull);
      },
    );

    test(
      'data depois da primeira movimentação: recusa registrada libera',
      () async {
        fake.seed(7, 50000, '2026-03-10');
        final outcome = await openings().submit(
          userId: 1,
          spaceId: 1,
          account: await account(7),
          openingBalance: Money.parse('1000.00'),
          openingDate: '2026-03-11',
          reason: 'Data',
        );
        expect(outcome.state, ReceiptAttemptState.rejected);
        expect(outcome.error!.fieldErrors, contains('opening_balance_date'));
        expect(fake.accounts[7]!.openingDate, '2026-01-01');
        expect(await openings().pending(1, 1, 7), isNull);
      },
    );

    test('422 sem decisão registrada mantém a correção pendente', () async {
      fake.script.add(Delivery.unrecordedRejection);
      final service = openings();
      final outcome = await service.submit(
        userId: 1,
        spaceId: 1,
        account: await account(7),
        openingBalance: Money.parse('900.00'),
        openingDate: '2026-01-01',
        reason: 'Ajuste',
      );
      expect(outcome.state, ReceiptAttemptState.uncertain);
      expect(await service.pending(1, 1, 7), isNotNull);
    });

    test(
      'tentativa incerta de recebimento em conta arquivada depois: recusa '
      'registrada, sem execução; concluída antes do arquivamento: replay',
      () async {
        final attempts = ReceiptAttempts(
          repository: AgreementsRepository(api()),
          storage: storage,
        );
        Future<ReceiptAttemptOutcome> submit(String amount) => attempts.submit(
          userId: 1,
          spaceId: 1,
          installmentId: 22,
          accountId: 7,
          accountName: 'Banco PF',
          amount: Money.parse(amount),
          receivedOn: '2026-03-10',
          kind: ReceiptKind.partial,
        );

        // Concluída antes; a resposta se perdeu; conta arquivada depois.
        fake.script.add(Delivery.loseResponse);
        final done = await submit('500.00');
        fake.accounts[7]!.archived = true;
        final replay = await attempts.resolve(done.attempt);
        expect(replay.state, ReceiptAttemptState.confirmed);
        expect(replay.replayed, isTrue);
        expect(fake.receipts, hasLength(1));

        // Nunca chegou; conta arquivada antes da verificação.
        fake.script.add(Delivery.dropBeforeServer);
        final lost = await submit('300.00');
        expect(lost.state, ReceiptAttemptState.uncertain);
        final resolved = await attempts.resolve(lost.attempt);
        expect(resolved.state, ReceiptAttemptState.rejected);
        expect(
          resolved.error!.fieldErrors['account_id'],
          contains('arquivada'),
        );
        expect(fake.receipts, hasLength(1));
        expect(fake.balanceCents, 150000);

        // Reativar não faz a chave recusada valer.
        fake.accounts[7]!.archived = false;
        final late = await attempts.resolve(lost.attempt);
        expect(late.state, ReceiptAttemptState.rejected);
        expect(fake.receipts, hasLength(1));
      },
    );
  });

  group('telas', () {
    Future<void> pump(WidgetTester tester, Widget home) async {
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
            Provider(
              create: (context) => ReceiptAttempts(
                repository: context.read<AgreementsRepository>(),
                storage: storage,
              ),
            ),
            Provider(
              create: (context) => OpeningAdjustments(
                repository: context.read<AccountsRepository>(),
                storage: storage,
              ),
            ),
            ChangeNotifierProvider(
              create: (_) => SessionController(
                api: client,
                auth: AuthRepository(client),
                storage: MemorySessionStorage(),
              )..user = const AppUser(id: 1, name: 'P', email: 'p@example.com'),
            ),
          ],
          child: MaterialApp(home: Scaffold(body: home)),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tapText(WidgetTester tester, String text) async {
      await tester.ensureVisible(find.text(text).last);
      await tester.pump();
      await tester.tap(find.text(text).last);
      await tester.pumpAndSettle();
    }

    Finder line(String id, String text) => find.descendant(
      of: find.byKey(ValueKey('opening-$id')),
      matching: find.text(text),
    );

    List<String> writes() => fake.requests
        .where((r) => r.method != 'GET')
        .map((r) => '${r.method} ${r.url.path}')
        .toList();

    testWidgets(
      'editar nome: cancelar não grava; salvar mantém a mesma conta',
      (tester) async {
        fake.seed(7, 50000, '2026-03-10');
        await pump(tester, const AccountsTab(space: pf));
        expect(find.text(r'Saldo total: R$ 1.500,00'), findsOneWidget);
        await tapText(tester, 'Banco PF');
        await tapText(tester, 'Editar conta');
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Nome da conta'),
          'Banco Novo',
        );
        await tapText(tester, 'Cancelar');
        expect(writes(), isEmpty);

        await tapText(tester, 'Editar conta');
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Nome da conta'),
          'Banco Novo',
        );
        await tapText(tester, 'Salvar alterações');
        expect(find.text('Conta atualizada.'), findsOneWidget);
        expect(find.text('Banco Novo'), findsWidgets);
        expect(writes(), ['PATCH /api/spaces/1/accounts/7']);
        expect(
          jsonDecode(
            fake.requests.singleWhere((r) => r.method == 'PATCH').body,
          ),
          {'name': 'Banco Novo'},
        );
        expect(fake.balanceCents, 150000);
      },
    );

    testWidgets(
      'corrigir abertura: revisão com antes/depois e saldo resultante; voltar '
      'não grava; confirmar registra no histórico',
      (tester) async {
        fake.seed(7, 50000, '2026-03-10');
        await pump(tester, const AccountsTab(space: pf));
        await tapText(tester, 'Banco PF');
        await tapText(tester, 'Corrigir abertura');
        expect(
          find.textContaining('10/03/2026, data da primeira movimentação'),
          findsOneWidget,
        );

        await tapText(tester, 'Revisar correção da abertura');
        expect(
          find.text('Altere o saldo inicial ou a data de abertura.'),
          findsOneWidget,
        );
        expect(
          find.text('Informe o motivo (pelo menos 3 caracteres).'),
          findsOneWidget,
        );

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Saldo inicial correto'),
          '120000',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Motivo'),
          'Saldo do extrato',
        );
        await tapText(tester, 'Revisar correção da abertura');
        expect(
          line('Saldo-inicial', r'R$ 1.000,00 → R$ 1.200,00'),
          findsOneWidget,
        );
        expect(line('Data', '01/01/2026 → 01/01/2026'), findsOneWidget);
        expect(
          line('Saldo-atual', r'R$ 1.500,00 → R$ 1.700,00'),
          findsOneWidget,
        );
        expect(line('Diferenca', r'+R$ 200,00'), findsOneWidget);

        await tapText(tester, 'Voltar e corrigir');
        expect(writes(), isEmpty);
        await tapText(tester, 'Revisar correção da abertura');
        await tapText(tester, 'Confirmar correção');
        expect(find.text('Abertura corrigida.'), findsOneWidget);
        expect(find.text(r'R$ 1.000,00 → R$ 1.200,00'), findsOneWidget);
        expect(find.textContaining('Motivo: Saldo do extrato'), findsOneWidget);
        expect(fake.balanceCents, 170000);
        expect(fake.receipts, hasLength(1), reason: 'não vira recebimento');
      },
    );

    testWidgets(
      'correção de abertura incerta: travada, sobrevive à reabertura e se '
      'resolve uma vez',
      (tester) async {
        fake.script.add(Delivery.loseResponse);
        await pump(tester, const AccountsTab(space: pf));
        await tapText(tester, 'Banco PF');
        await tapText(tester, 'Corrigir abertura');
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Saldo inicial correto'),
          '90000',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Motivo'),
          'Ajuste',
        );
        await tapText(tester, 'Revisar correção da abertura');
        await tapText(tester, 'Confirmar correção');
        expect(find.text('Correção não confirmada'), findsOneWidget);
        expect(find.text('Voltar e corrigir'), findsNothing);
        await tapText(tester, 'Verificar depois');
        expect(find.text('Corrigir abertura'), findsNothing);
        expect(find.text('Verificar correção da abertura'), findsOneWidget);

        await pump(tester, const AccountsTab(space: pf));
        await tapText(tester, 'Banco PF');
        await tapText(tester, 'Verificar correção da abertura');
        await tester.tap(find.text('Verificar correção'));
        await tester.pump();
        await tester.tap(find.byType(FilledButton).last, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(
          find.text('Correção da abertura já estava registrada.'),
          findsOneWidget,
        );
        expect(fake.balanceCents, 90000);
        expect(fake.accounts[7]!.adjustments, hasLength(1));
        expect(fake.receiptRequests, hasLength(2));
      },
    );

    testWidgets(
      'arquivar: confirmação, saldo no total, fora dos destinos; reativar volta',
      (tester) async {
        fake.seed(7, 50000, '2026-03-10');
        await pump(tester, const AccountsTab(space: pf));
        await tapText(tester, 'Banco PF');
        await tapText(tester, 'Arquivar conta');
        expect(find.text('Arquivar conta?'), findsOneWidget);
        await tapText(tester, 'Cancelar');
        expect(writes(), isEmpty);

        await tapText(tester, 'Arquivar conta');
        await tapText(tester, 'Arquivar');
        expect(find.text('Conta arquivada.'), findsOneWidget);
        expect(find.text('Arquivada'), findsOneWidget);
        expect(fake.balanceCents, 150000, reason: 'arquivar não muda dinheiro');

        await pump(tester, const AccountsTab(space: pf));
        expect(find.text(r'Saldo total: R$ 1.500,00'), findsOneWidget);
        expect(find.textContaining('1 ativa · 1 arquivada'), findsOneWidget);
        expect(find.text('Arquivadas'), findsOneWidget);

        // Destinos de operações novas: só a conta ativa.
        await pump(
          tester,
          const InstallmentScreen(space: pf, installmentId: 22),
        );
        await tapText(tester, 'Registrar recebimento');
        await tester.tap(find.byType(DropdownButtonFormField<int>));
        await tester.pumpAndSettle();
        expect(find.text('Reserva PF'), findsWidgets);
        expect(find.text('Banco PF'), findsNothing);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        // Histórico preservado com o nome da conta arquivada.
        expect(find.textContaining('Banco PF'), findsOneWidget);

        await pump(tester, const AccountsTab(space: pf));
        await tapText(tester, 'Banco PF');
        await tapText(tester, 'Reativar conta');
        await tapText(tester, 'Reativar');
        expect(find.text('Conta reativada.'), findsOneWidget);
        expect(fake.accounts[7]!.archived, isFalse);
      },
    );

    testWidgets(
      'alinhamento da carteira: 1 conta e múltiplas contas mantêm Saldo total na mesma posição',
      (tester) async {
        // Cenário 1: 1 conta única (PJ ou PF)
        fake.seed(10, 500000, '2026-01-01');
        await pump(tester, const AccountsTab(space: pf));
        expect(find.byKey(const ValueKey('accounts-total')), findsOneWidget);
        final posSingle = tester.getTopLeft(
          find.byKey(const ValueKey('accounts-total')),
        );

        // Cenário 2: Múltiplas contas (carrossel com indicadores)
        fake.seed(11, 200000, '2026-01-01');
        await pump(tester, const AccountsTab(space: pf));
        expect(find.byKey(const ValueKey('accounts-total')), findsOneWidget);
        final posMultiple = tester.getTopLeft(
          find.byKey(const ValueKey('accounts-total')),
        );

        // Posição Y deve ser idêntica na mesma escala e largura
        expect(posSingle.dy, equals(posMultiple.dy));
      },
    );
  });
}
