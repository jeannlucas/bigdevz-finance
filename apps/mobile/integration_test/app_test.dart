// Fluxo ponta a ponta no dispositivo contra a API real (não usa MockClient).
// Requer a API local com o seed demonstrativo:
//   make up migrate seed
//   flutter test integration_test -d <simulador> --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
import 'package:bigdevz_finance/bootstrap.dart';
import 'package:bigdevz_finance/core/config.dart';
import 'package:bigdevz_finance/core/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login, conta, acordo, recebimento parcial, troca PF/PJ e reabertura', (tester) async {
    const storage = SecureSessionStorage();
    await storage.delete('auth_token');
    await storage.delete('active_space_id');
    final stamp = DateTime.now().millisecondsSinceEpoch.toString();

    Future<void> settle() async {
      // A rede real não é controlada pelo relógio do teste: espera até a tela estabilizar.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (!tester.binding.hasScheduledFrame && find.byType(LinearProgressIndicator).evaluate().isEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          return;
        }
      }
    }

    Future<void> tapText(String text) async {
      await tester.ensureVisible(find.text(text).last);
      await tester.tap(find.text(text).last);
      await settle();
    }

    await tester.pumpWidget(buildApp(baseUrl: apiBaseUrl, storage: storage));
    await settle();

    // 1. Login com o usuário fictício do seed.
    await tester.enterText(find.widgetWithText(TextFormField, 'E-mail'), 'demo@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Senha'), 'demo-bigdevz-local');
    await tapText('Entrar');
    expect(find.text('Saldo disponível'), findsOneWidget);
    expect(find.text('Pessoal (PF)'), findsWidgets);

    // 2. Conta PF nova com saldo inicial de R$ 1.000,00.
    await tapText('Contas');
    await tapText('Nova conta');
    await tester.enterText(find.widgetWithText(TextFormField, 'Nome da conta'), 'Conta IT $stamp');
    await tester.enterText(find.widgetWithText(TextFormField, 'Saldo inicial'), '100000');
    await tapText('Salvar conta');
    expect(find.text('Conta IT $stamp'), findsOneWidget);

    // 3. Acordo de R$ 24.000,00 em 12 parcelas.
    await tapText('A receber');
    await tapText('Novo acordo');
    await tester.enterText(find.widgetWithText(TextFormField, 'Descrição'), 'Venda IT $stamp');
    await tester.enterText(find.widgetWithText(TextFormField, 'Valor total'), '2400000');
    await tapText('Gerar parcelas');
    expect(find.text('Venda IT $stamp'), findsOneWidget);
    expect(find.text('Parcela 1/12'), findsOneWidget);
    expect(find.text(r'R$ 2.000,00'), findsWidgets);

    // 4. Recebimento parcial de R$ 500,00 da primeira parcela na conta nova.
    await tapText('Parcela 1/12');
    await tapText('Registrar recebimento');
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await settle();
    await tapText('Conta IT $stamp');
    await tester.enterText(find.widgetWithText(TextFormField, 'Valor recebido'), '50000');
    await tapText('Confirmar recebimento');
    expect(find.textContaining(r'Saldo da conta: R$ 1.500,00'), findsOneWidget);
    expect(find.text(r'R$ 1.500,00'), findsWidgets); // falta receber na parcela
    expect(find.text('Parcial'), findsOneWidget);

    // 5. Volta ao início e troca para PJ: nada do PF permanece na tela.
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byType(BackButton));
      await settle();
    }
    await tapText('Contas');
    expect(find.text('Conta IT $stamp'), findsOneWidget);
    await tapText('PJ');
    expect(find.text('Conta IT $stamp'), findsNothing);
    expect(find.text('Banco Fictício PJ'), findsOneWidget);

    // 6. "Reabre" o app: nova árvore, mesmo armazenamento seguro, dados pela API.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(buildApp(baseUrl: apiBaseUrl, storage: storage));
    await settle();
    expect(find.text('Empresa (PJ)'), findsWidgets);
    await tapText('PF');
    await tapText('Contas');
    final card = find.ancestor(of: find.text('Conta IT $stamp'), matching: find.byType(ListTile));
    expect(find.descendant(of: card, matching: find.text(r'R$ 1.500,00')), findsOneWidget);
  });
}
