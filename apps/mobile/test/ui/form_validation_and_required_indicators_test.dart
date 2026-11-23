import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/core/money.dart';
import 'package:bigdevz_finance/features/accounts/account.dart';
import 'package:bigdevz_finance/features/accounts/account_edit_screen.dart';
import 'package:bigdevz_finance/features/accounts/account_form_screen.dart';
import 'package:bigdevz_finance/features/accounts/accounts_repository.dart';
import 'package:bigdevz_finance/features/accounts/opening_adjustments.dart';
import 'package:bigdevz_finance/features/agreements/agreement_form_screen.dart';
import 'package:bigdevz_finance/features/agreements/agreements_repository.dart';
import 'package:bigdevz_finance/features/agreements/receipt_attempts.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/auth/auth_repository.dart';
import 'package:bigdevz_finance/features/auth/session_controller.dart';
import 'package:bigdevz_finance/features/categories/categories_repository.dart';
import 'package:bigdevz_finance/features/payables/payable.dart';
import 'package:bigdevz_finance/features/payables/payable_creations.dart';
import 'package:bigdevz_finance/features/payables/payable_edit_screen.dart';
import 'package:bigdevz_finance/features/payables/payable_form_screen.dart';
import 'package:bigdevz_finance/features/payables/payables_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../support/fake_backend.dart';

const pf = Space(id: 1, kind: 'PF', name: 'Pessoal');
const pj = Space(id: 2, kind: 'PJ', name: 'BigDev.Z LTDA');

void main() {
  late FakeBackend backend;
  late ApiClient api;
  late MemorySessionStorage storage;
  late SessionController session;

  setUp(() {
    backend = FakeBackend();
    backend.overrides['GET /spaces/1/categories'] = (_) => http.Response(
      '{"data":[]}',
      200,
      headers: {'content-type': 'application/json'},
    );
    backend.overrides['GET /spaces/2/categories'] = (_) => http.Response(
      '{"data":[]}',
      200,
      headers: {'content-type': 'application/json'},
    );
    api = ApiClient(baseUrl: 'http://example.test', client: backend.client);
    storage = MemorySessionStorage();
    session = SessionController(
      api: api,
      auth: AuthRepository(api),
      storage: storage,
    )..user = const AppUser(id: 1, name: 'Jeann', email: 'jeann@example.com');
  });

  Widget wrapWithProviders(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(1280, 1000),
  }) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    return MediaQuery(
      data: MediaQueryData(size: size),
      child: MultiProvider(
        providers: [
          Provider<AgreementsRepository>(
            create: (_) => AgreementsRepository(api),
          ),
          Provider<AccountsRepository>(create: (_) => AccountsRepository(api)),
          Provider<PayablesRepository>(create: (_) => PayablesRepository(api)),
          Provider<CategoriesRepository>(
            create: (_) => CategoriesRepository(api),
          ),
          Provider<PayableCreations>(
            create: (ctx) => PayableCreations(
              repository: ctx.read<PayablesRepository>(),
              storage: storage,
            ),
          ),
          Provider<ReceiptAttempts>(
            create: (ctx) => ReceiptAttempts(
              repository: ctx.read<AgreementsRepository>(),
              storage: storage,
              payables: ctx.read<PayablesRepository>(),
            ),
          ),
          Provider<OpeningAdjustments>(
            create: (ctx) => OpeningAdjustments(
              repository: ctx.read<AccountsRepository>(),
              storage: storage,
            ),
          ),
          ChangeNotifierProvider<SessionController>.value(value: session),
        ],
        child: MaterialApp(home: child),
      ),
    );
  }

  bool isFieldFocused(WidgetTester tester, Finder fieldFinder) {
    final editableText = tester.widget<EditableText>(
      find.descendant(of: fieldFinder, matching: find.byType(EditableText)),
    );
    return editableText.focusNode.hasFocus;
  }

  group('AC-UI-010: PayableFormScreen (A Pagar)', () {
    testWidgets(
      'Modo Avulso: exibe asterisco em campos obrigatórios e sufixo opcional',
      (tester) async {
        await tester.pumpWidget(
          wrapWithProviders(
            tester,
            PayableFormScreen(space: pf, today: DateTime(2026, 11, 23)),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Descrição *'), findsOneWidget);
        expect(find.text('Beneficiário (opcional)'), findsOneWidget);
        expect(find.text('Categoria (opcional)'), findsOneWidget);
        expect(find.text('Valor *'), findsOneWidget);
        expect(find.text('Vencimento *'), findsOneWidget);
      },
    );

    testWidgets(
      'Modo Parcelado: exibe asterisco em Número de parcelas e Valor',
      (tester) async {
        await tester.pumpWidget(
          wrapWithProviders(
            tester,
            PayableFormScreen(space: pf, today: DateTime(2026, 11, 23)),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Parcelada'));
        await tester.pumpAndSettle();

        expect(find.text('Descrição *'), findsOneWidget);
        expect(find.text('Número de parcelas *'), findsOneWidget);
        expect(find.text('Primeiro vencimento *'), findsOneWidget);
        expect(find.textContaining('Valor'), findsWidgets);
      },
    );

    testWidgets(
      'Modo Recorrente Fixo vs Variável: Valor mensal * vs Valor da primeira ocorrência (opcional)',
      (tester) async {
        await tester.pumpWidget(
          wrapWithProviders(
            tester,
            PayableFormScreen(space: pf, today: DateTime(2026, 11, 23)),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Recorrente'));
        await tester.pumpAndSettle();

        // Padrão Fixo
        expect(find.text('Valor mensal *'), findsOneWidget);
        expect(find.text('Primeiro vencimento *'), findsOneWidget);

        // Alterna para Variável
        await tester.tap(find.text('Valor Variável'));
        await tester.pumpAndSettle();

        expect(
          find.text('Valor da primeira ocorrência (opcional)'),
          findsOneWidget,
        );
        expect(find.text('Primeiro vencimento *'), findsOneWidget);
      },
    );

    testWidgets(
      'Validação inline e foco automático no primeiro erro visual (descrição vazia)',
      (tester) async {
        await tester.pumpWidget(
          wrapWithProviders(
            tester,
            PayableFormScreen(space: pf, today: DateTime(2026, 11, 23)),
          ),
        );
        await tester.pumpAndSettle();

        // Tenta salvar sem preencher nada
        final saveBtn = find.text('Salvar conta a pagar');
        await tester.ensureVisible(saveBtn);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        // Mensagem inline exibida
        expect(find.text('Informe a descrição.'), findsOneWidget);
        expect(find.text('Informe o valor.'), findsOneWidget);

        // Foco deve estar no primeiro campo inválido (descrição)
        final descField = find.widgetWithText(TextFormField, 'Descrição *');
        expect(isFieldFocused(tester, descField), isTrue);
      },
    );

    testWidgets(
      'Validação inline e foco automático no segundo campo quando descrição está preenchida',
      (tester) async {
        await tester.pumpWidget(
          wrapWithProviders(
            tester,
            PayableFormScreen(space: pf, today: DateTime(2026, 11, 23)),
          ),
        );
        await tester.pumpAndSettle();

        // Preenche descrição
        final descField = find.widgetWithText(TextFormField, 'Descrição *');
        await tester.enterText(descField, 'Internet Fibra');
        await tester.pumpAndSettle();

        // Tenta salvar
        final saveBtn = find.text('Salvar conta a pagar');
        await tester.ensureVisible(saveBtn);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        // Descrição não tem erro, valor tem erro
        expect(find.text('Informe a descrição.'), findsNothing);
        expect(find.text('Informe o valor.'), findsOneWidget);

        // Foco deve estar no campo de valor
        final amountField = find.widgetWithText(TextFormField, 'Valor *');
        expect(isFieldFocused(tester, amountField), isTrue);
      },
    );

    testWidgets(
      'Modo Variável: valor vazio não impede avanço quando descrição é válida',
      (tester) async {
        await tester.pumpWidget(
          wrapWithProviders(
            tester,
            PayableFormScreen(space: pf, today: DateTime(2026, 11, 23)),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Recorrente'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Valor Variável'));
        await tester.pumpAndSettle();

        final descField = find.widgetWithText(TextFormField, 'Descrição *');
        await tester.enterText(descField, 'Energia Elétrica Copel');
        await tester.pumpAndSettle();

        // Clica em 'Revisar ocorrências' sem informar valor
        final previewBtn = find.text('Revisar ocorrências');
        await tester.ensureVisible(previewBtn);
        await tester.tap(previewBtn);
        await tester.pumpAndSettle();

        // Não exibe erro de "Informe o valor."
        expect(find.text('Informe o valor.'), findsNothing);
      },
    );

    testWidgets(
      'Rolagem automática quando o primeiro campo inválido está abaixo da dobra',
      (tester) async {
        await tester.pumpWidget(
          wrapWithProviders(
            tester,
            PayableFormScreen(space: pf, today: DateTime(2026, 11, 23)),
            size: const Size(375, 400),
          ),
        );
        await tester.pumpAndSettle();

        // Preenche descrição
        final descField = find.widgetWithText(TextFormField, 'Descrição *');
        await tester.enterText(descField, 'Manutenção Elétrica');
        await tester.pumpAndSettle();

        // Rola a tela até o botão salvar (no final da lista)
        final saveBtn = find.text('Salvar conta a pagar');
        await tester.scrollUntilVisible(
          saveBtn,
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        // Ao tentar salvar com valor em branco, o formulário deve rolar de volta para o campo de valor
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        final amountField = find.widgetWithText(TextFormField, 'Valor *');
        expect(find.text('Informe o valor.'), findsOneWidget);
        expect(isFieldFocused(tester, amountField), isTrue);

        // Confirma que o campo de valor está visível no viewport (dy >= 0 e <= 400)
        final amountTop = tester.getTopLeft(amountField).dy;
        expect(amountTop, greaterThanOrEqualTo(0.0));
        expect(amountTop, lessThan(400.0));
      },
    );
  });

  group('AC-UI-010: AgreementFormScreen (A Receber)', () {
    testWidgets(
      'Exibe asteriscos em campos obrigatórios e foco no primeiro erro',
      (tester) async {
        await tester.pumpWidget(
          wrapWithProviders(tester, const AgreementFormScreen(space: pj)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Descrição *'), findsOneWidget);
        expect(find.text('Valor *'), findsOneWidget);
        expect(find.text('Vencimento *'), findsOneWidget);
        expect(find.text('Categoria (opcional)'), findsOneWidget);

        // Tenta salvar vazio
        final submitBtn = find.text('Salvar conta a receber');
        await tester.ensureVisible(submitBtn);
        await tester.tap(submitBtn);
        await tester.pumpAndSettle();

        expect(find.text('Informe a descrição.'), findsOneWidget);
        expect(find.text('Informe o valor.'), findsOneWidget);

        final descField = find.widgetWithText(TextFormField, 'Descrição *');
        expect(isFieldFocused(tester, descField), isTrue);
      },
    );

    testWidgets(
      'Modo Parcelado: asterisco em Quantidade de parcelas e Valor da parcela',
      (tester) async {
        await tester.pumpWidget(
          wrapWithProviders(
            tester,
            const AgreementFormScreen(space: pj),
            size: const Size(375, 812),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Parcelada'));
        await tester.pumpAndSettle();

        expect(find.text('Quantidade de parcelas *'), findsOneWidget);
        expect(find.text('Valor da parcela *'), findsOneWidget);
        expect(find.text('Primeiro vencimento *'), findsOneWidget);
      },
    );
  });

  group('AC-UI-010: AccountFormScreen (Contas)', () {
    testWidgets(
      'Passo 3: exibe asteriscos e valida nome obrigatório com foco',
      (tester) async {
        await tester.pumpWidget(
          wrapWithProviders(
            tester,
            const AccountFormScreen(space: pf),
            size: const Size(1280, 1000),
          ),
        );
        await tester.pumpAndSettle();

        // Passo 1: Seleciona Nubank
        await tester.tap(find.text('Nubank'));
        await tester.pumpAndSettle();

        // Passo 2: Seleciona Corrente
        await tester.tap(find.text('Conta Corrente'));
        await tester.pumpAndSettle();

        // Passo 3: Verifica labels com asterisco
        expect(find.text('Nome de exibição da conta *'), findsOneWidget);
        expect(find.text('Saldo inicial / atual *'), findsOneWidget);
        expect(find.text('Data de referência do saldo *'), findsOneWidget);

        // Limpa o nome sugerido para forçar erro
        final nameField = find.byKey(const ValueKey('account_name_field'));
        await tester.enterText(nameField, '');
        await tester.pumpAndSettle();

        // Tenta criar conta
        final saveBtn = find.text('Criar e Cadastrar Conta');
        await tester.ensureVisible(saveBtn);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        expect(find.text('Informe um nome.'), findsOneWidget);
        expect(isFieldFocused(tester, nameField), isTrue);
      },
    );
  });

  group(
    'AC-UI-010: Telas de Edição (PayableEditScreen e AccountEditScreen)',
    () {
      testWidgets('PayableEditScreen exibe asteriscos em campos obrigatórios', (
        tester,
      ) async {
        const samplePayable = Payable(
          id: 10,
          kind: 'single',
          description: 'Consultoria TI',
          amount: Money(150000),
          paid: Money(0),
          remaining: Money(150000),
          dueDate: '2026-12-10',
          status: PayableStatus.open,
          overdue: false,
        );

        await tester.pumpWidget(
          wrapWithProviders(
            tester,
            PayableEditScreen(space: pf, payable: samplePayable),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Descrição *'), findsOneWidget);
        expect(find.text('Valor *'), findsOneWidget);
        expect(find.text('Vencimento *'), findsOneWidget);
        expect(find.text('Beneficiário (opcional)'), findsOneWidget);
        expect(find.text('Motivo da alteração (opcional)'), findsOneWidget);
      });

      testWidgets('AccountEditScreen exibe asterisco no nome da conta', (
        tester,
      ) async {
        const sampleAccount = Account(
          id: 5,
          name: 'Nubank PJ',
          openingBalance: Money(100000),
          openingBalanceDate: '2026-01-01',
          balance: Money(100000),
        );

        await tester.pumpWidget(
          wrapWithProviders(
            tester,
            const AccountEditScreen(space: pj, account: sampleAccount),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Nome da conta *'), findsOneWidget);
      });
    },
  );
}
