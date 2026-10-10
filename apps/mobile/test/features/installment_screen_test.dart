import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/core/money.dart';
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

void main() {
  late FakeReceiptsApi fake;
  late MemorySessionStorage storage;

  ApiClient client() =>
      ApiClient(baseUrl: 'http://api.test/api', client: fake.client);

  /// Monta o app do zero (novo serviço, mesmo armazenamento): equivale a
  /// fechar e reabrir com o [userId] informado.
  Future<void> openApp(WidgetTester tester, {required int userId}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final api = client();
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

  setUp(() {
    fake = FakeReceiptsApi(installmentCents: 200000, balanceCents: 100000);
    storage = MemorySessionStorage();
  });

  testWidgets(
    'tentativa incerta sobrevive à reabertura, não aparece para outro usuário '
    'e bloqueia a parcela até ser verificada',
    (tester) async {
      // Sessão anterior: a API gravou R$ 500,00 e a resposta se perdeu.
      fake.script.add(Delivery.loseResponse);
      final previous = ReceiptAttempts(
        repository: AgreementsRepository(client()),
        storage: storage,
      );
      final lost = await previous.submit(
        userId: 1,
        spaceId: 1,
        installmentId: 22,
        accountId: 7,
        accountName: 'Banco PF',
        amount: Money.parse('500.00'),
        receivedOn: '2026-03-10',
        kind: ReceiptKind.partial,
      );
      expect(lost.state, ReceiptAttemptState.uncertain);

      // Outro usuário no mesmo aparelho: nada da tentativa é exibido.
      await openApp(tester, userId: 2);
      expect(find.text('Recebimento aguardando confirmação'), findsNothing);
      expect(find.text('Banco PF · 10/03/2026'), findsNothing);

      // O usuário original reabre o app: a tentativa volta e bloqueia.
      await openApp(tester, userId: 1);
      expect(find.text('Recebimento aguardando confirmação'), findsOneWidget);
      expect(find.text('Banco PF · 10/03/2026'), findsOneWidget);
      expect(find.text('Registrar recebimento'), findsNothing);

      await tester.tap(find.text('Verificar recebimento'));
      await tester.pump();
      await tester.tap(find.text('Verificar recebimento'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(
        find.text(
          r'Recebimento já estava registrado: R$ 500,00 em Banco PF. '
          r'Saldo da conta: R$ 1.500,00.',
        ),
        findsOneWidget,
      );
      expect(fake.receiptRequests, hasLength(2));
      expect(
        fake.receiptRequests.map((r) => r.headers['Idempotency-Key']).toSet(),
        {lost.attempt.idempotencyKey},
      );
      expect(fake.receipts, hasLength(1));
      expect(fake.balanceCents, 150000);
      expect(find.text('Recebimento aguardando confirmação'), findsNothing);
      expect(await storage.read('pending_receipt.1.1.22'), isNull);

      // Novo recebimento intencional parte do restante atualizado.
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
          .hideCurrentSnackBar();
      await tester.pumpAndSettle();
      await tapText(tester, 'Registrar recebimento');
      expect(find.textContaining(r'Falta receber R$ 1.500,00'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tapText(tester, 'Reserva PF');
      await tapText(tester, 'Total');
      await tapText(tester, 'Revisar recebimento');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('review-Valor')),
          matching: find.text(r'R$ 1.500,00'),
        ),
        findsOneWidget,
      );
      await tapText(tester, 'Confirmar recebimento');

      expect(fake.receipts.map((r) => r.amountCents), [50000, 150000]);
      expect(fake.receipts.last.accountId, 8);
      expect(fake.remainingCents, 0);
      expect(find.text('Quitada'), findsOneWidget);
      expect(find.text('Registrar recebimento'), findsNothing);
    },
  );
}
