// Teste de integração de inspeção e comprovação visual das abas, filtros e botões únicos.
import 'package:bigdevz_finance/bootstrap.dart';
import 'package:bigdevz_finance/core/config.dart';
import 'package:bigdevz_finance/core/token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'inspeciona e comprova na tela a navegação, filtros e botões únicos',
    (tester) async {
      const storage = SecureSessionStorage();
      final client = http.Client();

      Future<void> settle() async {
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 200));
          if (!tester.binding.hasScheduledFrame &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty &&
              find.byType(CircularProgressIndicator).evaluate().isEmpty) {
            return;
          }
        }
      }

      Future<void> tapText(String text) async {
        final target = find.text(text);
        expect(target, findsWidgets, reason: 'esperado encontrar $text');
        await tester.tap(target.first);
        await settle();
      }

      Future<void> capture(String name) async {
        await binding.takeScreenshot(name);
        try {
          await http.get(
            Uri.parse('http://127.0.0.1:9876/screenshot?name=$name'),
          );
        } catch (_) {}
      }

      await tester.pumpWidget(
        buildApp(baseUrl: apiBaseUrl, storage: storage, client: client),
      );
      await settle();

      // Se estiver no login, entra com o usuário do seed
      if (find.widgetWithText(TextFormField, 'E-mail').evaluate().isNotEmpty) {
        await tester.enterText(
          find.widgetWithText(TextFormField, 'E-mail'),
          'demo@example.com',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Senha'),
          'demo-bigdevz-local',
        );
        await tester.tap(find.text('Entrar'));
        await settle();
      }

      expect(find.text('Saldo disponível'), findsOneWidget);

      Future<void> tapDestination(String label) async {
        final dest = find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        );
        expect(dest, findsOneWidget);
        await tester.tap(dest);
        await settle();
      }

      // 1. ESPAÇO PF
      // Aba Resumo
      await capture('evidence_pf_01_resumo');

      // Aba Contas a receber
      await tapDestination('A receber');
      expect(find.text('Contas a receber'), findsOneWidget);
      expect(find.text('Nova conta a receber'), findsOneWidget);
      expect(
        find.byType(FloatingActionButton),
        findsNothing,
        reason: 'Nenhum FAB na tela',
      );
      expect(
        find.text('Novo acordo'),
        findsNothing,
        reason: 'Nenhum botão antigo',
      );
      expect(find.text('Em aberto'), findsOneWidget);
      expect(find.text('Vencidas'), findsOneWidget);
      expect(find.text('Hoje'), findsOneWidget);
      expect(find.text('Próximos 30 dias'), findsOneWidget);
      await capture('evidence_pf_02_receber_open');

      // Troca de filtro para Vencidas
      await tapText('Vencidas');
      await capture('evidence_pf_03_receber_overdue');

      // Aba A pagar
      await tapDestination('A pagar');
      expect(find.text('Nova conta a pagar'), findsOneWidget);
      expect(
        find.byType(FloatingActionButton),
        findsNothing,
        reason: 'Nenhum FAB na tela',
      );
      await capture('evidence_pf_04_pagar');

      // Aba Contas
      await tapDestination('Contas');
      expect(find.text('Carteira de Contas'), findsOneWidget);
      expect(find.text('Nova conta'), findsOneWidget);
      expect(
        find.byType(FloatingActionButton),
        findsNothing,
        reason: 'Nenhum FAB na tela',
      );
      await capture('evidence_pf_05_contas');

      // 2. ESPAÇO PJ
      await tapText('PJ');
      await settle();

      // Aba Contas (PJ)
      expect(find.text('Carteira de Contas'), findsOneWidget);
      expect(find.text('Nova conta'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      await capture('evidence_pj_01_contas');

      // Aba A pagar (PJ)
      await tapDestination('A pagar');
      expect(find.text('Nova conta a pagar'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      await capture('evidence_pj_02_pagar');

      // Aba Contas a receber (PJ)
      await tapDestination('A receber');
      expect(find.text('Contas a receber'), findsOneWidget);
      expect(find.text('Nova conta a receber'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      await capture('evidence_pj_03_receber');

      // Aba Resumo (PJ) - verificar gradiente verde esmeralda e proporção
      await tapDestination('Resumo');
      await capture('evidence_pj_04_resumo');

      // Volta para PF e abre formulário de Nova conta a pagar para verificar seletor
      await tapText('PF');
      await settle();
      await tapDestination('A pagar');
      expect(
        find.byType(Card),
        findsWidgets,
        reason: 'esperado encontrar PayableCards individuais',
      );
      await tapText('Nova conta a pagar');
      await settle();
      expect(find.text('Avulsa'), findsOneWidget);
      expect(find.text('Parcelada'), findsOneWidget);
      expect(find.text('Recorrente'), findsOneWidget);
      await capture('evidence_pf_07_form_pagar_segmented');

      // Testa seleção de Recorrente no formulário
      await tapText('Recorrente');
      await settle();
      await capture('evidence_pf_08_form_pagar_recorrente_selected');

      // Volta para tela anterior
      final backBtn = find.byTooltip('Back');
      if (backBtn.evaluate().isNotEmpty) {
        await tester.tap(backBtn);
      } else {
        final navBack = find.byType(BackButton);
        if (navBack.evaluate().isNotEmpty) {
          await tester.tap(navBack);
        }
      }
      await settle();

      // Volta para Resumo, testa clique no alerta de vencidas
      await tapDestination('Resumo');

      final alertFinder = find.textContaining('parcelas vencidas a receber');
      if (alertFinder.evaluate().isNotEmpty) {
        await tester.tap(alertFinder.first);
        await settle();
        expect(find.text('Contas a receber'), findsOneWidget);
        // Confirma que abriu com Vencidas selecionado
        await capture('evidence_pf_06_receber_from_summary_alert');

        // Abre formulário de Nova conta a receber para comprovar campos e ícones de data
        await tapText('Nova conta a receber');
        await settle();
        await capture('evidence_pf_09_form_receber');
      }
    },
  );
}
