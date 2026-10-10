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

import 'support/lose_response_client.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'login, conta, acordo, recebimentos, correção, estorno, PF/PJ, reabertura e gestão da conta',
    (tester) async {
      const storage = SecureSessionStorage();
      await storage.delete('auth_token');
      await storage.delete('active_space_id');
      final stamp = DateTime.now().millisecondsSinceEpoch.toString();
      // Repassa à API real; armado, descarta uma resposta de recebimento.
      final network = LoseResponseClient();

      Future<void> settle() async {
        // A rede real não é controlada pelo relógio do teste: espera até a tela estabilizar.
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 250));
          if (!tester.binding.hasScheduledFrame &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty &&
              find.byType(CircularProgressIndicator).evaluate().isEmpty) {
            return;
          }
        }
      }

      Finder verticalScrollable() {
        final candidates = find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        );
        return candidates.evaluate().isNotEmpty
            ? candidates.first
            : find.byType(Scrollable).first;
      }

      Future<void> reveal(String text) async {
        final target = find.text(text);
        if (target.evaluate().isNotEmpty) {
          try {
            await tester.ensureVisible(target.last);
          } catch (_) {}
          await settle();
          return;
        }
        for (var i = 0; i < 20 && target.evaluate().isEmpty; i++) {
          if (find.byType(Scrollable).evaluate().isNotEmpty) {
            await tester.drag(
              verticalScrollable(),
              const Offset(0, -300),
              warnIfMissed: false,
            );
          } else {
            await tester.dragFrom(
              const Offset(200, 450),
              const Offset(0, -250),
            );
          }
          await settle();
        }
        if (target.evaluate().isNotEmpty) {
          try {
            await tester.ensureVisible(target.last);
          } catch (_) {}
          await settle();
          return;
        }
        for (var i = 0; i < 20 && target.evaluate().isEmpty; i++) {
          if (find.byType(Scrollable).evaluate().isNotEmpty) {
            await tester.drag(
              verticalScrollable(),
              const Offset(0, 300),
              warnIfMissed: false,
            );
          } else {
            await tester.dragFrom(const Offset(200, 300), const Offset(0, 250));
          }
          await settle();
        }
        if (target.evaluate().isNotEmpty) {
          try {
            await tester.ensureVisible(target.last);
          } catch (_) {}
          await settle();
        }
      }

      Future<void> tapText(String text) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await settle();
        await reveal(text);
        final found = find.text(text);
        expect(
          found,
          findsWidgets,
          reason: 'Elemento com texto "$text" não foi encontrado na tela',
        );
        try {
          await tester.ensureVisible(found.last);
        } catch (_) {}
        await tester.tap(found.last, warnIfMissed: false);
        await settle();
      }

      Future<void> enterField(String label, String value) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await settle();
        await reveal(label);
        final field = find.widgetWithText(TextFormField, label);
        expect(field, findsOneWidget, reason: 'Campo $label não encontrado');
        await tester.enterText(field, value);
        await settle();
      }

      await tester.pumpWidget(
        buildApp(baseUrl: apiBaseUrl, storage: storage, client: network),
      );
      await settle();

      // 1. Login com o usuário fictício do seed.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'E-mail'),
        'demo@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Senha'),
        'demo-bigdevz-local',
      );
      await tapText('Entrar');
      expect(find.text('Saldo disponível'), findsOneWidget);
      expect(find.text('Pessoal (PF)'), findsWidgets);

      // 2. Conta PF nova com saldo inicial de R$ 1.000,00.
      await tapText('Contas');
      await tapText('Nova conta');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome da conta'),
        'Conta IT $stamp',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Saldo inicial'),
        '100000',
      );
      await tapText('Salvar conta');
      await reveal('Conta IT $stamp');
      expect(find.text('Conta IT $stamp'), findsOneWidget);

      // 3. Conta a receber de R$ 24.000,00 em 12 parcelas.
      await tapText('A receber');
      await tapText('Nova conta a receber');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Descrição'),
        'Venda IT $stamp',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Valor total'),
        '2400000',
      );
      await tapText('Gerar parcelas');
      expect(find.text('Venda IT $stamp'), findsOneWidget);
      expect(find.text('Parcela 1/12'), findsOneWidget);
      expect(find.text(r'R$ 2.000,00'), findsWidgets);

      Future<void> chooseAccount() async {
        await tester.tap(find.byType(DropdownButtonFormField<int>));
        await settle();
        await reveal('Conta IT $stamp');
        await tapText('Conta IT $stamp');
      }

      Finder reviewLine(String id, String value) => find.descendant(
        of: find.byKey(ValueKey('review-$id')),
        matching: find.text(value),
      );

      // 4. Recebimento parcial de R$ 500,00 da primeira parcela na conta nova,
      //    revisado e corrigido sem gravar. Na confirmação a API grava, mas a
      //    resposta se perde: a tentativa fica travada e sobrevive à reabertura.
      await tapText('Parcela 1/12');
      await tapText('Registrar recebimento');
      await chooseAccount();
      await tapText('Parcial');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Valor recebido'),
        '50000',
      );
      await tapText('Revisar recebimento');
      expect(reviewLine('Valor', r'R$ 500,00'), findsOneWidget);
      expect(reviewLine('Conta', 'Conta IT $stamp'), findsOneWidget);
      expect(reviewLine('Espaço', 'Pessoal (PF)'), findsOneWidget);
      expect(reviewLine('Restante', r'R$ 1.500,00'), findsOneWidget);
      await tapText('Voltar e corrigir');
      await tapText('Revisar recebimento');
      network.armed = true;
      await tapText('Confirmar recebimento');
      expect(network.lost, 1);
      expect(find.text('Recebimento não confirmado'), findsOneWidget);
      expect(find.text('Voltar e corrigir'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      await tapText('Verificar depois');
      expect(find.text('Recebimento aguardando confirmação'), findsOneWidget);
      expect(find.text('Registrar recebimento'), findsNothing);

      // Reabre o app: a tentativa volta do armazenamento seguro.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        buildApp(baseUrl: apiBaseUrl, storage: storage, client: network),
      );
      await settle();
      await tapText('A receber');
      await reveal('Venda IT $stamp');
      await tapText('Venda IT $stamp');
      await tapText('Parcela 1/12');
      expect(find.text('Recebimento aguardando confirmação'), findsOneWidget);
      expect(find.text('Registrar recebimento'), findsNothing);
      await tapText('Verificar recebimento');
      expect(
        find.textContaining(
          'Recebimento já estava registrado: R\$ 500,00 em Conta IT $stamp',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(r'Saldo da conta: R$ 1.500,00'),
        findsOneWidget,
      );
      expect(find.text('Recebimento aguardando confirmação'), findsNothing);
      expect(
        find.text(r'R$ 1.500,00'),
        findsWidgets,
      ); // falta receber na parcela
      expect(find.text('Parcial'), findsOneWidget);

      // 4b. Recebimento total do restante (R$ 1.500,00): parcela quitada.
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold).last))
          .hideCurrentSnackBar();
      await settle();
      await tapText('Registrar recebimento');
      await chooseAccount();
      await tapText('Total');
      await tapText('Revisar recebimento');
      expect(reviewLine('Valor', r'R$ 1.500,00'), findsOneWidget);
      expect(
        reviewLine('Restante', r'R$ 0,00 · parcela quitada'),
        findsOneWidget,
      );
      await tapText('Confirmar recebimento');
      expect(
        find.textContaining(r'Saldo da conta: R$ 3.000,00'),
        findsOneWidget,
      );
      expect(find.text('Quitada'), findsOneWidget);
      expect(find.text('Registrar recebimento'), findsNothing);

      Future<void> dismissSnackBar() async {
        ScaffoldMessenger.of(tester.element(find.byType(Scaffold).last))
            .hideCurrentSnackBar();
        await settle();
      }

      // 4c. Correção do Total (R$ 1.500,00 → R$ 1.200,00) com a resposta
      //     perdida depois da gravação; verificada pela mesma chave.
      await dismissSnackBar();
      await tester.tap(find.byTooltip('Ações do recebimento').last);
      await settle();
      await tapText('Corrigir recebimento');
      await enterField('Valor correto', '120000');
      await enterField('Motivo', 'Valor digitado errado (teste IT)');
      await tapText('Revisar correção');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('fix-Restante')),
          matching: find.text(r'R$ 0,00 → R$ 300,00'),
        ),
        findsOneWidget,
      );
      network.armed = true;
      await tapText('Confirmar correção');
      expect(network.lost, 2);
      expect(find.text('Correção não confirmada'), findsOneWidget);
      expect(find.text('Voltar e corrigir'), findsNothing);
      await tapText('Verificar correção');
      expect(
        find.textContaining(
          'Correção já estava registrada: R\$ 1.200,00 em Conta IT $stamp',
        ),
        findsOneWidget,
      );
      expect(find.text('Corrigido'), findsOneWidget);
      expect(find.text('Parcial'), findsOneWidget);

      // 4d. Estorno do recebimento parcial de R$ 500,00.
      await dismissSnackBar();
      await tester.tap(find.byTooltip('Ações do recebimento').first);
      await settle();
      await tapText('Estornar recebimento');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo'),
        'Registrado por engano (teste IT)',
      );
      await tapText('Revisar estorno');
      await tapText('Confirmar estorno');
      expect(
        find.textContaining(
          'Estorno confirmado: R\$ 500,00 retirados de Conta IT $stamp',
        ),
        findsOneWidget,
      );
      expect(find.text('Estornado'), findsOneWidget);
      expect(find.text(r'R$ 800,00'), findsWidgets); // falta receber

      // 5. Volta ao início e troca para PJ: nada do PF permanece na tela.
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byType(BackButton));
        await settle();
      }
      await tapText('Contas');
      await reveal('Conta IT $stamp');
      expect(find.text('Conta IT $stamp'), findsOneWidget);
      await tapText('PJ');
      expect(find.text('Conta IT $stamp'), findsNothing);
      expect(find.text('Banco Fictício PJ'), findsOneWidget);

      // 6. "Reabre" o app: nova árvore, mesmo armazenamento seguro, dados pela API.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        buildApp(baseUrl: apiBaseUrl, storage: storage, client: network),
      );
      await settle();
      expect(find.text('Empresa (PJ)'), findsWidgets);
      await tapText('PF');
      await tapText('Contas');
      await reveal('Conta IT $stamp');
      final card = find.ancestor(
        of: find.text('Conta IT $stamp'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: card, matching: find.text(r'R$ 2.200,00')),
        findsOneWidget,
      );

      // 7. Conta: editar nome, corrigir abertura, arquivar e reativar.
      final edited = 'Conta IT $stamp editada';
      await tapText('Conta IT $stamp');
      await tapText('Editar conta');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome da conta'),
        edited,
      );
      await tapText('Salvar alterações');
      expect(find.text('Conta atualizada.'), findsOneWidget);
      expect(find.text(edited), findsOneWidget);

      await dismissSnackBar();
      await tapText('Corrigir abertura');
      await enterField('Saldo inicial correto', '110000');
      await enterField('Motivo', 'Saldo do extrato (teste IT)');
      await tapText('Revisar correção da abertura');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('opening-Saldo-atual')),
          matching: find.text(r'R$ 2.200,00 → R$ 2.300,00'),
        ),
        findsOneWidget,
      );
      await tapText('Confirmar correção');
      expect(find.text('Abertura corrigida.'), findsOneWidget);
      expect(find.text(r'R$ 1.000,00 → R$ 1.100,00'), findsOneWidget);

      await dismissSnackBar();
      await tapText('Arquivar conta');
      await tapText('Arquivar');
      expect(find.text('Conta arquivada.'), findsOneWidget);
      expect(find.text('Arquivada'), findsOneWidget);

      // Arquivada: fora dos destinos de um novo recebimento.
      Future<List<String>> destinations() async {
        await tapText('A receber');
        await reveal('Venda IT $stamp');
        await tapText('Venda IT $stamp');
        await tapText('Parcela 1/12');
        await tapText('Registrar recebimento');
        final items = tester
            .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
            .items!;
        final names = [
          for (final item in items) ((item.child as Text).data ?? ''),
        ];
        for (var i = 0; i < 3; i++) {
          await tester.tap(find.byType(BackButton));
          await settle();
        }
        return names;
      }

      await dismissSnackBar();
      await tester.tap(find.byType(BackButton));
      await settle();
      expect(await destinations(), isNot(contains(edited)));

      await tapText('Contas');
      await reveal(edited);
      await tapText(edited);
      await dismissSnackBar();
      await tapText('Reativar conta');
      await tapText('Reativar');
      expect(find.text('Conta reativada.'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await settle();
      expect(await destinations(), contains(edited));
    },
  );

  testWidgets(
    'a pagar: cadastros com resposta perdida e retomada, pagamento parcial com resposta perdida, total, estorno e correção',
    (tester) async {
      const storage = SecureSessionStorage();
      await storage.delete('auth_token');
      await storage.delete('active_space_id');
      final stamp = DateTime.now().millisecondsSinceEpoch.toString();
      final network = LoseResponseClient();
      final account = 'Conta AP $stamp';
      final expense = 'Despesa IT $stamp';

      Future<void> settle() async {
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 250));
          if (!tester.binding.hasScheduledFrame &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty &&
              find.byType(CircularProgressIndicator).evaluate().isEmpty) {
            return;
          }
        }
      }

      Finder verticalScrollable() {
        final candidates = find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        );
        return candidates.evaluate().isNotEmpty
            ? candidates.first
            : find.byType(Scrollable).first;
      }

      Future<void> reveal(String text) async {
        final target = find.text(text);
        if (target.evaluate().isNotEmpty) {
          try {
            await tester.ensureVisible(target.last);
          } catch (_) {}
          await settle();
          return;
        }
        for (var i = 0; i < 20 && target.evaluate().isEmpty; i++) {
          if (find.byType(Scrollable).evaluate().isNotEmpty) {
            await tester.drag(
              verticalScrollable(),
              const Offset(0, -300),
              warnIfMissed: false,
            );
          } else {
            await tester.dragFrom(
              const Offset(200, 450),
              const Offset(0, -250),
            );
          }
          await settle();
        }
        if (target.evaluate().isNotEmpty) {
          try {
            await tester.ensureVisible(target.last);
          } catch (_) {}
          await settle();
          return;
        }
        for (var i = 0; i < 20 && target.evaluate().isEmpty; i++) {
          if (find.byType(Scrollable).evaluate().isNotEmpty) {
            await tester.drag(
              verticalScrollable(),
              const Offset(0, 300),
              warnIfMissed: false,
            );
          } else {
            await tester.dragFrom(const Offset(200, 300), const Offset(0, 250));
          }
          await settle();
        }
        if (target.evaluate().isNotEmpty) {
          try {
            await tester.ensureVisible(target.last);
          } catch (_) {}
          await settle();
        }
      }

      Future<void> tapText(String text) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await settle();
        await reveal(text);
        final found = find.text(text);
        expect(
          found,
          findsWidgets,
          reason: 'Elemento com texto "$text" não foi encontrado na tela',
        );
        try {
          await tester.ensureVisible(found.last);
        } catch (_) {}
        await tester.tap(found.last, warnIfMissed: false);
        await settle();
      }

      Future<void> dismissSnackBar() async {
        ScaffoldMessenger.of(tester.element(find.byType(Scaffold).last))
            .hideCurrentSnackBar();
        await settle();
      }

      Future<void> chooseAccount() async {
        await tester.tap(find.byType(DropdownButtonFormField<int>));
        await settle();
        await reveal(account);
        await tapText(account);
      }

      await tester.pumpWidget(
        buildApp(baseUrl: apiBaseUrl, storage: storage, client: network),
      );
      await settle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'E-mail'),
        'demo@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Senha'),
        'demo-bigdevz-local',
      );
      await tapText('Entrar');

      // Conta fictícia com R$ 1.000,00 de abertura.
      await tapText('Contas');
      await tapText('Nova conta');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome da conta'),
        account,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Saldo inicial'),
        '100000',
      );
      await tapText('Salvar conta');
      await dismissSnackBar();

      Future<void> reopenApp() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          buildApp(baseUrl: apiBaseUrl, storage: storage, client: network),
        );
        await settle();
        await tapText('A pagar');
      }

      // Obrigação avulsa de R$ 300,00 com a resposta perdida após gravar:
      // app reaberto, retomada pelo aviso de A pagar. Não altera saldo.
      await tapText('A pagar');
      await tapText('Nova conta a pagar');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Descrição'),
        expense,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Valor'),
        '30000',
      );
      network.armed = true;
      await tapText('Salvar conta a pagar');
      expect(network.lost, 1);
      expect(find.text('Cadastro aguardando confirmação'), findsOneWidget);
      await reopenApp();
      expect(find.text('Cadastro aguardando confirmação'), findsOneWidget);
      await tapText('Verificar cadastro');
      expect(
        find.textContaining(
          'Cadastro já estava registrado: $expense, 1 obrigação.',
        ),
        findsOneWidget,
      );
      await dismissSnackBar();

      // Recorrente iniciada em agosto: revisão mostra as vencidas e exige
      // confirmação; resposta perdida; retomada cria o conjunto uma vez.
      final recurring = 'Recorrência IT $stamp';
      await tapText('Nova conta a pagar');
      await tapText('Recorrente');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Descrição'),
        recurring,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Valor mensal'),
        '5000',
      );
      await tapText('Primeiro vencimento (dia de referência)');
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await settle();
      await tester.enterText(find.byType(TextField).last, '15/08/2026');
      await tapText('OK');
      await tapText('Revisar ocorrências');
      expect(
        find.textContaining('2 ocorrências já venceram (total R\$ 100,00)'),
        findsOneWidget,
      );
      await reveal('Confirmo a criação das 2 ocorrências vencidas');
      await tapText('Confirmo a criação das 2 ocorrências vencidas');
      await reveal('Confirmar recorrência');
      network.armed = true;
      await tapText('Confirmar recorrência');
      expect(network.lost, 2);
      await reopenApp();
      await tapText('Verificar cadastro');
      expect(
        find.textContaining(
          'Cadastro já estava registrado: $recurring, 15 obrigações.',
        ),
        findsOneWidget,
      );
      await dismissSnackBar();
      await reveal(expense);
      await tapText(expense);

      // Parcial de R$ 100,00 com a resposta perdida após a gravação.
      await tapText('Registrar pagamento');
      await chooseAccount();
      await tapText('Parcial');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Valor pago'),
        '10000',
      );
      await tapText('Revisar pagamento');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('payment-Saldo')),
          matching: find.text(r'R$ 1.000,00 → R$ 900,00'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('payment-Restante')),
          matching: find.text(r'R$ 200,00'),
        ),
        findsOneWidget,
      );
      network.armed = true;
      await tapText('Confirmar pagamento');
      expect(network.lost, 3);
      expect(find.text('Pagamento não confirmado'), findsOneWidget);
      expect(find.text('Voltar e corrigir'), findsNothing);
      await tapText('Verificar pagamento');
      expect(
        find.textContaining(
          'Pagamento já estava registrado: R\$ 100,00 de $account. Saldo da conta: R\$ 900,00.',
        ),
        findsOneWidget,
      );

      // Restante total: saldo R$ 700,00.
      await dismissSnackBar();
      await tapText('Registrar pagamento');
      await chooseAccount();
      await tapText('Total');
      await tapText('Revisar pagamento');
      await tapText('Confirmar pagamento');
      expect(find.textContaining(r'Saldo da conta: R$ 700,00'), findsOneWidget);
      expect(find.text('Paga'), findsOneWidget);

      // Estorno do pagamento de R$ 100,00: saldo R$ 800,00, restante R$ 100,00.
      await dismissSnackBar();
      await tester.tap(find.byTooltip('Ações do pagamento').first);
      await settle();
      await tapText('Estornar pagamento');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo'),
        'Débito duplicado (teste IT)',
      );
      await tapText('Revisar estorno');
      await tapText('Confirmar estorno');
      expect(
        find.textContaining(
          'Estorno do pagamento confirmado: R\$ 100,00 devolvidos a $account',
        ),
        findsOneWidget,
      );

      // Correção do pagamento de R$ 200,00 para R$ 150,00: saldo R$ 850,00.
      await dismissSnackBar();
      await tester.tap(find.byTooltip('Ações do pagamento').first);
      await settle();
      await tapText('Corrigir pagamento');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Valor correto'),
        '15000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo'),
        'Valor errado (teste IT)',
      );
      await tapText('Revisar correção');
      await tapText('Confirmar correção');
      expect(
        find.textContaining(
          'Correção do pagamento confirmada: R\$ 150,00 de $account',
        ),
        findsOneWidget,
      );
      expect(find.text('Estornado'), findsOneWidget);
      expect(find.text('Corrigido'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await settle();
      await tapText('Contas');
      await reveal(account);
      final card = find.ancestor(
        of: find.text(account),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: card, matching: find.text(r'R$ 850,00')),
        findsOneWidget,
      );
    },
  );
}
