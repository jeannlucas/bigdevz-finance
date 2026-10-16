import 'dart:async';

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
    test('SEC-04: Resiliência a exceção no storage: fallback conservador fail-closed (valores ocultos por segurança)', () async {
      final faultyStorage = _FaultyStorage();
      final controller = PreferencesController(storage: faultyStorage);

      // Não deve lançar exceção e deve proteger os valores financeiros (fail-closed)
      await controller.load();
      expect(controller.themeMode, equals(ThemeMode.system));
      expect(controller.hideValuesByDefault, isFalse);
      expect(
        controller.obscureValues,
        isTrue,
      ); // Fail-closed seguro: valores protegidos
      expect(controller.hasReadError, isTrue);

      // Escrita também tolera exceções
      await controller.setThemeMode(ThemeMode.dark);
      expect(controller.themeMode, equals(ThemeMode.dark));
    });

    test('SEC-01: Preferência ausente no storage mantém padrão aprovado do produto (visível)', () async {
      final storage = MemorySessionStorage();
      final controller = PreferencesController(storage: storage);
      await controller.load();

      expect(controller.isLoaded, isTrue);
      expect(controller.hasReadError, isFalse);
      expect(controller.hideValuesByDefault, isFalse);
      expect(controller.obscureValues, isFalse);
    });

    test('SEC-02 e SEC-03: Preferências explícitas true e false são rigorosamente respeitadas', () async {
      final storage = MemorySessionStorage();
      await storage.write(PreferencesController.hideByDefaultKey, 'true');
      final cTrue = PreferencesController(storage: storage);
      await cTrue.load();
      expect(cTrue.hideValuesByDefault, isTrue);
      expect(cTrue.obscureValues, isTrue);

      await storage.write(PreferencesController.hideByDefaultKey, 'false');
      final cFalse = PreferencesController(storage: storage);
      await cFalse.load();
      expect(cFalse.hideValuesByDefault, isFalse);
      expect(cFalse.obscureValues, isFalse);
    });

    test('SEC-05: Falha na leitura do tema NÃO contamina nem bloqueia a privacidade financeira', () async {
      final selectiveStorage = _SelectiveFaultyStorage(
        faultyTheme: true,
        hideVal: 'false',
      );
      final controller = PreferencesController(storage: selectiveStorage);

      await controller.load();
      // Tema recua para o padrão do sistema
      expect(controller.themeMode, equals(ThemeMode.system));
      // Privacidade financeira foi lida com sucesso e respeitada (false = visível)
      expect(controller.hideValuesByDefault, isFalse);
      expect(controller.obscureValues, isFalse);
      expect(controller.hasReadError, isFalse);
    });

    test('SEC-06: Falha de gravação de preferência mantém estado seguro em memória para a sessão ativa', () async {
      final faultyStorage = _FaultyStorage();
      final controller = PreferencesController(storage: faultyStorage);
      await controller.load();

      // Altera na sessão; falha na escrita retorna false e não propaga exceção
      final success = await controller.setHideValuesByDefault(true);
      expect(success, isFalse);
      expect(controller.hideValuesByDefault, isFalse);
      expect(controller.obscureValues, isTrue);
    });

    test('SEC-07: Preferência corrompida / formato inesperado aciona fallback fail-closed (oculto)', () async {
      final storage = MemorySessionStorage();
      await storage.write(
        PreferencesController.hideByDefaultKey,
        'corrupted_value_xyz',
      );
      final controller = PreferencesController(storage: storage);

      await controller.load();
      expect(controller.isLoaded, isTrue);
      expect(controller.hasReadError, isTrue);
      expect(controller.obscureValues, isTrue); // Valores protegidos
    });

    test('SEC-08: Estado inicial antes de load() é fail-closed (obscureValues = true) prevenindo flicker', () {
      final storage = MemorySessionStorage();
      final controller = PreferencesController(storage: storage);

      // Antes de load(), o estado é conservador para prevenir exposição de dados no boot
      expect(controller.isLoaded, isFalse);
      expect(controller.obscureValues, isTrue);
    });

    test('SEC-09: resetSessionPrivacy() durante carga pendente (!isLoaded) mantém obscureValues = true', () {
      final completer = Completer<String?>();
      final delayedStorage = _DelayedStorage(completer);
      final controller = PreferencesController(storage: delayedStorage);

      // Dispara carga assíncrona que fica pendente
      unawaited(controller.load());
      expect(controller.isLoaded, isFalse);
      expect(controller.obscureValues, isTrue);

      // Simula reset acionado por SessionStateSignedOut durante o boot antes da carga terminar
      controller.resetSessionPrivacy();

      // obscureValues DEVE continuar true (protegido contra desarme prematuro)
      expect(controller.obscureValues, isTrue);
    });

    test('SEC-W01: setHideValuesByDefault retorna false e mantém hideValuesByDefault inalterado em falha de escrita', () async {
      final storage = _WriteFaultyStorage();
      final controller = PreferencesController(storage: storage);
      await controller.load();
      expect(controller.hideValuesByDefault, isFalse);
      expect(controller.obscureValues, isFalse);

      final success = await controller.setHideValuesByDefault(true);
      expect(success, isFalse);
      expect(
        controller.hideValuesByDefault,
        isFalse,
      ); // Não altera o valor persistido
      expect(
        controller.obscureValues,
        isTrue,
      ); // Fail-closed protege a sessão atual
    });

    test('SEC-W02: Novo controller lendo storage após falha de escrita mantém valor anterior honesto', () async {
      final storage = _WriteFaultyStorage();
      final controller1 = PreferencesController(storage: storage);
      await controller1.load();
      await controller1.setHideValuesByDefault(true);

      final controller2 = PreferencesController(storage: storage);
      await controller2.load();
      expect(controller2.hideValuesByDefault, isFalse);
      expect(controller2.obscureValues, isFalse);
    });

    test('SEC-W03: Bloqueio de concorrência: chamadas paralelas durante isSavingPrivacy são rejeitadas', () async {
      final completer = Completer<void>();
      final slowStorage = _SlowStorage(completer);
      final controller = PreferencesController(storage: slowStorage);
      await controller.load();

      final future1 = controller.setHideValuesByDefault(true);
      expect(controller.isSavingPrivacy, isTrue);

      final future2 = controller.setHideValuesByDefault(true);
      final success2 = await future2;
      expect(success2, isFalse);

      completer.complete();
      final success1 = await future1;
      expect(success1, isTrue);
      expect(controller.isSavingPrivacy, isFalse);
      expect(controller.hideValuesByDefault, isTrue);
    });

    test('SEC-W04: Chamada no-op para o mesmo estado retorna true sem reescrever no storage', () async {
      final storage = MemorySessionStorage();
      final controller = PreferencesController(storage: storage);
      await controller.load();
      await controller.setHideValuesByDefault(true);

      final success = await controller.setHideValuesByDefault(true);
      expect(success, isTrue);
      expect(controller.isSavingPrivacy, isFalse);
    });

    test('SEC-W05: setThemeMode retorna false em caso de falha de persistência mas mantém tema ativo na sessão', () async {
      final storage = _WriteFaultyStorage();
      final controller = PreferencesController(storage: storage);
      await controller.load();
      expect(controller.themeMode, equals(ThemeMode.system));

      final success = await controller.setThemeMode(ThemeMode.dark);
      expect(success, isFalse);
      expect(
        controller.themeMode,
        equals(ThemeMode.dark),
      ); // Mantém na sessão atual sem flicker
    });

    test('SEC-W06: Falha ao tentar desativar preferência previamente true mantém hideValuesByDefault = true', () async {
      final storage = _WriteFaultyStorage();
      storage.failWrite = false;
      final controller = PreferencesController(storage: storage);
      await controller.load();

      // Grava com sucesso primeiro
      final ok = await controller.setHideValuesByDefault(true);
      expect(ok, isTrue);
      expect(controller.hideValuesByDefault, isTrue);
      expect(controller.obscureValues, isTrue);

      // Agora ativa a falha de escrita e tenta desativar
      storage.failWrite = true;
      final success = await controller.setHideValuesByDefault(false);
      expect(success, isFalse);
      expect(
        controller.hideValuesByDefault,
        isTrue,
      ); // Permanece true honestamente
    });

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

    testWidgets(
      'SEC-08 (Widget Anti-flicker): Durante carregamento assíncrono atrasado do storage, saldos já montam mascarados',
      (tester) async {
        final completer = Completer<String?>();
        final delayedStorage = _DelayedStorage(completer);
        final controller = PreferencesController(storage: delayedStorage);

        // Dispara carga mas NÃO completa ainda o Future do storage
        unawaited(controller.load());

        // Monta a interface observando o controller em estado não carregado (_loaded == false)
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light, seed: seedForSpace(true)),
            home: ChangeNotifierProvider<PreferencesController>.value(
              value: controller,
              child: Builder(
                builder: (context) {
                  final obscure = context
                      .watch<PreferencesController>()
                      .obscureValues;
                  return Scaffold(
                    body: Text(obscure ? r'R$ ••••••••' : r'R$ 5.432,10'),
                  );
                },
              ),
            ),
          ),
        );

        // ANTES do completer resolver: valor financeiro real NÃO PODE estar na tela!
        expect(find.text(r'R$ 5.432,10'), findsNothing);
        expect(find.text(r'R$ ••••••••'), findsOneWidget);

        // Completa o carregamento com preferência 'false' (usuário optou por ver)
        completer.complete('false');
        await tester.pumpAndSettle();

        // Agora que carregou explicitamente false, o saldo é revelado com segurança
        expect(find.text(r'R$ 5.432,10'), findsOneWidget);
        expect(find.text(r'R$ ••••••••'), findsNothing);
      },
    );

    testWidgets(
      'SEC-W08: Switch de privacidade fica desabilitado e mostra subtítulo de salvamento durante isSavingPrivacy',
      (tester) async {
        final completer = Completer<void>();
        final slowStorage = _SlowStorage(completer);
        final controller = PreferencesController(storage: slowStorage);
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

        unawaited(controller.setHideValuesByDefault(true));
        await tester.pump();

        expect(find.text('Salvando preferência...'), findsOneWidget);
        final switchWidget = tester.widget<Switch>(find.byType(Switch));
        expect(switchWidget.onChanged, isNull);

        completer.complete();
        await tester.pumpAndSettle();

        expect(find.text('Salvando preferência...'), findsNothing);
        expect(
          find.text('Iniciar com os valores financeiros ocultos.'),
          findsOneWidget,
        );
        final updatedSwitch = tester.widget<Switch>(find.byType(Switch));
        expect(updatedSwitch.onChanged, isNotNull);
      },
    );

    testWidgets(
      'SEC-W09 e SEC-W10: Falha de escrita no Switch exibe SnackBar de erro com ação Tentar novamente e suporta retries sucessivos',
      (tester) async {
        final storage = _WriteFaultyStorage();
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

        // 1. Tenta ativar o switch com falha simulada de disco
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();

        // SnackBar de erro exibido
        expect(
          find.text('Não foi possível salvar a preferência de privacidade.'),
          findsOneWidget,
        );
        expect(find.text('Tentar novamente'), findsOneWidget);

        // O switch permanece falso porque a escrita falhou
        expect(controller.hideValuesByDefault, isFalse);
        final switchWidget = tester.widget<Switch>(find.byType(Switch));
        expect(switchWidget.value, isFalse);

        // 2. Clica em "Tentar novamente" mantendo failWrite = true (segunda falha)
        await tester.tap(find.text('Tentar novamente'));
        await tester.pumpAndSettle();

        // O SnackBar é reapresentado e o botão de retry continua acessível
        expect(
          find.text('Não foi possível salvar a preferência de privacidade.'),
          findsOneWidget,
        );
        expect(find.text('Tentar novamente'), findsOneWidget);
        expect(controller.hideValuesByDefault, isFalse);

        // 3. Agora o storage é corrigido e o usuário clica novamente em retry
        storage.failWrite = false;
        await tester.tap(find.text('Tentar novamente'));
        await tester.pumpAndSettle();

        // Agora salvou com sucesso no storage
        expect(controller.hideValuesByDefault, isTrue);
        final finalSwitch = tester.widget<Switch>(find.byType(Switch));
        expect(finalSwitch.value, isTrue);
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

class _SelectiveFaultyStorage implements SessionStorage {
  _SelectiveFaultyStorage({this.faultyTheme = false, this.hideVal});

  final bool faultyTheme;
  final String? hideVal;

  @override
  Future<void> delete(String key) async {}

  @override
  Future<String?> read(String key) async {
    if (key == PreferencesController.themeModeKey && faultyTheme) {
      throw Exception('Theme storage error');
    }
    if (key == PreferencesController.hideByDefaultKey) {
      return hideVal;
    }
    return null;
  }

  @override
  Future<void> write(String key, String value) async {}
}

class _DelayedStorage implements SessionStorage {
  _DelayedStorage(this.completer);

  final Completer<String?> completer;

  @override
  Future<void> delete(String key) async {}

  @override
  Future<String?> read(String key) async {
    if (key == PreferencesController.hideByDefaultKey) {
      return completer.future;
    }
    return null;
  }

  @override
  Future<void> write(String key, String value) async {}
}

class _WriteFaultyStorage implements SessionStorage {
  _WriteFaultyStorage();

  final Map<String, String> _data = {};
  bool failWrite = true;

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    return _data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) {
      throw Exception('Storage disk full / write fault');
    }
    _data[key] = value;
  }
}

class _SlowStorage implements SessionStorage {
  _SlowStorage(this.completer);

  final Completer<void> completer;
  final Map<String, String> _data = {};

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    await completer.future;
    _data[key] = value;
  }
}
