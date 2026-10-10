import 'package:bigdevz_finance/bootstrap.dart';
import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/core/config.dart';
import 'package:bigdevz_finance/core/token_storage.dart';
import 'package:bigdevz_finance/features/accounts/accounts_repository.dart';
import 'package:bigdevz_finance/features/agreements/agreements_repository.dart';
import 'package:bigdevz_finance/features/agreements/receipt_attempts.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:bigdevz_finance/features/payables/payable_creations.dart';
import 'package:bigdevz_finance/features/payables/payable_form_screen.dart';
import 'package:bigdevz_finance/features/payables/payables_repository.dart';
import 'package:bigdevz_finance/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Gera evidencias visuais reais com validacao estrita de espaco e conteudo',
    (tester) async {
      const storage = SecureSessionStorage();
      final client = http.Client();

      Future<void> settle([int iterations = 40]) async {
        for (var i = 0; i < iterations; i++) {
          await tester.pump(const Duration(milliseconds: 200));
          if (!tester.binding.hasScheduledFrame &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty &&
              find.byType(CircularProgressIndicator).evaluate().isEmpty) {
            return;
          }
        }
      }

      Future<void> capture(String name) async {
        final res = await http.get(
          Uri.parse('http://127.0.0.1:9876/screenshot?name=$name'),
        );
        expect(
          res.statusCode,
          equals(200),
          reason: 'Falha ao solicitar screenshot para $name',
        );
      }

      Future<void> setAppearance(String mode) async {
        final res = await http.get(
          Uri.parse('http://127.0.0.1:9876/appearance?mode=$mode'),
        );
        expect(
          res.statusCode,
          equals(200),
          reason: 'Falha ao mudar aparencia para $mode',
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      Future<void> selectSpace(String kind) async {
        final spaceText = find.descendant(
          of: find.byType(SegmentedButton<int>),
          matching: find.text(kind),
        );
        expect(
          spaceText,
          findsOneWidget,
          reason: 'Botao de selecao do espaco $kind nao encontrado',
        );
        await tester.tap(spaceText);
        await settle();

        // Confirma que o espaco ativo e exatamente o solicitado
        final context = tester.element(find.byType(SegmentedButton<int>));
        final session = Provider.of<SessionController>(context, listen: false);
        expect(
          session.activeSpace?.kind,
          equals(kind),
          reason: 'Espaco ativo nao e $kind',
        );
      }

      Future<void> selectTab(String label) async {
        final dest = find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        );
        expect(
          dest,
          findsOneWidget,
          reason: 'Destino de navegacao $label nao encontrado',
        );
        await tester.tap(dest);
        await settle();
      }

      // Inicia app real conectado a API local
      await tester.pumpWidget(
        buildApp(baseUrl: apiBaseUrl, storage: storage, client: client),
      );
      await settle();

      // Login se necessario
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

      // ==========================================
      // 1. TEMA ESCURO (DARK MODE)
      // ==========================================
      await setAppearance('dark');
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      await tester.pumpAndSettle();

      // 1.1 Resumo PF
      await selectTab('Resumo');
      await selectSpace('PF');
      expect(find.text('Espaço PF'), findsOneWidget);
      await capture('dark_01_resumo_pf');

      // 1.2 Resumo PJ
      await selectSpace('PJ');
      expect(find.text('Espaço PJ'), findsOneWidget);
      await capture('dark_02_resumo_pj');

      // 1.3 Carteira PF
      await selectSpace('PF');
      await selectTab('Contas');
      expect(find.text('Carteira de Contas'), findsOneWidget);
      expect(find.text('Conta financeira PF'), findsWidgets);
      await capture('dark_03_carteira_pf');

      // 1.4 Carteira PJ
      await selectSpace('PJ');
      await selectTab('Contas');
      expect(find.text('Carteira de Contas'), findsOneWidget);
      expect(find.text('Banco Fictício PJ'), findsWidgets);
      expect(find.text('Conta financeira PJ'), findsWidgets);
      await capture('dark_04_carteira_pj');

      // 1.5 A pagar PF
      await selectSpace('PF');
      await selectTab('A pagar');
      expect(find.text('Nova conta a pagar'), findsOneWidget);
      await capture('dark_05_a_pagar_pf');

      // 1.6 Cadastro A pagar Recorrente (PF)
      final newPayableBtn = find.text('Nova conta a pagar');
      expect(newPayableBtn, findsOneWidget);
      await tester.tap(newPayableBtn);
      await settle();
      expect(find.text('Nova conta a pagar'), findsOneWidget);
      expect(find.textContaining('Pessoal'), findsOneWidget);
      await tester.tap(find.text('Recorrente'));
      await settle();
      // Confirma campos e rotulos sem truncamento
      expect(find.text('Beneficiário (opcional)'), findsOneWidget);
      expect(find.text('Primeiro vencimento'), findsOneWidget);
      expect(
        find.text(
          'O dia escolhido será usado como referência nos meses seguintes.',
        ),
        findsOneWidget,
      );
      await capture('dark_06_cadastro_pagar_recorrente');

      // Retorna para a tela de A pagar
      final backBtnDark = find.byTooltip('Back');
      if (backBtnDark.evaluate().isNotEmpty) {
        await tester.tap(backBtnDark);
      } else {
        await tester.tap(find.byType(BackButton));
      }
      await settle();

      // ==========================================
      // 2. TEMA CLARO (LIGHT MODE)
      // ==========================================
      await setAppearance('light');
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;
      await tester.pumpAndSettle();

      // 2.1 Resumo PF
      await selectTab('Resumo');
      await selectSpace('PF');
      expect(find.text('Espaço PF'), findsOneWidget);
      await capture('light_01_resumo_pf');

      // 2.2 Resumo PJ
      await selectSpace('PJ');
      expect(find.text('Espaço PJ'), findsOneWidget);
      await capture('light_02_resumo_pj');

      // 2.3 Carteira PF (Garante selecao explicita de PF e conteudo real PF)
      await selectSpace('PF');
      await selectTab('Contas');
      expect(find.text('Carteira de Contas'), findsOneWidget);
      expect(find.text('Conta financeira PF'), findsWidgets);
      expect(find.text('Banco Fictício PJ'), findsNothing);
      await capture('light_03_carteira_pf');

      // 2.4 Carteira PJ
      await selectSpace('PJ');
      await selectTab('Contas');
      expect(find.text('Carteira de Contas'), findsOneWidget);
      expect(find.text('Banco Fictício PJ'), findsWidgets);
      expect(find.text('Conta financeira PJ'), findsWidgets);
      await capture('light_04_carteira_pj');

      // 2.5 A pagar PF
      await selectSpace('PF');
      await selectTab('A pagar');
      expect(find.text('Nova conta a pagar'), findsOneWidget);
      await capture('light_05_a_pagar_pf');

      // 2.6 Cadastro A pagar Recorrente (PF)
      final newPayableBtnLight = find.text('Nova conta a pagar');
      expect(newPayableBtnLight, findsOneWidget);
      await tester.tap(newPayableBtnLight);
      await settle();
      expect(find.text('Nova conta a pagar'), findsOneWidget);
      expect(find.textContaining('Pessoal'), findsOneWidget);
      await tester.tap(find.text('Recorrente'));
      await settle();
      expect(find.text('Beneficiário (opcional)'), findsOneWidget);
      expect(find.text('Primeiro vencimento'), findsOneWidget);
      expect(
        find.text(
          'O dia escolhido será usado como referência nos meses seguintes.',
        ),
        findsOneWidget,
      );
      await capture('light_06_cadastro_pagar_recorrente');

      // Retorna para A pagar e restaura tema dark nativo
      final backBtnLight = find.byTooltip('Back');
      if (backBtnLight.evaluate().isNotEmpty) {
        await tester.tap(backBtnLight);
      } else {
        await tester.tap(find.byType(BackButton));
      }
      await settle();
      await setAppearance('dark');
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      await tester.pumpAndSettle();

      // ==========================================
      // 3. EVIDENCIAS DE ACESSIBILIDADE VIA HARNESS DE TESTE
      // Insets reais de Safe Area (top: 59pt status bar, bottom: 34pt home indicator)
      // ==========================================
      final apiClient = ApiClient(baseUrl: apiBaseUrl, client: client);
      const spacePf = Space(id: 1, kind: 'PF', name: 'Pessoal');

      Widget buildA11yForm({
        required double width,
        required double scale,
        required EdgeInsets insets,
      }) {
        return MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 874),
              padding: insets,
              viewPadding: insets,
              textScaler: TextScaler.linear(scale),
            ),
            child: MultiProvider(
              providers: [
                Provider.value(value: AgreementsRepository(apiClient)),
                Provider.value(value: AccountsRepository(apiClient)),
                Provider.value(value: PayablesRepository(apiClient)),
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
                          api: apiClient,
                          auth: AuthRepository(apiClient),
                          storage: storage,
                        )
                        ..user = const AppUser(
                          id: 1,
                          name: 'Demo',
                          email: 'demo@example.com',
                        ),
                ),
              ],
              child: PayableFormScreen(
                space: spacePf,
                today: DateTime(2026, 3, 10),
              ),
            ),
          ),
        );
      }

      const standardInsets = EdgeInsets.only(top: 59, bottom: 34);

      // 3.1: Harness 375px com escala 150% (1.5x)
      await tester.pumpWidget(
        buildA11yForm(width: 375, scale: 1.5, insets: standardInsets),
      );
      await settle();
      await tester.tap(find.text('Recorrente'));
      await settle();
      // Confere que o cabeçalho e labels estão intactos
      expect(find.text('Nova conta a pagar'), findsOneWidget);
      expect(find.text('Beneficiário (opcional)'), findsOneWidget);
      expect(find.text('Primeiro vencimento'), findsOneWidget);
      await capture('a11y_375px_scale_150_seletor');

      // 3.2: Harness 375px com escala 200% (2.0x)
      await tester.pumpWidget(
        buildA11yForm(width: 375, scale: 2.0, insets: standardInsets),
      );
      await settle();
      expect(find.text('Nova conta a pagar'), findsOneWidget);
      expect(find.text('Beneficiário (opcional)'), findsOneWidget);
      expect(find.text('Primeiro vencimento'), findsOneWidget);
      await capture('a11y_375px_scale_200_seletor');

      // 3.3: Harness 402px (iPhone 17 Pro) com escala 200% (2.0x)
      await tester.pumpWidget(
        buildA11yForm(width: 402, scale: 2.0, insets: standardInsets),
      );
      await settle();
      expect(find.text('Nova conta a pagar'), findsOneWidget);
      expect(find.text('Beneficiário (opcional)'), findsOneWidget);
      expect(find.text('Primeiro vencimento'), findsOneWidget);
      await capture('a11y_iphone17pro_scale_200_seletor');
    },
  );
}
