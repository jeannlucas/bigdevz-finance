import 'dart:convert';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/accounts/account.dart';
import 'package:bigdevz_finance/features/accounts/account_card.dart';
import 'package:bigdevz_finance/features/accounts/account_form_screen.dart';
import 'package:bigdevz_finance/features/accounts/account_screen.dart';
import 'package:bigdevz_finance/features/accounts/accounts_repository.dart';
import 'package:bigdevz_finance/features/accounts/accounts_tab.dart';
import 'package:bigdevz_finance/features/accounts/bank_catalog.dart';
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
    Future<void> pump(
      WidgetTester tester,
      Widget home, {
      Size? physicalSize,
    }) async {
      tester.view.physicalSize = physicalSize ?? const Size(1170, 2532);
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

    testWidgets(
      'AccountCard: privacidade semântica oculta saldo no leitor de tela quando obscureBalance=true',
      (tester) async {
        final account = Account(
          id: 1,
          name: 'Nubank Principal',
          balance: Money.parse('1500.00'),
          openingBalance: Money.parse('1000.00'),
          openingBalanceDate: '2026-01-01',
        );

        // Caso 1: Saldo mascarado (obscureBalance = true)
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AccountCard(
                space: pf,
                account: account,
                obscureBalance: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Nó semântico deve anunciar "saldo oculto" e não o valor real
        expect(
          find.bySemanticsLabel('Conta Nubank Principal, saldo oculto'),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel(RegExp(r'1\.500,00')), findsNothing);

        // Caso 2: Saldo visível (obscureBalance = false)
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AccountCard(
                space: pf,
                account: account,
                obscureBalance: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.bySemanticsLabel('Conta Nubank Principal, saldo R\$ 1.500,00'),
          findsOneWidget,
        );

        // Caso 3: Ação acessível de toque (onTap) preservada no nó semântico
        var tapped = false;
        final semantics = tester.semantics;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AccountCard(
                space: pf,
                account: account,
                onTap: () => tapped = true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final nodeFinder = find.bySemanticsLabel(
          'Conta Nubank Principal, saldo R\$ 1.500,00',
        );
        expect(nodeFinder, findsOneWidget);
        semantics.tap(
          find.semantics.byLabel('Conta Nubank Principal, saldo R\$ 1.500,00'),
        );
        expect(
          tapped,
          isTrue,
          reason: 'SemanticsAction.tap deve disparar o callback onTap do nó acessível',
        );
      },
    );

    const widths = <double>[320, 375, 402];
    const scales = <double>[1.0, 1.5, 2.0];

    for (final width in widths) {
      for (final scale in scales) {
        testWidgets(
          'AccountsTab: painel executivo ${width.toInt()}pt escala ${(scale * 100).toInt()}% sem overflow',
          (tester) async {
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            await pump(
              tester,
              const AccountsTab(space: pf),
              physicalSize: Size(width * 3, 812 * 3),
            );
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            expect(find.text('Carteira de Contas'), findsOneWidget);
            expect(find.text('Nova conta'), findsOneWidget);
            expect(
              find.byKey(const ValueKey('accounts-total')),
              findsOneWidget,
            );
          },
        );
      }
    }

    testWidgets(
      'AccountCard no consumidor compartilhado (AccountScreen) sem regressão em 200%',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pump(
          tester,
          const AccountScreen(space: pf, accountId: 7),
          physicalSize: const Size(375 * 3, 812 * 3),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(AccountCard), findsOneWidget);
        expect(find.text('Saldo disponível'), findsOneWidget);
      },
    );

    test('BankCatalog: identifica bancos brasileiros corretamente a partir do nome ou ID', () {
      expect(BankCatalog.findByAccountName('Nubank PF')?.id, 'nubank');
      expect(BankCatalog.findByAccountName('Itaú Unibanco')?.id, 'itau');
      expect(BankCatalog.findByAccountName('Banco Bradesco')?.id, 'bradesco');
      expect(BankCatalog.findByAccountName('Banco do Brasil PJ')?.id, 'bb');
      expect(
        BankCatalog.findByAccountName('Caixa Econômica Federal')?.id,
        'caixa',
      );
      expect(BankCatalog.findByAccountName('Santander')?.id, 'santander');
      expect(BankCatalog.findByAccountName('Banco Inter PJ')?.id, 'inter');
      expect(BankCatalog.findByAccountName('Sicoob')?.id, 'sicoob');
      expect(BankCatalog.findByAccountName('Sicredi')?.id, 'sicredi');
      expect(BankCatalog.findByAccountName('Mercado Pago')?.id, 'mercadopago');
      expect(BankCatalog.findByAccountName('C6 Bank')?.id, 'c6');
      expect(BankCatalog.findByAccountName('BTG Pactual')?.id, 'btg');
      expect(BankCatalog.findByAccountName('PicPay')?.id, 'picpay');
      expect(BankCatalog.findByAccountName('PagBank')?.id, 'pagbank');
      expect(
        BankCatalog.findByAccountName('Dinheiro em Espécie')?.id,
        'dinheiro',
      );
      expect(BankCatalog.findByAccountName('Carteira Física')?.id, 'dinheiro');
      expect(BankCatalog.findByAccountName('Conta Desconhecida XYZ'), isNull);
      expect(BankCatalog.findById('nubank')?.name, 'Nubank');
    });

    testWidgets(
      'AccountsTab: estado vazio exibe botão para cadastrar primeira conta e navega para formulário',
      (tester) async {
        fake.accounts.clear();
        await pump(tester, const AccountsTab(space: pf));
        await tester.pumpAndSettle();

        expect(find.text('Nenhuma conta neste espaço'), findsOneWidget);
        final createBtn = find.byKey(
          const ValueKey('accounts_empty_create_button'),
        );
        expect(createBtn, findsOneWidget);
        expect(find.text('Cadastrar primeira conta'), findsOneWidget);

        await tester.tap(createBtn);
        await tester.pumpAndSettle();

        expect(find.text('Passo 1 de 3: Escolha o Banco'), findsOneWidget);
        expect(find.text('Selecione a sua instituição'), findsOneWidget);
        expect(find.text('Nubank'), findsOneWidget);
        expect(find.text('Itaú'), findsOneWidget);
      },
    );

    testWidgets(
      'AccountCard: renderiza logo oficial para conta reconhecida no catálogo e tipo de conta',
      (tester) async {
        final account = Account(
          id: 1,
          name: 'Nubank - Poupança',
          balance: Money.parse('2500.00'),
          openingBalance: Money.parse('1000.00'),
          openingBalanceDate: '2026-01-01',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AccountCard(space: pf, account: account),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Image &&
                widget.image is AssetImage &&
                (widget.image as AssetImage).assetName ==
                    'assets/banks/nubank.png',
          ),
          findsOneWidget,
        );
        expect(find.text('Nubank · Poupança · PF'), findsOneWidget);
      },
    );

    testWidgets(
      'AccountFormScreen: wizard em 3 passos seleciona banco e modalidade sugerindo nome',
      (tester) async {
        await pump(
          tester,
          const AccountFormScreen(space: pf),
          physicalSize: const Size(800 * 3, 1200 * 3),
        );

        String getNameFieldText() {
          final field = tester.widget<TextFormField>(
            find.byKey(const ValueKey('account_name_field')),
          );
          return field.controller?.text ?? '';
        }

        expect(find.text('Passo 1 de 3: Escolha o Banco'), findsOneWidget);

        // Passo 1: Tocar no banco Nubank avança para o Passo 2
        await tester.tap(find.text('Nubank'));
        await tester.pumpAndSettle();

        expect(find.text('Passo 2 de 3: Modalidade da Conta'), findsOneWidget);
        expect(find.text('Nubank selecionado'), findsOneWidget);

        // Passo 2: Selecionar Poupança avança para o Passo 3
        await tester.tap(find.text('Conta Poupança'));
        await tester.pumpAndSettle();

        expect(find.text('Passo 3 de 3: Saldo e Confirmação'), findsOneWidget);
        expect(getNameFieldText(), 'Nubank - Poupança');
        expect(find.text('Pré-visualização do Cartão'), findsOneWidget);

        // Voltar para o Passo 2
        await tester.tap(find.byTooltip('Voltar'));
        await tester.pumpAndSettle();

        expect(find.text('Passo 2 de 3: Modalidade da Conta'), findsOneWidget);

        // Selecionar Salário
        await tester.tap(find.text('Conta Salário'));
        await tester.pumpAndSettle();

        expect(find.text('Passo 3 de 3: Saldo e Confirmação'), findsOneWidget);
        expect(getNameFieldText(), 'Nubank - Salário');
      },
    );

    testWidgets(
      'AccountsTab: na lista Todas as contas renderiza logo do banco e subtítulo com modalidade',
      (tester) async {
        fake.seed(7, 50000, '2026-03-10');
        fake.accounts[7]!.name = 'Banco do Brasil - Corrente';
        await pump(tester, const AccountsTab(space: pf));
        await tester.pumpAndSettle();

        expect(find.text('Todas as contas'), findsOneWidget);
        expect(find.text('Banco do Brasil - Corrente'), findsWidgets);
        expect(find.text('Corrente · Saldo disponível'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Image &&
                widget.image is AssetImage &&
                (widget.image as AssetImage).assetName == 'assets/banks/bb.png',
          ),
          findsWidgets,
        );
      },
    );

    testWidgets(
      'AccountsTab: em desktop exibe painel executivo com saldo total e remove botão Empréstimos do cabeçalho',
      (tester) async {
        fake.seed(7, 50000, '2026-03-10');
        await pump(
          tester,
          const AccountsTab(space: pf),
          physicalSize: const Size(1200 * 3, 800 * 3),
        );
        await tester.pumpAndSettle();

        // Não deve ter o botão 'Empréstimos' no cabeçalho de contas
        expect(
          find.byKey(const ValueKey('accounts_tab_loans_button')),
          findsNothing,
        );

        // Deve exibir o painel executivo consolidado
        expect(find.text('Carteira de Contas'), findsOneWidget);
        expect(find.byKey(const ValueKey('accounts-total')), findsOneWidget);
        expect(find.text('Todas as contas'), findsOneWidget);
        expect(find.text('Nova conta'), findsOneWidget);
      },
    );
  });
}
