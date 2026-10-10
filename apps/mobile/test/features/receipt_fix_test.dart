import 'dart:async';
import 'dart:convert';

import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/accounts/accounts_repository.dart';
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

// Telas contra a API simulada (mesma regra de chave da API Laravel).
// Persistência, transação e concorrência reais: testes PHP em PostgreSQL.
void main() {
  late FakeReceiptsApi fake;
  late MemorySessionStorage storage;
  late FakeReceipt original;

  Future<void> openApp(WidgetTester tester, {int userId = 1}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final api = ApiClient(baseUrl: 'http://api.test/api', client: fake.client);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider.value(value: AgreementsRepository(api)),
          Provider.value(value: AccountsRepository(api)),
          Provider(
            create: (context) => ReceiptAttempts(
              repository: context.read<AgreementsRepository>(),
              storage: storage,
            ),
          ),
          ChangeNotifierProvider(
            create: (_) => SessionController(
              api: api,
              auth: AuthRepository(api),
              storage: MemorySessionStorage(),
            )..user = AppUser(id: userId, name: 'P', email: 'p@example.com'),
          ),
        ],
        child: const MaterialApp(
          home: InstallmentScreen(space: pf, installmentId: 22),
        ),
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

  Future<void> openAction(WidgetTester tester, String action) async {
    await tester.tap(find.byTooltip('Ações do recebimento').first);
    await tester.pumpAndSettle();
    await tapText(tester, action);
  }

  Finder line(String id, String text) => find.descendant(
    of: find.byKey(ValueKey('fix-$id')),
    matching: find.textContaining(text),
  );

  setUp(() {
    fake = FakeReceiptsApi(installmentCents: 200000, balanceCents: 100000);
    // Recebimento de R$ 500,00 na conta errada, já confirmado.
    original = fake.seed(7, 50000, '2026-03-10');
    storage = MemorySessionStorage();
  });

  testWidgets(
    'correção mostra antes, depois e saldos; voltar não grava; confirmar '
    'move o recebimento sem mudar o restante',
    (tester) async {
      await openApp(tester);
      await openAction(tester, 'Corrigir recebimento');
      expect(
        find.textContaining(r'R$ 500,00 · Banco PF · 10/03/2026'),
        findsOneWidget,
      );

      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tapText(tester, 'Reserva PF');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo'),
        'Conta errada',
      );
      await tapText(tester, 'Revisar correção');

      expect(line('Antes-Conta', 'Banco PF'), findsOneWidget);
      expect(line('Depois-Conta', 'Reserva PF'), findsOneWidget);
      expect(
        line('Saldo-7', r'−R$ 500,00 · R$ 1.500,00 → R$ 1.000,00'),
        findsOneWidget,
      );
      expect(
        line('Saldo-8', r'+R$ 500,00 · R$ 0,00 → R$ 500,00'),
        findsOneWidget,
      );
      expect(line('Restante', r'R$ 1.500,00 → R$ 1.500,00'), findsOneWidget);
      expect(line('Motivo', 'Conta errada'), findsOneWidget);

      await tapText(tester, 'Voltar e corrigir');
      expect(find.text('Revisar correção'), findsOneWidget);
      expect(fake.receiptRequests, isEmpty, reason: 'cancelar não grava');

      await tapText(tester, 'Revisar correção');
      await tapText(tester, 'Confirmar correção');
      expect(
        find.textContaining(r'Correção confirmada: R$ 500,00 em Reserva PF'),
        findsOneWidget,
      );
      expect(jsonDecode(fake.receiptRequests.single.body), {
        'reason': 'Conta errada',
        'account_id': 8,
        'amount': '500.00',
        'received_on': '2026-03-10',
      });
      expect(fake.balanceCents, 100000);
      expect(fake.reserveCents, 50000);
      expect(fake.remainingCents, 150000);

      // Histórico: original corrigido e substituto identificado.
      expect(find.text('Corrigido'), findsOneWidget);
      expect(find.textContaining('Motivo: Conta errada'), findsOneWidget);
      expect(
        find.textContaining('Substitui um recebimento corrigido'),
        findsOneWidget,
      );
      expect(
        find.byTooltip('Ações do recebimento'),
        findsOneWidget,
        reason: 'só o substituto ativo tem ações',
      );
    },
  );

  testWidgets(
    'estorno com resposta perdida: travado, bloqueia a parcela, sobrevive à '
    'reabertura e se resolve uma única vez',
    (tester) async {
      fake.script.add(Delivery.loseResponse);
      await openApp(tester);
      await openAction(tester, 'Estornar recebimento');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo'),
        'Não recebido',
      );
      await tapText(tester, 'Revisar estorno');
      expect(
        line('Saldo-7', r'−R$ 500,00 · R$ 1.500,00 → R$ 1.000,00'),
        findsOneWidget,
      );
      expect(line('Restante', r'R$ 1.500,00 → R$ 2.000,00'), findsOneWidget);

      await tapText(tester, 'Confirmar estorno');
      expect(original.reversed, isTrue, reason: 'a API aplicou');
      expect(find.text('Estorno não confirmado'), findsOneWidget);
      expect(find.text('Voltar e corrigir'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);

      await tapText(tester, 'Verificar depois');
      expect(find.text('Estorno aguardando confirmação'), findsOneWidget);
      expect(find.text('Registrar recebimento'), findsNothing);
      expect(
        find.byTooltip('Ações do recebimento'),
        findsNothing,
        reason: 'nenhuma operação conflitante na parcela',
      );

      // Outro usuário no aparelho não vê; o original reabre e verifica.
      await openApp(tester, userId: 2);
      expect(find.text('Estorno aguardando confirmação'), findsNothing);
      await openApp(tester);
      expect(find.text('Estorno aguardando confirmação'), findsOneWidget);

      await tester.tap(find.text('Verificar recebimento'));
      await tester.pump();
      await tester.tap(find.text('Verificar recebimento'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          r'Estorno já estava registrado: R$ 500,00 de Banco PF',
        ),
        findsOneWidget,
      );
      expect(fake.receiptRequests, hasLength(2));
      expect(
        fake.receiptRequests.map((r) => r.headers['Idempotency-Key']).toSet(),
        hasLength(1),
      );
      expect(fake.balanceCents, 100000, reason: 'compensação uma vez');
      expect(find.text('Estornado'), findsOneWidget);
      expect(find.text('Registrar recebimento'), findsOneWidget);
      expect(await storage.read('pending_receipt.1.1.22'), isNull);
    },
  );

  testWidgets('motivo obrigatório e correção sem mudança não enviam nada', (
    tester,
  ) async {
    await openApp(tester);
    await openAction(tester, 'Corrigir recebimento');
    await tapText(tester, 'Revisar correção');
    expect(
      find.text('Informe o motivo (pelo menos 3 caracteres).'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Altere a conta, o valor ou a data. Para só desfazer, use Estornar.',
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Valor correto'),
      '200001',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Motivo'),
      'Valor',
    );
    await tapText(tester, 'Revisar correção');
    expect(find.text(r'Máximo após o estorno: R$ 2.000,00.'), findsOneWidget);
    expect(fake.receiptRequests, isEmpty);
  });

  testWidgets('valor menor na mesma conta: um envio por toque repetido', (
    tester,
  ) async {
    final gate = fake.hold = Completer<void>();
    await openApp(tester);
    await openAction(tester, 'Corrigir recebimento');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Valor correto'),
      '40000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Motivo'),
      'Valor errado',
    );
    await tapText(tester, 'Revisar correção');
    expect(
      line('Saldo-7', r'−R$ 100,00 · R$ 1.500,00 → R$ 1.400,00'),
      findsOneWidget,
    );
    expect(line('Restante', r'R$ 1.500,00 → R$ 1.600,00'), findsOneWidget);

    await tester.tap(find.text('Confirmar correção'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    expect(fake.receiptRequests, hasLength(1));
    gate.complete();
    await tester.pumpAndSettle();

    expect(fake.receiptRequests, hasLength(1));
    expect(fake.balanceCents, 140000);
    expect(fake.remainingCents, 160000);
  });
}
