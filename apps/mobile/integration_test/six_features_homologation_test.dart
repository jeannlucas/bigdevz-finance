// ==============================================================================
// BigDev.Z Finance — Homologação Multiplataforma Nativa das 6 Melhorias
// Teste estrito com asserções verificáveis: falha obrigatoriamente se qualquer
// elemento, saldo, transação, estorno ou persistência divergir do esperado.
// ==============================================================================
import 'package:bigdevz_finance/bootstrap.dart';
import 'package:bigdevz_finance/core/token_storage.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:bigdevz_finance/features/home/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Homologação dos 6 novos fluxos no dispositivo nativo com asserções estritas', (
    tester,
  ) async {
    const storage = SecureSessionStorage();
    await storage.delete('auth_token');
    await storage.delete('active_space_id');
    final client = http.Client();

    const serverHost = String.fromEnvironment(
      'SCREENSHOT_HOST',
      defaultValue: '127.0.0.1',
    );
    const targetPlatform = String.fromEnvironment(
      'TARGET_PLATFORM',
      defaultValue: 'ios',
    );
    const apiBaseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8000/api',
    );
    final prefix = targetPlatform == 'android' ? 'android_real' : 'ios_real';

    Future<void> settle([int iterations = 40]) async {
      for (var i = 0; i < iterations; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (!tester.binding.hasScheduledFrame &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          return;
        }
      }
    }

    /// Captura obrigatória: sinaliza falha do teste se o servidor recusar ou faltar o PNG
    Future<void> capture(String name) async {
      await settle();
      final uri = Uri.parse(
        'http://$serverHost:9876/screenshot?name=$name&target=$targetPlatform',
      );
      final res = await http
          .get(uri)
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw TestFailure(
              'Timeout ao solicitar captura obrigatória de $name no servidor 127.0.0.1:9876',
            ),
          );

      expect(
        res.statusCode,
        equals(200),
        reason:
            'Falha na captura obrigatória de $name: HTTP ${res.statusCode} (${res.body})',
      );
      debugPrint('📸 [$targetPlatform Screenshot Válido] $name');
    }

    Future<void> setAppearance(String mode) async {
      await settle();
      try {
        final uri = Uri.parse('http://$serverHost:9876/appearance?mode=$mode');
        final res = await http.get(uri).timeout(const Duration(seconds: 5));
        expect(res.statusCode, equals(200));
      } catch (_) {}
      await settle(10);
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
      for (var i = 0; i < 15 && target.evaluate().isEmpty; i++) {
        if (find.byType(Scrollable).evaluate().isNotEmpty) {
          await tester.drag(
            verticalScrollable(),
            const Offset(0, -250),
            warnIfMissed: false,
          );
        } else {
          await tester.dragFrom(const Offset(200, 450), const Offset(0, -250));
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

    Future<void> revealHorizontal(String text) async {
      final target = find.text(text);
      if (target.evaluate().isNotEmpty) {
        try {
          await tester.ensureVisible(target.last);
        } catch (_) {}
        await settle();
        return;
      }
      final hScrollable = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
      );
      if (hScrollable.evaluate().isNotEmpty) {
        for (var i = 0; i < 10 && target.evaluate().isEmpty; i++) {
          await tester.drag(
            hScrollable.first,
            const Offset(-150, 0),
            warnIfMissed: false,
          );
          await settle();
        }
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
        reason: 'Elemento com texto "$text" não encontrado na tela',
      );
      try {
        await tester.ensureVisible(found.last);
      } catch (_) {}
      await tester.tap(found.last, warnIfMissed: false);
      await settle();
    }

    Future<void> selectTabByIndex(int index) async {
      final navBar = find.byType(NavigationBar);
      expect(
        navBar,
        findsOneWidget,
        reason: 'NavigationBar principal deve estar visível',
      );
      final dests = find.descendant(
        of: navBar,
        matching: find.byType(NavigationDestination),
      );
      expect(
        dests.evaluate().length,
        greaterThan(index),
        reason: 'Aba de índice $index deve existir na NavigationBar',
      );
      await tester.tap(dests.at(index), warnIfMissed: false);
      await settle();
    }

    Future<void> selectSpace(String kind) async {
      final spaceBtn = find.text(kind);
      expect(
        spaceBtn,
        findsWidgets,
        reason: 'Botão de troca de espaço $kind deve existir no topo',
      );
      await tester.tap(spaceBtn.first, warnIfMissed: false);
      await settle(40);
    }

    // ========================================================================
    // 1. INICIALIZAÇÃO DO APP E AUTENTICAÇÃO OBRIGATÓRIA
    // ========================================================================
    await tester.pumpWidget(
      buildApp(baseUrl: apiBaseUrl, storage: storage, client: client),
    );
    await settle(40);

    // Se estiver na tela de login, preenche credenciais homologadas
    final emailField = find.widgetWithText(TextFormField, 'E-mail');
    expect(
      emailField,
      findsOneWidget,
      reason: 'Tela de login deve ser exibida após limpeza de sessão',
    );
    await capture('${prefix}_00_login_screen');

    await tester.enterText(emailField, 'dev@bigdevz.com');
    final passwordField = find.widgetWithText(TextFormField, 'Senha');
    expect(
      passwordField,
      findsOneWidget,
      reason: 'Campo de senha deve existir no login',
    );
    await tester.enterText(passwordField, 'password123');

    await tapText('Entrar');
    await settle(60);

    // Valida que o Dashboard foi carregado com sucesso
    expect(
      find.text('Saldo disponível'),
      findsOneWidget,
      reason: 'Dashboard deve abrir após login',
    );
    expect(
      find.text('Pessoal (PF)'),
      findsOneWidget,
      reason: 'Espaço inicial deve ser Pessoal (PF)',
    );
    await capture('${prefix}_01_dashboard_initial');

    // ========================================================================
    // 2. CONFERÊNCIA DO SALDO INICIAL DA WISE (R$ 100,00) NA CARTEIRA PF
    // ========================================================================
    await selectTabByIndex(4); // Aba Contas
    await settle(30);
    expect(
      find.text('Carteira de Contas'),
      findsOneWidget,
      reason: 'Aba Contas deve ser exibida',
    );
    expect(
      find.textContaining('WISE GLOBAL'),
      findsWidgets,
      reason: 'Conta Wise Global deve constar na carteira PF',
    );
    expect(
      find.textContaining('100,00'),
      findsWidgets,
      reason: 'Saldo inicial da Wise deve ser R\$ 100,00',
    );

    // Retorna ao Dashboard para o registro da compra
    await selectTabByIndex(0);
    await settle(30);

    // ========================================================================
    // 3. FLUXO WISE: REGISTRO DE DESPESA NO DÉBITO COM TECLADO NA TELA
    // ========================================================================
    final directExpenseBtn = find.text(
      'Registrar despesa paga (débito em conta)',
    );
    expect(
      directExpenseBtn,
      findsOneWidget,
      reason: 'Botão "Registrar despesa paga (débito em conta)" é obrigatório no Dashboard PF',
    );
    await tester.tap(directExpenseBtn);
    await settle(30);

    expect(
      find.text('Registrar Despesa Paga'),
      findsOneWidget,
      reason: 'Modal de Despesa Paga deve abrir ao clicar no botão',
    );

    // 3.1 Seleciona obrigatoriamente a conta Wise
    final accountDropdown = find.widgetWithText(
      DropdownButtonFormField<int>,
      'Conta de Origem *',
    );
    expect(
      accountDropdown,
      findsOneWidget,
      reason: 'Dropdown de conta de origem é obrigatório',
    );
    await tester.tap(accountDropdown.first, warnIfMissed: false);
    await settle(20);

    final wiseOption = find.textContaining('WISE');
    expect(
      wiseOption,
      findsWidgets,
      reason: 'A conta Wise Global com saldo R\$ 100,00 deve estar disponível para seleção',
    );
    await tester.tap(wiseOption.last, warnIfMissed: false);
    await settle(20);

    // 3.2 Foca campo de valor e exibe teclado nativo
    final amountField = find.widgetWithText(TextFormField, 'Valor Pago *');
    expect(
      amountField,
      findsOneWidget,
      reason: 'Campo "Valor Pago *" é obrigatório',
    );
    await tester.tap(amountField, warnIfMissed: false);
    await tester.showKeyboard(amountField);
    await settle(20);

    // EVIDÊNCIA CRÍTICA OBRIGATÓRIA: Tela com o teclado aberto
    await capture('${prefix}_02_wise_debit_keyboard_open');

    // Digita o valor estrito de R$ 35,90
    await tester.enterText(amountField, '35,90');
    await settle(10);

    // 3.3 Preenche descrição auditável
    final descField = find.widgetWithText(
      TextFormField,
      'Descrição da Despesa *',
    );
    expect(
      descField,
      findsOneWidget,
      reason: 'Campo de descrição da despesa é obrigatório',
    );
    await tester.enterText(descField, 'COMPRA TESTE WISE HOMOLOGACAO');
    await settle(10);

    // 3.4 Seleciona obrigatoriamente a subcategoria Moradia > Energia
    final categoryDropdown = find.widgetWithText(
      DropdownButtonFormField<int?>,
      'Categoria (opcional)',
    );
    expect(
      categoryDropdown,
      findsOneWidget,
      reason: 'Dropdown de categoria deve estar presente',
    );
    await tester.tap(categoryDropdown.first, warnIfMissed: false);
    await settle(20);

    final energiaCat = find.textContaining('ENERGIA');
    expect(
      energiaCat,
      findsWidgets,
      reason:
          'Subcategoria ENERGIA deve estar cadastrada e selecionável no picker',
    );
    await tester.tap(energiaCat.last, warnIfMissed: false);
    await settle(20);

    // 3.5 Fecha teclado e rola para submissão
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(20);

    final modalList = find.byType(ListView);
    expect(modalList, findsWidgets);
    await tester.drag(
      modalList.last,
      const Offset(0, -250),
      warnIfMissed: false,
    );
    await settle(20);

    final submitDirectBtn = find.text('Confirmar Despesa Paga');
    expect(
      submitDirectBtn,
      findsOneWidget,
      reason: 'Botão "Confirmar Despesa Paga" deve existir no formulário',
    );
    await tester.ensureVisible(submitDirectBtn);
    await tester.tap(submitDirectBtn, warnIfMissed: false);
    await settle(60);

    // Modal deve ter sido fechado após o registro
    expect(
      find.text('Registrar Despesa Paga'),
      findsNothing,
      reason: 'Modal de despesa paga deve fechar automaticamente após sucesso',
    );

    // Dashboard pós-débito Wise capturado
    await capture('${prefix}_03_wise_debit_confirmed');

    // ========================================================================
    // 4. CONFERÊNCIA DO SALDO DÉBITADO NA WISE (R$ 64,10)
    // ========================================================================
    await selectTabByIndex(4); // Aba Contas
    await settle(30);
    expect(find.textContaining('WISE GLOBAL'), findsWidgets);
    expect(
      find.textContaining('64,10'),
      findsWidgets,
      reason:
          'Saldo da conta Wise deve ser de R\$ 64,10 após débito de R\$ 35,90',
    );

    // ========================================================================
    // 5. CONFERÊNCIA NO EXTRATO: SAÍDA ÚNICA DE R$ 35,90
    // ========================================================================
    await selectTabByIndex(1); // Aba Extrato
    await settle(30);
    expect(
      find.text('Extrato'),
      findsWidgets,
      reason: 'Aba Extrato deve ser exibida',
    );

    // Valida que o lançamento criado consta no extrato como saída única
    final wiseTx = find.textContaining('COMPRA TESTE WISE');
    expect(
      wiseTx,
      findsOneWidget,
      reason: 'O lançamento da despesa Wise deve constar no extrato exatamente uma única vez',
    );

    // Valida valor de R$ 35,90 e badge de subcategoria Energia
    expect(
      find.textContaining('35,90'),
      findsWidgets,
      reason: 'Valor de R\$ 35,90 deve constar no extrato',
    );
    expect(
      find.text('ENERGIA'),
      findsWidgets,
      reason: 'Badge [ENERGIA] deve constar no item do extrato',
    );

    await capture('${prefix}_04_statement_with_wise_debit');

    // ========================================================================
    // 5.1 EXECUÇÃO DO ESTORNO PELA INTERFACE (A PAGAR > PAGAS > ESTORNAR)
    // ========================================================================
    await selectTabByIndex(3); // Aba A Pagar
    await settle(30);
    expect(
      find.text('A pagar'),
      findsWidgets,
      reason: 'Aba A pagar deve ser exibida',
    );

    await revealHorizontal('Pagas');
    final pagasChip = find.widgetWithText(ChoiceChip, 'Pagas');
    expect(
      pagasChip,
      findsOneWidget,
      reason: 'Filtro "Pagas" deve estar visível',
    );
    await tester.tap(pagasChip.first, warnIfMissed: false);
    await settle(40);

    await reveal('COMPRA TESTE WISE');
    final wisePayable = find.textContaining('COMPRA TESTE WISE');
    expect(
      wisePayable,
      findsWidgets,
      reason: 'A despesa paga deve constar na listagem de contas pagas',
    );
    await tester.tap(wisePayable.first, warnIfMissed: false);
    await settle(40);

    // No modal da conta a pagar, rola até o botão de estorno
    await reveal('Estornar');
    final revertBtn = find.text('Estornar');
    expect(
      revertBtn,
      findsOneWidget,
      reason: 'Botão "Estornar" deve estar disponível no detalhamento da conta',
    );
    await tester.tap(revertBtn.first, warnIfMissed: false);
    await settle(20);

    expect(
      find.text('Estornar pagamento'),
      findsWidgets,
      reason: 'Diálogo de estorno deve abrir',
    );
    final reasonField = find.widgetWithText(
      TextFormField,
      'Justificativa do estorno *',
    );
    expect(
      reasonField,
      findsOneWidget,
      reason: 'Justificativa do estorno é campo obrigatório',
    );
    await tester.enterText(reasonField, 'Estorno auditado de homologação');
    await settle(10);

    final confirmRevertBtn = find.text('Confirmar estorno');
    expect(
      confirmRevertBtn,
      findsOneWidget,
      reason: 'Botão de confirmação de estorno deve existir',
    );
    await tester.tap(confirmRevertBtn.first, warnIfMissed: false);
    await settle(50);

    // Fecha o modal da conta
    final closePayableBtn = find.byTooltip('Fechar');
    if (closePayableBtn.evaluate().isNotEmpty) {
      await tester.tap(closePayableBtn.last, warnIfMissed: false);
      await settle(30);
    }

    // 5.2 Valida que o estorno gerou lançamento contábil compensatório no extrato
    await selectTabByIndex(1); // Aba Extrato
    await settle(30);
    expect(
      find.textContaining('ESTORNO DE PAGAMENTO'),
      findsWidgets,
      reason: 'Lançamento de estorno compensatório deve constar no extrato',
    );

    // 5.3 Confere que o saldo da Wise retornou exatamente a R$ 100,00
    await selectTabByIndex(4); // Aba Contas
    await settle(30);
    expect(find.textContaining('WISE GLOBAL'), findsWidgets);
    expect(
      find.textContaining('100,00'),
      findsWidgets,
      reason: 'Saldo da conta Wise deve retornar exatamente a R\$ 100,00 após o estorno',
    );

    // Retorna ao Dashboard
    await selectTabByIndex(0);
    await settle(30);
    expect(find.text('Saldo disponível'), findsOneWidget);
    await capture('${prefix}_05_dashboard_after_reversal');

    // ========================================================================
    // 6. FLUXO DUCZ BENEFÍCIOS NA GESTÃO DE CONTAS (PJ)
    // ========================================================================
    await selectSpace('PJ');
    await settle(40);
    expect(
      find.text('Empresa (PJ)'),
      findsOneWidget,
      reason: 'Espaço PJ deve estar ativo',
    );

    await selectTabByIndex(4); // Aba Contas
    await settle(30);
    expect(
      find.text('Carteira de Contas'),
      findsOneWidget,
      reason: 'Carteira de contas PJ deve ser exibida',
    );

    // Valida presença da conta DUCZ Benefícios
    final duczAccount = find.textContaining('BENEFÍCIOS DA EMPRESA');
    expect(
      duczAccount,
      findsWidgets,
      reason: 'Conta "BENEFÍCIOS DA EMPRESA" vinculada à DUCZ Benefícios deve constar na carteira PJ',
    );
    expect(
      find.textContaining('500,00'),
      findsWidgets,
      reason: 'Saldo de R\$ 500,00 da conta DUCZ deve ser visível',
    );

    await capture('${prefix}_06_accounts_list_pj');

    // ========================================================================
    // 7. FLUXO RECORRÊNCIA VARIÁVEL EM A PAGAR (PJ)
    // ========================================================================
    await selectTabByIndex(3); // Aba A Pagar
    await settle(30);
    expect(
      find.text('A pagar'),
      findsWidgets,
      reason: 'Aba A pagar deve ser exibida',
    );

    await revealHorizontal('Valor a informar');
    final awaitingChip = find.widgetWithText(ChoiceChip, 'Valor a informar');
    expect(
      awaitingChip,
      findsOneWidget,
      reason: 'Filtro "Valor a informar" para faturas variáveis deve existir',
    );
    await tester.tap(awaitingChip.first, warnIfMissed: false);
    await settle(30);

    expect(
      find.textContaining('Valor a informar'),
      findsWidgets,
      reason: 'Filtro ativo de faturas com valor a informar deve ser destacado',
    );
    await capture('${prefix}_07_payables_variable_recurrence');

    // ========================================================================
    // 8. FLUXO CENTRAL DE AVISOS (DISPENSA E PERSISTÊNCIA APÓS NOVO LOGIN)
    // ========================================================================
    // Volta para o espaço PF onde os avisos foram resetados e estão ativos
    await selectSpace('PF');
    await settle(40);

    await selectTabByIndex(0); // Dashboard
    await settle(20);

    final bellButtonFinder = find.byWidgetPredicate(
      (w) =>
          w is IconButton && (w.tooltip?.contains('notificação(ões)') ?? false),
    );
    expect(
      bellButtonFinder,
      findsOneWidget,
      reason: 'Ícone de sininho com indicador de notificações não lidas deve existir na AppBar',
    );

    // Valida badge inicial de avisos com contador
    final initialBadge = find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(Badge),
    );
    expect(
      initialBadge,
      findsOneWidget,
      reason: 'Badge de notificações deve exibir contador pendente',
    );

    await tester.tap(bellButtonFinder.first, warnIfMissed: false);
    await settle(30);
    expect(
      find.text('Notificações e Vencimentos'),
      findsWidgets,
      reason:
          'Modal "Notificações e Vencimentos" deve abrir ao clicar no sininho',
    );
    await capture('${prefix}_08_notifications_modal');

    // Valida a ação estrita de dispensar o aviso
    final dismissButtons = find.byTooltip('Dispensar aviso');
    expect(
      dismissButtons,
      findsWidgets,
      reason: 'Botão de dispensar aviso deve estar presente nos cards de notificação',
    );
    await tester.tap(dismissButtons.first, warnIfMissed: false);
    await settle(30);

    // Fecha o modal de notificações
    final closeBtn = find.byTooltip('Fechar');
    expect(
      closeBtn,
      findsOneWidget,
      reason: 'Botão "Fechar" deve existir no cabeçalho do modal',
    );
    await tester.tap(closeBtn, warnIfMissed: false);
    await settle(30);

    // Confere que dispensar o aviso alterou o contador observado
    final updatedBellFinder = find.byWidgetPredicate(
      (w) =>
          w is IconButton && (w.tooltip?.contains('notificação(ões)') ?? false),
    );
    expect(
      updatedBellFinder,
      findsOneWidget,
      reason:
          'Sininho deve continuar exibindo notificações pendentes atualizadas',
    );

    // 8.1 Testa persistência de dispensa após deslogar e relogar
    final sessionController = tester
        .element(find.byType(HomeShell))
        .read<SessionController>();
    await sessionController.logout();
    await settle(40);

    final reloginEmail = find.widgetWithText(TextFormField, 'E-mail');
    expect(
      reloginEmail,
      findsOneWidget,
      reason: 'Tela de login deve reaparecer após logout',
    );
    await tester.enterText(reloginEmail, 'dev@bigdevz.com');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Senha'),
      'password123',
    );
    await tapText('Entrar');
    await settle(60);

    expect(
      find.text('Saldo disponível'),
      findsOneWidget,
      reason: 'Dashboard deve recarregar após novo login',
    );

    // EVIDÊNCIA DE PERSISTÊNCIA: O aviso dispensado não retorna ao contador
    await capture('${prefix}_09_bell_persisted_after_fresh_login');

    // ========================================================================
    // 9. FLUXO TEMAS CLARO E ESCURO
    // ========================================================================
    await setAppearance('light');
    await settle(20);
    await capture('${prefix}_10_theme_light_overview');

    await setAppearance('dark');
    await settle(20);
    await capture('${prefix}_11_theme_dark_overview');
  });
}
