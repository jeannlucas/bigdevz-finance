import 'package:bigdevz_finance/bootstrap.dart';
import 'package:bigdevz_finance/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';

void main() {
  late FakeBackend backend;
  late MemorySessionStorage storage;

  setUp(() {
    backend = FakeBackend();
    storage = MemorySessionStorage();
    // Rotas necessárias para as abas adicionais ao testar navegação do HomeShell
    backend.routes['GET /spaces/1/payables'] = {'data': []};
    backend.routes['GET /spaces/1/agreements'] = {'data': []};
    backend.routes['GET /spaces/1/accounts'] = {'data': []};
    backend.routes['GET /spaces/1/statement'] = {'data': []};
    backend.routes['GET /spaces/1/loans'] = {'data': []};
    backend.routes['GET /spaces/2/payables'] = {'data': []};
    backend.routes['GET /spaces/2/agreements'] = {'data': []};
    backend.routes['GET /spaces/2/accounts'] = {'data': []};
    backend.routes['GET /spaces/2/statement'] = {'data': []};
    backend.routes['GET /spaces/2/loans'] = {'data': []};
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

    // Login com credenciais válidas do FakeBackend
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
    'HomeShell: renderiza espaço PF padrão com tema Azul Profundo e dados de PF',
    (tester) async {
      await launchApp(tester);

      // Valida espaço inicial PF
      expect(find.text('Saldo disponível'), findsOneWidget);
      expect(find.text(r'R$ 1.000,00'), findsOneWidget);
      expect(find.text('Pessoal (PF)'), findsOneWidget);

      // Valida que o tema aplicado é o de PF
      final themeContext = tester.element(find.text('Saldo disponível'));
      final currentPrimary = Theme.of(themeContext).colorScheme.primary;
      final expectedPfPrimary = buildTheme(
        Brightness.light,
        seed: seedForSpace(true),
      ).colorScheme.primary;
      expect(currentPrimary, equals(expectedPfPrimary));
    },
  );

  testWidgets(
    'HomeShell: alternância PF -> PJ altera tema para Verde Esmeralda e isola dados',
    (tester) async {
      await launchApp(tester);

      // Inicialmente PF
      expect(find.text(r'R$ 1.000,00'), findsOneWidget);
      expect(find.text('Pessoal (PF)'), findsOneWidget);

      // Alterna para PJ no seletor de espaços
      final pjSegment = find.descendant(
        of: find.byType(SegmentedButton<int>),
        matching: find.text('PJ'),
      );
      expect(pjSegment, findsOneWidget);
      await tester.tap(pjSegment);
      await tester.pumpAndSettle();

      // Confirma que agora estamos em PJ
      expect(find.text('Empresa (PJ)'), findsOneWidget);
      expect(find.text(r'R$ 5.000,00'), findsOneWidget);
      expect(find.text(r'R$ 1.000,00'), findsNothing);

      // Confirma que o tema foi atualizado para Verde Esmeralda (PJ)
      final themeContext = tester.element(find.text('Saldo disponível'));
      final currentPrimary = Theme.of(themeContext).colorScheme.primary;
      final expectedPjPrimary = buildTheme(
        Brightness.light,
        seed: seedForSpace(false),
      ).colorScheme.primary;
      expect(currentPrimary, equals(expectedPjPrimary));
      expect(
        expectedPjPrimary,
        isNot(
          equals(
            buildTheme(
              Brightness.light,
              seed: seedForSpace(true),
            ).colorScheme.primary,
          ),
        ),
      );

      // Alterna de volta para PF
      final pfSegment = find.descendant(
        of: find.byType(SegmentedButton<int>),
        matching: find.text('PF'),
      );
      await tester.tap(pfSegment);
      await tester.pumpAndSettle();

      // Confirma restauração dos dados e tema de PF
      expect(find.text('Pessoal (PF)'), findsOneWidget);
      expect(find.text(r'R$ 1.000,00'), findsOneWidget);
      expect(find.text(r'R$ 5.000,00'), findsNothing);

      final restoredContext = tester.element(find.text('Saldo disponível'));
      expect(
        Theme.of(restoredContext).colorScheme.primary,
        equals(
          buildTheme(
            Brightness.light,
            seed: seedForSpace(true),
          ).colorScheme.primary,
        ),
      );
    },
  );

  testWidgets(
    'HomeShell: ocultação de saldo funciona e privacidade é preservada durante navegação entre abas',
    (tester) async {
      await launchApp(tester);

      // Saldo visível inicialmente
      expect(find.text(r'R$ 1.000,00'), findsOneWidget);
      expect(find.text(r'R$ ••••••••'), findsNothing);

      // Ocultar saldo clicando no botão do olho
      final hideButton = find.byTooltip('Ocultar saldo');
      expect(hideButton, findsOneWidget);
      await tester.tap(hideButton);
      await tester.pump();

      // Saldo agora está mascarado
      expect(find.text(r'R$ ••••••••'), findsWidgets);
      expect(find.text(r'R$ 1.000,00'), findsNothing);

      // Tooltip mudou para 'Mostrar saldo'
      final showButton = find.byTooltip('Mostrar saldo');
      expect(showButton, findsOneWidget);

      // Navegar para outra aba (Contas) e retornar para Dashboard
      final contasTab = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Contas'),
      );
      await tester.tap(contasTab);
      await tester.pumpAndSettle();

      final resumoTab = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Dashboard'),
      );
      await tester.tap(resumoTab);
      await tester.pumpAndSettle();

      // FINANCE-UX-01: privacidade persiste durante navegação na sessão
      expect(find.text(r'R$ ••••••••'), findsWidgets);
      expect(find.text(r'R$ 1.000,00'), findsNothing);

      // Revelar novamente
      await tester.tap(find.byTooltip('Mostrar saldo'));
      await tester.pump();

      expect(find.text(r'R$ 1.000,00'), findsOneWidget);
    },
  );

  testWidgets(
    'HomeShell: atalhos rápidos do Dashboard navegam para abas correspondentes',
    (tester) async {
      await launchApp(tester);

      // Botão 'A pagar' no grid de ações rápidas navega para a aba 'A pagar'
      final payShortcut = find.descendant(
        of: find.byType(InkWell),
        matching: find.text('A pagar'),
      );
      expect(payShortcut, findsWidgets);
      await tester.tap(payShortcut.first);
      await tester.pumpAndSettle();

      expect(find.text('Nova conta a pagar'), findsOneWidget);

      // Retorna para o Dashboard
      final resumoTab = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Dashboard'),
      );
      await tester.tap(resumoTab);
      await tester.pumpAndSettle();

      // Botão 'A receber' navega para 'Contas a receber'
      final receiveShortcut = find.descendant(
        of: find.byType(InkWell),
        matching: find.text('A receber'),
      );
      expect(receiveShortcut, findsWidgets);
      await tester.tap(receiveShortcut.first);
      await tester.pumpAndSettle();

      expect(find.text('Contas a receber'), findsOneWidget);

      // Retorna para o Dashboard
      await tester.tap(resumoTab);
      await tester.pumpAndSettle();

      // Botão 'Contas' no Dashboard navega para a aba de 'Contas' (onde accounts está vazio)
      final accountsShortcut = find.descendant(
        of: find.byType(InkWell),
        matching: find.text('Contas'),
      );
      expect(accountsShortcut, findsWidgets);
      await tester.tap(accountsShortcut.first);
      await tester.pumpAndSettle();

      expect(find.text('Nenhuma conta neste espaço'), findsOneWidget);
    },
  );

  testWidgets(
    'HomeShell: em largura >= 840 exibe Top Bar superior com navegação desktop, perfil clicável e sininho',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await launchApp(tester);

      // Em desktop, não deve renderizar NavigationBar inferior
      expect(find.byType(NavigationBar), findsNothing);

      // Deve renderizar itens da Top Bar superior
      expect(find.text('Dashboard'), findsWidgets);
      expect(find.text('Extrato'), findsOneWidget);
      expect(find.text('A receber'), findsWidgets);
      expect(find.text('A pagar'), findsWidgets);
      expect(find.text('Contas'), findsWidgets);
      expect(find.text('Empréstimos'), findsNothing);

      // Clicar em Extrato navega para a aba de Extrato
      await tester.tap(find.text('Extrato'));
      await tester.pumpAndSettle();

      expect(find.text('Nenhuma movimentação encontrada'), findsOneWidget);

      // Pill de perfil do usuário exibe o nome e clicá-lo abre o modal de edição
      expect(find.text('Pessoa Teste'), findsOneWidget);
      await tester.tap(find.text('Pessoa Teste'));
      await tester.pumpAndSettle();

      expect(find.text('Editar perfil'), findsOneWidget);
      // Fecha modal de perfil
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      // Sininho de notificações está presente na Top Bar
      expect(find.byTooltip('Notificações'), findsOneWidget);
      await tester.tap(find.byTooltip('Notificações'));
      await tester.pumpAndSettle();

      expect(find.text('Notificações e Vencimentos'), findsOneWidget);
    },
  );
}
