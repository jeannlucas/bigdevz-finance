import 'package:bigdevz_finance/app.dart';
import 'package:bigdevz_finance/bootstrap.dart';
import 'package:bigdevz_finance/core/config.dart';
import 'package:bigdevz_finance/core/token_storage.dart';
import 'package:bigdevz_finance/features/settings/preferences_controller.dart';
import 'package:bigdevz_finance/features/settings/settings_screen.dart';
import 'package:bigdevz_finance/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';

void main() {
  group('PreferencesController - Testes Unitários e de Persistência', () {
    late MemorySessionStorage storage;
    late PreferencesController controller;

    setUp(() {
      storage = MemorySessionStorage();
      controller = PreferencesController(storage: storage);
    });

    test('A10: Fallback inicial para ThemeMode.system e hideValuesByDefault = false', () async {
      await controller.load();
      expect(controller.themeMode, equals(ThemeMode.system));
      expect(controller.hideValuesByDefault, isFalse);
      expect(controller.obscureValues, isFalse);
    });

    test('A1, A2, A3, A6, A7: Seleção e persistência de ThemeMode (Claro, Escuro, Sistema)', () async {
      await controller.load();

      // Altera para Claro (A2)
      await controller.setThemeMode(ThemeMode.light);
      expect(controller.themeMode, equals(ThemeMode.light));

      // Verifica persistência no storage (A6)
      expect(
        await storage.read(PreferencesController.themeModeKey),
        equals('light'),
      );

      // Novo controller lê o valor persistido (A7)
      final restored = PreferencesController(storage: storage);
      await restored.load();
      expect(restored.themeMode, equals(ThemeMode.light));

      // Altera para Escuro (A3)
      await controller.setThemeMode(ThemeMode.dark);
      expect(controller.themeMode, equals(ThemeMode.dark));
      expect(
        await storage.read(PreferencesController.themeModeKey),
        equals('dark'),
      );

      // Altera de volta para Sistema/Automático (A1)
      await controller.setThemeMode(ThemeMode.system);
      expect(controller.themeMode, equals(ThemeMode.system));
      expect(
        await storage.read(PreferencesController.themeModeKey),
        equals('system'),
      );
    });

    test('P1, P2, P9, P10, P11, P12, P13, P14: Controle de privacidade na sessão e persistência de padrão', () async {
      await controller.load();

      // P1: Inicialmente visível
      expect(controller.obscureValues, isFalse);

      // P2: Alterna privacidade na sessão
      controller.togglePrivacy();
      expect(controller.obscureValues, isTrue);

      // P9: Alterna de volta
      controller.togglePrivacy();
      expect(controller.obscureValues, isFalse);

      // P10, P11: Ativa ocultar valores por padrão
      await controller.setHideValuesByDefault(true);
      expect(controller.hideValuesByDefault, isTrue);
      expect(controller.obscureValues, isTrue);
      expect(
        await storage.read(PreferencesController.hideByDefaultKey),
        equals('true'),
      );

      // P12: Novo controller restaura obscureValues = true ao carregar
      final newController = PreferencesController(storage: storage);
      await newController.load();
      expect(newController.hideValuesByDefault, isTrue);
      expect(newController.obscureValues, isTrue);

      // P13: Usuário revela temporariamente na sessão
      newController.togglePrivacy();
      expect(newController.obscureValues, isFalse);
      expect(
        newController.hideValuesByDefault,
        isTrue,
      ); // preferência persistida inalterada

      // P14: Reset da privacidade de sessão retorna para o padrão configurado
      newController.resetSessionPrivacy();
      expect(newController.obscureValues, isTrue);
    });
  });

  group('Aparência e Preservação de Identidade Visual Multi-Espaço', () {
    test('A4, A5: Preservação estrita das cores semente PF (Azul) e PJ (Verde) em Light e Dark', () {
      final pfSeed = seedForSpace(true);
      final pjSeed = seedForSpace(false);

      expect(pfSeed, equals(const Color(0xFF2459D4)));
      expect(pjSeed, equals(const Color(0xFF137A63)));

      final lightPfTheme = buildTheme(Brightness.light, seed: pfSeed);
      final darkPfTheme = buildTheme(Brightness.dark, seed: pfSeed);

      final lightPjTheme = buildTheme(Brightness.light, seed: pjSeed);
      final darkPjTheme = buildTheme(Brightness.dark, seed: pjSeed);

      // Garante que o seed de PF nunca é misturado com PJ
      expect(
        lightPfTheme.colorScheme.primary,
        isNot(equals(lightPjTheme.colorScheme.primary)),
      );
      expect(
        darkPfTheme.colorScheme.primary,
        isNot(equals(darkPjTheme.colorScheme.primary)),
      );

      // Garante brilho consistente
      expect(lightPfTheme.brightness, equals(Brightness.light));
      expect(darkPfTheme.brightness, equals(Brightness.dark));
      expect(lightPjTheme.brightness, equals(Brightness.light));
      expect(darkPjTheme.brightness, equals(Brightness.dark));
    });
  });

  group('Tela de Configurações - Widget & UX Tests', () {
    late MemorySessionStorage storage;
    late PreferencesController controller;

    setUp(() {
      storage = MemorySessionStorage();
      controller = PreferencesController(storage: storage);
    });

    Widget createTestApp({double textScale = 1.0}) {
      return MaterialApp(
        theme: buildTheme(Brightness.light, seed: seedForSpace(true)),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: ChangeNotifierProvider<PreferencesController>.value(
            value: controller,
            child: const SettingsScreen(),
          ),
        ),
      );
    }

    testWidgets(
      'A8, A9: Exibe opções de tema e reflete alterações imediatamente',
      (tester) async {
        await controller.load();
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();

        // Verifica seções da tela
        expect(find.text('Aparência'), findsOneWidget);
        expect(find.text('Privacidade'), findsOneWidget);

        // Verifica opções de tema
        expect(find.text('Automático'), findsOneWidget);
        expect(find.text('Claro'), findsOneWidget);
        expect(find.text('Escuro'), findsOneWidget);

        // Alterna para Tema Escuro
        await tester.tap(find.text('Escuro'));
        await tester.pumpAndSettle();

        expect(controller.themeMode, equals(ThemeMode.dark));

        // Alterna para Tema Claro
        await tester.tap(find.text('Claro'));
        await tester.pumpAndSettle();

        expect(controller.themeMode, equals(ThemeMode.light));
      },
    );

    testWidgets(
      'P10, P11: Switch de Ocultar valores por padrão altera o controlador',
      (tester) async {
        await controller.load();
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();

        expect(find.text('Ocultar valores por padrão'), findsOneWidget);
        final switchFinder = find.byType(Switch);
        expect(switchFinder, findsOneWidget);

        // Ativa o switch
        await tester.tap(switchFinder);
        await tester.pumpAndSettle();

        expect(controller.hideValuesByDefault, isTrue);
        expect(controller.obscureValues, isTrue);

        // Desativa o switch
        await tester.tap(switchFinder);
        await tester.pumpAndSettle();

        expect(controller.hideValuesByDefault, isFalse);
      },
    );

    testWidgets(
      'P20: Acessibilidade com texto ampliado a 200% não causa overflow na tela de Configurações',
      (tester) async {
        tester.view.physicalSize = const Size(375 * 2, 812 * 2);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await controller.load();
        await tester.pumpWidget(createTestApp(textScale: 2.0));
        await tester.pumpAndSettle();

        // Garante que renderizou sem erros de overflow
        expect(find.text('Configurações'), findsOneWidget);
        expect(find.text('Aparência'), findsOneWidget);

        // Rola a tela até encontrar a seção Privacidade
        final privacyHeader = find.text('Privacidade');
        await tester.scrollUntilVisible(privacyHeader, 100);
        expect(privacyHeader, findsOneWidget);
      },
    );

    testWidgets(
      'Exibe a versão e build reais do app sincronizados com AppConfig',
      (tester) async {
        await controller.load();
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();

        expect(find.text(appVersionLabel), findsOneWidget);
      },
    );
  });

  group('Privacidade e Navegação no Fluxo Completo (HomeShell & Abas)', () {
    late FakeBackend backend;
    late MemorySessionStorage storage;

    setUp(() {
      backend = FakeBackend();
      storage = MemorySessionStorage();
      backend.routes['GET /spaces/1/payables'] = {'data': []};
      backend.routes['GET /spaces/1/agreements'] = {'data': []};
      backend.routes['GET /spaces/1/accounts'] = {
        'data': [
          {
            'id': 10,
            'name': 'Banco do Brasil',
            'opening_balance': '1250.50',
            'opening_balance_date': '2026-01-01',
            'balance': '1250.50',
            'archived_at': null,
            'opening_adjustments': [],
          },
        ],
      };
      backend.routes['GET /spaces/2/payables'] = {'data': []};
      backend.routes['GET /spaces/2/agreements'] = {'data': []};
      backend.routes['GET /spaces/2/accounts'] = {
        'data': [
          {
            'id': 20,
            'name': 'Itaú PJ',
            'opening_balance': '5000.00',
            'opening_balance_date': '2026-01-01',
            'balance': '5000.00',
            'archived_at': null,
            'opening_adjustments': [],
          },
        ],
      };
    });

    Future<void> launchApp(WidgetTester tester) async {
      await tester.pumpWidget(
        buildApp(
          baseUrl: 'http://api.test/api',
          storage: storage,
          client: backend.client,
        ),
      );
      await tester.pumpAndSettle();

      // Login
      await tester.enterText(
        find.widgetWithText(TextFormField, 'E-mail'),
        'teste@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Senha'),
        'senha-certa',
      );
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'P2, P4, P5, P6, P7, P8, P17: Mascaramento consistente no Dashboard e Contas através de navegação e troca de espaço',
      (tester) async {
        await launchApp(tester);

        // Dashboard PF inicial: saldo disponível visível
        expect(find.text(r'R$ 1.000,00'), findsOneWidget);
        expect(find.text(r'R$ ••••••••'), findsNothing);

        // Ocultar valores via botão no card do Dashboard
        await tester.tap(find.byTooltip('Ocultar saldo'));
        await tester.pumpAndSettle();

        // Dashboard com valor mascarado
        expect(find.text(r'R$ ••••••••'), findsWidgets);
        expect(find.text(r'R$ 1.000,00'), findsNothing);

        // Navega para aba Contas (P4, P5, P6)
        final contasTab = find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Contas'),
        );
        await tester.tap(contasTab);
        await tester.pumpAndSettle();

        // Na aba Contas, o totalizador e o saldo da conta devem estar mascarados
        expect(find.text(r'Saldo total: R$ ••••••••'), findsOneWidget);
        expect(find.text(r'R$ 1.250,50'), findsNothing);
        expect(find.text(r'R$ ••••••••'), findsWidgets);

        // Alterna para PJ (P7: preservação da privacidade na troca de espaço)
        final pjSegment = find.descendant(
          of: find.byType(SegmentedButton<int>),
          matching: find.text('PJ'),
        );
        await tester.tap(pjSegment);
        await tester.pumpAndSettle();

        // Continua mascarado em PJ
        expect(find.text(r'Saldo total: R$ ••••••••'), findsOneWidget);
        expect(find.text(r'R$ 5.000,00'), findsNothing);

        // Retorna ao Dashboard (P8)
        final resumoTab = find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Resumo'),
        );
        await tester.tap(resumoTab);
        await tester.pumpAndSettle();

        // Dashboard PJ mascarado
        expect(find.text(r'R$ ••••••••'), findsWidgets);
        expect(find.text(r'R$ 5.000,00'), findsNothing);

        // Revela os valores novamente
        await tester.tap(find.byTooltip('Mostrar saldo'));
        await tester.pumpAndSettle();

        expect(find.text(r'R$ 5.000,00'), findsOneWidget);
      },
    );

    testWidgets(
      'Menu do Usuário abre Configurações e integra preferências com a Home',
      (tester) async {
        await launchApp(tester);

        // Abre o menu do usuário
        final userButton = find.byTooltip('Conta');
        expect(userButton, findsOneWidget);
        await tester.tap(userButton);
        await tester.pumpAndSettle();

        // Clica em Configurações
        expect(find.text('Configurações'), findsOneWidget);
        await tester.tap(find.text('Configurações'));
        await tester.pumpAndSettle();

        // Tela de Configurações aberta
        expect(find.text('Aparência'), findsOneWidget);
        expect(find.text('Privacidade'), findsOneWidget);

        // Ativa Ocultar valores por padrão
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();

        // Volta para a Home
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();

        // Na Home, os valores agora estão mascarados
        expect(find.text(r'R$ ••••••••'), findsWidgets);
        expect(find.text(r'R$ 1.000,00'), findsNothing);
      },
    );

    testWidgets('Cancelar diálogo de saída PRESERVA o mascaramento da sessão', (
      tester,
    ) async {
      await launchApp(tester);

      // Mascara o saldo
      await tester.tap(find.byTooltip('Ocultar saldo'));
      await tester.pumpAndSettle();
      expect(find.text(r'R$ ••••••••'), findsWidgets);

      // Abre o menu e clica em Sair
      await tester.tap(find.byTooltip('Conta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sair'));
      await tester.pumpAndSettle();

      // Diálogo de confirmação aberto
      expect(find.text('Confirmar saída'), findsOneWidget);

      // Clica em Cancelar
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      // O saldo DEVE continuar mascarado!
      expect(find.text(r'R$ ••••••••'), findsWidgets);
      expect(find.text(r'R$ 1.000,00'), findsNothing);
    });

    testWidgets(
      'Confirmar saída ou expirar sessão restaura privacidade para o padrão configurado',
      (tester) async {
        await launchApp(tester);

        // Mascara o saldo
        await tester.tap(find.byTooltip('Ocultar saldo'));
        await tester.pumpAndSettle();
        expect(find.text(r'R$ ••••••••'), findsWidgets);

        // Abre menu e confirma saída
        await tester.tap(find.byTooltip('Conta'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sair'));
        await tester.pumpAndSettle();

        // Clica no botão Sair do diálogo
        final confirmButton = find.widgetWithText(FilledButton, 'Sair');
        await tester.tap(confirmButton);
        await tester.pumpAndSettle();

        // Sessão foi encerrada (volta para tela de Login)
        expect(find.widgetWithText(TextFormField, 'E-mail'), findsOneWidget);

        // Verifica que o PreferencesController foi resetado para o padrão
        final preferences = Provider.of<PreferencesController>(
          tester.element(find.byType(FinanceApp)),
          listen: false,
        );
        expect(
          preferences.obscureValues,
          equals(preferences.hideValuesByDefault),
        );
      },
    );

    testWidgets(
      'Mascaramento de privacidade estende-se para listagens de consulta em A Receber e A Pagar',
      (tester) async {
        backend.routes['GET /spaces/1/agreements'] = {
          'data': [
            {
              'id': 101,
              'description': 'Consultoria Especializada',
              'total': '3000.00',
              'installment_count': 1,
              'received': '1000.00',
              'remaining': '2000.00',
              'paid_installments': 0,
              'overdue_installments': 0,
              'next_due_date': '2026-11-01',
              'installments': [
                {
                  'id': 501,
                  'agreement_id': 101,
                  'number': 1,
                  'due_date': '2026-11-01',
                  'amount': '3000.00',
                  'received': '1000.00',
                  'remaining': '2000.00',
                  'status': 'partial',
                  'overdue': false,
                },
              ],
            },
          ],
        };
        backend.routes['GET /spaces/1/payables'] = {
          'data': [
            {
              'id': 201,
              'kind': 'outros',
              'description': 'Licença de Software',
              'amount': '1500.00',
              'due_date': '2026-11-05',
              'status': 'open',
              'overdue': false,
              'paid': '0.00',
              'remaining': '1500.00',
              'payment_count': 0,
              'payments': [],
            },
          ],
        };

        await launchApp(tester);

        // Oculta valores no Dashboard
        await tester.tap(find.byTooltip('Ocultar saldo'));
        await tester.pumpAndSettle();

        // Navega para aba A receber
        final aReceberTab = find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('A receber'),
        );
        await tester.tap(aReceberTab);
        await tester.pumpAndSettle();

        // Verifica que os valores estão mascarados no AgreementCard
        expect(find.text('Consultoria Especializada'), findsOneWidget);
        expect(find.text(r'R$ ••••••••'), findsWidgets);
        expect(find.text(r'R$ 2.000,00'), findsNothing);
        expect(find.text('Recebido: ••••••'), findsOneWidget);
        expect(find.text(r'Recebido: R$ 1.000,00'), findsNothing);

        // Navega para aba A pagar
        final aPagarTab = find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('A pagar'),
        );
        await tester.tap(aPagarTab);
        await tester.pumpAndSettle();

        // Verifica que os valores estão mascarados no PayableCard
        expect(find.text('Licença de Software'), findsOneWidget);
        expect(find.text(r'R$ ••••••••'), findsWidgets);
        expect(find.text(r'R$ 1.500,00'), findsNothing);
      },
    );
  });

  group('PreferencesController - Resiliência e Acessibilidade Semântica', () {
    test(
      'Resiliência a exceção no storage: fallback seguro sem travar',
      () async {
        final faultyStorage = _FaultyStorage();
        final controller = PreferencesController(storage: faultyStorage);

        // Não deve lançar exceção
        await controller.load();
        expect(controller.themeMode, equals(ThemeMode.system));
        expect(controller.hideValuesByDefault, isFalse);
        expect(controller.obscureValues, isFalse);

        // Escrita também tolera exceções
        await controller.setThemeMode(ThemeMode.dark);
        expect(controller.themeMode, equals(ThemeMode.dark));
      },
    );

    testWidgets(
      'Acessibilidade: _ThemeOptionTile declara semântica de seleção',
      (tester) async {
        final storage = MemorySessionStorage();
        final controller = PreferencesController(storage: storage);
        await controller.load();

        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider<PreferencesController>.value(
              value: controller,
              child: const SettingsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // O tema inicial é Automático (system), deve ter semântica selected: true
        final autoTile = tester.widget<Semantics>(
          find
              .ancestor(
                of: find.text('Automático'),
                matching: find.byWidgetPredicate(
                  (w) => w is Semantics && w.properties.selected == true,
                ),
              )
              .first,
        );
        expect(autoTile.properties.selected, isTrue);

        // Claro não está selecionado
        final lightTile = tester.widget<Semantics>(
          find
              .ancestor(
                of: find.text('Claro'),
                matching: find.byWidgetPredicate(
                  (w) => w is Semantics && w.properties.selected == false,
                ),
              )
              .first,
        );
        expect(lightTile.properties.selected, isFalse);
      },
    );
  });
}

class _FaultyStorage implements SessionStorage {
  @override
  Future<void> delete(String key) async => throw Exception('Storage error');

  @override
  Future<String?> read(String key) async =>
      throw Exception('Storage corrupted');

  @override
  Future<void> write(String key, String value) async =>
      throw Exception('Storage disk full');
}
