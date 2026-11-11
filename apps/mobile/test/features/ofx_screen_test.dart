import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/accounts/account.dart';
import 'package:bigdevz_finance/features/accounts/accounts_repository.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/reconciliation/ofx_models.dart';
import 'package:bigdevz_finance/features/reconciliation/ofx_repository.dart';
import 'package:bigdevz_finance/features/reconciliation/ofx_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

class FakeOfxRepository extends OfxRepository {
  FakeOfxRepository({required this.parseResult})
    : super(ApiClient(baseUrl: 'http://example.com'));

  final OfxParseResult parseResult;
  bool reconcileCalled = false;

  @override
  Future<OfxParseResult> parseOfx({
    required int spaceId,
    required int accountId,
    required String ofxContent,
  }) async {
    return parseResult;
  }

  @override
  Future<Map<String, dynamic>> reconcile({
    required int spaceId,
    required int accountId,
    required List<Map<String, dynamic>> transactions,
  }) async {
    reconcileCalled = true;
    return {'reconciled_count': 1, 'ignored_count': 0};
  }
}

class FakeAccountsRepository extends AccountsRepository {
  FakeAccountsRepository() : super(ApiClient(baseUrl: 'http://example.com'));

  @override
  Future<List<Account>> list(int spaceId) async {
    return [
      const Account(
        id: 10,
        name: 'Itaú Principal',
        openingBalance: Money(100000),
        openingBalanceDate: '2026-01-01',
        balance: Money(500000),
      ),
    ];
  }
}

final fakeOfxResult = OfxParseResult(
  accountId: 10,
  accountName: 'Itaú Principal',
  transactionsCount: 2,
  alreadyReconciledCount: 1,
  transactions: [
    OfxTransactionItem(
      fitid: 'FIT-101',
      type: 'debit',
      amountCents: 25000,
      amount: const Money(25000),
      postedAt: '2026-11-10',
      memo: 'ELEKTRO ELETRICIDADE',
      alreadyReconciled: false,
      suggestedMatch: const OfxSuggestedMatch(
        type: 'payable',
        id: 5,
        title: 'Conta de Energia',
        amount: '250.00',
        dueDate: '2026-11-10',
        confidence: 'high',
      ),
    ),
    OfxTransactionItem(
      fitid: 'FIT-102',
      type: 'credit',
      amountCents: 80000,
      amount: const Money(80000),
      postedAt: '2026-11-09',
      memo: 'TED RECEBIDA',
      alreadyReconciled: true,
    ),
  ],
);

Widget buildTestWidget({required Space space, required OfxRepository repo}) {
  final client = MockClient((_) async => http.Response('{}', 200));
  final api = ApiClient(baseUrl: 'http://example.com', client: client);

  return MaterialApp(
    home: MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        Provider<AccountsRepository>(create: (_) => FakeAccountsRepository()),
        Provider<OfxRepository>.value(value: repo),
      ],
      child: OfxScreen(space: space, repository: repo),
    ),
  );
}

void main() {
  testWidgets(
    'OfxScreen: parses OFX, renders transactions, match suggestion and deduplication',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const space = Space(
        id: 1,
        kind: 'PJ',
        name: 'Empresa Teste',
        role: 'administrador',
      );
      final repo = FakeOfxRepository(parseResult: fakeOfxResult);

      await tester.pumpWidget(buildTestWidget(space: space, repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Conciliação Bancária OFX'), findsOneWidget);
      expect(find.text('Importação Manual de Extrato OFX'), findsOneWidget);
      expect(find.text('ITAÚ PRINCIPAL'), findsOneWidget);

      // Preenche campo de texto OFX
      await tester.enterText(
        find.byKey(const ValueKey('ofx-input')),
        '<OFX><STMTTRN><TRNAMT>-250.00</TRNAMT></STMTTRN></OFX>',
      );
      await tester.pump();

      // Clica para analisar extrato
      await tester.tap(find.text('Analisar Extrato OFX'));
      await tester.pumpAndSettle();

      // Transações renderizadas
      expect(find.text('Transações Encontradas (2)'), findsOneWidget);
      expect(find.text('1 já conciliadas'), findsOneWidget);
      expect(find.text('ELEKTRO ELETRICIDADE'), findsOneWidget);
      expect(find.text('-R\$ 250,00'), findsOneWidget);

      // Sugestão de correspondência
      expect(
        find.textContaining('Correspondência sugerida: CONTA DE ENERGIA'),
        findsOneWidget,
      );

      // Deduplicação (item já conciliado)
      expect(
        find.text('Transação já conciliada anteriormente (Deduplicada)'),
        findsOneWidget,
      );

      // Botão de confirmação manual
      final confirmBtn = find.text('Confirmar Conciliação Manual');
      expect(confirmBtn, findsOneWidget);

      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(repo.reconcileCalled, isTrue);
    },
  );
}
