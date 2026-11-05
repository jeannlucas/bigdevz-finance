import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../../ui/date_field.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import 'account.dart';
import 'account_card.dart';
import 'accounts_repository.dart';
import 'bank_catalog.dart';

/// Modalidades de conta bancária brasileira.
enum AccountType {
  corrente(
    'Conta Corrente',
    'Corrente',
    'Para movimentações e pagamentos do dia a dia',
    Icons.credit_card_outlined,
  ),
  poupanca(
    'Conta Poupança',
    'Poupança',
    'Para reservas financeiras e rendimentos',
    Icons.savings_outlined,
  ),
  salario(
    'Conta Salário',
    'Salário',
    'Para recebimento de salários e proventos',
    Icons.work_outline,
  ),
  investimento(
    'Investimento / Pagamento',
    'Investimento',
    'Carteiras digitais, corretoras e reservas',
    Icons.trending_up_outlined,
  );

  const AccountType(this.label, this.shortLabel, this.description, this.icon);
  final String label;
  final String shortLabel;
  final String description;
  final IconData icon;
}

/// Abre o fluxo guiado em 3 passos (Modal Dialog em Desktop / Bottom Sheet em Mobile).
Future<void> showAccountFormModal(
  BuildContext context, {
  required Space space,
}) {
  final isDesktop = MediaQuery.sizeOf(context).width >= 640;
  if (isDesktop) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.r24),
        ),
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
          child: AccountFormScreen(space: space, asModal: true),
        ),
      ),
    );
  } else {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTokens.r24),
        ),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.92,
          child: AccountFormScreen(space: space, asModal: true),
        ),
      ),
    );
  }
}

class AccountFormScreen extends StatefulWidget {
  const AccountFormScreen({
    super.key,
    required this.space,
    this.asModal = false,
  });

  final Space space;
  final bool asModal;

  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  final _pageController = PageController();
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _balance = TextEditingController(text: '0,00');
  final _searchController = TextEditingController();

  int _currentStep = 0;
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  bool _saving = false;
  ApiException? _error;
  BankInfo? _selectedBank;
  AccountType _selectedType = AccountType.corrente;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(
        () => _searchQuery = _searchController.text.trim().toLowerCase(),
      );
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _name.dispose();
    _balance.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
    );
  }

  void _updateSuggestedName() {
    if (_selectedBank == null) return;
    if (_selectedBank!.isOther) {
      _name.text = '';
      return;
    }
    if (_selectedBank!.isCashOrWallet) {
      _name.text =
          _selectedBank!.initialNameSuggestion ?? 'Dinheiro em Espécie';
      return;
    }
    _name.text = '${_selectedBank!.name} - ${_selectedType.shortLabel}';
    _name.selection = TextSelection.fromPosition(
      TextPosition(offset: _name.text.length),
    );
  }

  void _selectBank(BankInfo bank) {
    setState(() {
      _selectedBank = bank;
      _updateSuggestedName();
    });
    // Se for dinheiro em espécie, pula direto para o saldo (passo 2)
    if (bank.isCashOrWallet) {
      _goToStep(2);
    } else {
      _goToStep(1);
    }
  }

  void _selectType(AccountType type) {
    setState(() {
      _selectedType = type;
      _updateSuggestedName();
    });
    _goToStep(2);
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<AccountsRepository>().create(
        widget.space.id,
        name: _name.text.trim(),
        openingBalance: Money.fromInput(_balance.text)!,
        date: toApiDate(_date),
      );
      if (!mounted) return;
      context.read<SessionController>().dataChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conta cadastrada com sucesso.')),
      );
      Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fieldErrors = _error?.fieldErrors ?? const {};

    final body = Column(
      children: [
        // CABEÇALHO DO WIZARD COM PROGRESSO
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (_currentStep > 0)
                    IconButton(
                      icon: const Icon(Icons.arrow_back, size: 20),
                      tooltip: 'Voltar',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _goToStep(_currentStep - 1),
                    )
                  else
                    const SizedBox(width: 4),
                  if (_currentStep > 0) const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          switch (_currentStep) {
                            0 => 'Passo 1 de 3: Escolha o Banco',
                            1 => 'Passo 2 de 3: Modalidade da Conta',
                            _ => 'Passo 3 de 3: Saldo e Confirmação',
                          },
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          switch (_currentStep) {
                            0 => 'Selecione a sua instituição',
                            1 => 'Qual é o tipo da conta?',
                            _ => 'Defina o saldo de abertura',
                          },
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Barra de progresso linear fina
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: (_currentStep + 1) / 3,
                  minHeight: 3,
                  backgroundColor: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                  valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
                ),
              ),
            ],
          ),
        ),

        // CORPO DO WIZARD (PAGEVIEW)
        Expanded(
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              // PASSO 1: SELEÇÃO DA INSTITUIÇÃO
              _buildStep1Institutions(theme),

              // PASSO 2: MODALIDADE DA CONTA
              _buildStep2AccountType(theme),

              // PASSO 3: SALDO E CONFIRMAÇÃO
              _buildStep3BalanceAndConfirm(theme, fieldErrors),
            ],
          ),
        ),
      ],
    );

    if (widget.asModal) {
      return Material(color: theme.colorScheme.surface, child: body);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Nova conta bancária')),
      body: body,
    );
  }

  // PASSO 1: GRID CENTRALIZADO DE BANCOS COM BUSCA RÁPIDA
  Widget _buildStep1Institutions(ThemeData theme) {
    final filteredBanks = BankCatalog.all.where((bank) {
      if (_searchQuery.isEmpty) return true;
      return bank.name.toLowerCase().contains(_searchQuery) ||
          bank.code.contains(_searchQuery);
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          // Campo de busca
          TextFormField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar banco ou fintech...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTokens.r12),
                borderSide: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.6,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Grid com alinhamento e centralização perfeita
          Expanded(
            child: filteredBanks.isEmpty
                ? Center(
                    child: Text(
                      'Nenhum banco encontrado para "$_searchQuery".',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.15,
                        ),
                    itemCount: filteredBanks.length,
                    itemBuilder: (context, index) {
                      final bank = filteredBanks[index];
                      final isSelected = _selectedBank?.id == bank.id;

                      return Material(
                        color: isSelected
                            ? theme.colorScheme.primaryContainer.withValues(
                                alpha: 0.4,
                              )
                            : theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(AppTokens.r16),
                        child: InkWell(
                          onTap: () => _selectBank(bank),
                          borderRadius: BorderRadius.circular(AppTokens.r16),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                AppTokens.r16,
                              ),
                              border: Border.all(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outlineVariant
                                          .withValues(alpha: 0.45),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(
                                      AppTokens.r12,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.1,
                                        ),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Image.asset(
                                    bank.assetPath,
                                    width: 32,
                                    height: 32,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  bank.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // PASSO 2: CARDS LARGOS E DESCRITIVOS DE MODALIDADE
  Widget _buildStep2AccountType(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner com banco selecionado
          if (_selectedBank != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(AppTokens.r12),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Image.asset(
                      _selectedBank!.assetPath,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${_selectedBank!.name} selecionado',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _goToStep(0),
                    child: const Text('Trocar'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),

          Text(
            'Selecione a modalidade da conta:',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),

          Expanded(
            child: ListView(
              children: AccountType.values.map((type) {
                final isSelected = _selectedType == type;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: isSelected
                        ? theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.35,
                          )
                        : theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppTokens.r16),
                    child: InkWell(
                      onTap: () => _selectType(type),
                      borderRadius: BorderRadius.circular(AppTokens.r16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppTokens.r16),
                          border: Border.all(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outlineVariant.withValues(
                                    alpha: 0.45,
                                  ),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(
                                  AppTokens.r12,
                                ),
                              ),
                              child: Icon(
                                type.icon,
                                color: isSelected
                                    ? Colors.white
                                    : theme.colorScheme.onSurfaceVariant,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    type.label,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: isSelected
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    type.description,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios, size: 14),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // PASSO 3: LIVE PREVIEW + SALDO + CONFIRMAÇÃO
  Widget _buildStep3BalanceAndConfirm(
    ThemeData theme,
    Map<String, String> fieldErrors,
  ) {
    final previewAccount = Account(
      id: 0,
      name: _name.text.isEmpty
          ? '${_selectedBank?.name ?? 'Conta'} - ${_selectedType.shortLabel}'
          : _name.text,
      openingBalance: Money.fromInput(_balance.text) ?? const Money(0),
      openingBalanceDate: toApiDate(_date),
      balance: Money.fromInput(_balance.text) ?? const Money(0),
    );

    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        children: [
          if (_error != null && fieldErrors.isEmpty) ...[
            FormErrorBanner(_error!.message),
            const SizedBox(height: 12),
          ],

          // Preview em tempo real do cartão bancário
          Text(
            'Pré-visualização do Cartão',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          AccountCard(space: widget.space, account: previewAccount),
          const SizedBox(height: 20),

          // Nome da conta personalizável
          TextFormField(
            key: const ValueKey('account_name_field'),
            controller: _name,
            decoration: InputDecoration(
              labelText: 'Nome de exibição da conta',
              hintText: 'Ex.: Banco do Brasil - Corrente',
              errorText: fieldErrors['name'],
              prefixIcon: _selectedBank != null
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: Image.asset(
                        _selectedBank!.assetPath,
                        width: 22,
                        height: 22,
                        fit: BoxFit.contain,
                      ),
                    )
                  : const AppIcon(AppIcons.accounts, size: 20),
            ),
            textCapitalization: TextCapitalization.sentences,
            maxLength: 80,
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Informe um nome.' : null,
          ),
          const SizedBox(height: 12),

          // Saldo Inicial
          TextFormField(
            controller: _balance,
            decoration: InputDecoration(
              labelText: 'Saldo inicial / atual',
              prefixText: r'R$ ',
              errorText: fieldErrors['opening_balance'],
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [MoneyInputFormatter()],
            validator: (value) => Money.fromInput(value ?? '') == null
                ? 'Informe o saldo inicial.'
                : null,
          ),
          const SizedBox(height: 16),

          // Data de abertura
          DateField(
            label: 'Data de referência do saldo',
            value: _date,
            lastDate: DateTime(2100),
            errorText: fieldErrors['opening_balance_date'],
            onChanged: (date) => setState(() => _date = date),
          ),
          const SizedBox(height: 8),
          Text(
            'Movimentações anteriores a esta data não são permitidas nesta conta.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Botão Concluir
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const AppIcon(AppIcons.check, size: 18),
            label: Text(_saving ? 'Cadastrando...' : 'Criar e Cadastrar Conta'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.r12),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
