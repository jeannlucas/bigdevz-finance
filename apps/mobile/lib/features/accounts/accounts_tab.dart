import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import '../settings/preferences_controller.dart';
import '../transfers/transfer_form_screen.dart';
import 'account.dart';
import 'account_form_screen.dart';
import 'account_screen.dart';
import 'accounts_repository.dart';
import 'bank_catalog.dart';

/// Carteira de contas do espaço com layout executivo financeiro (Opção 2).
/// Topo: Hero KPI com Saldo Total Consolidado, contagem de contas e ações rápidas (Transferir / Nova conta).
/// Abaixo: Tabela/Lista Inteligente com as logos oficiais dos bancos, tipos de conta e saldos.
class AccountsTab extends StatelessWidget {
  const AccountsTab({super.key, required this.space});

  final Space space;

  @override
  Widget build(BuildContext context) {
    return LoadView<List<Account>>(
      load: () => context.read<AccountsRepository>().list(space.id),
      isEmpty: (accounts) => accounts.isEmpty,
      empty: (context, _) => EmptyState(
        icon: AppIcons.accounts,
        title: 'Nenhuma conta neste espaço',
        message: 'Cadastre uma conta com o saldo inicial e a data de referência. Recebimentos e pagamentos posteriores atualizam o saldo.',
        action: FilledButton.icon(
          key: const ValueKey('accounts_empty_create_button'),
          onPressed: () => showAccountFormModal(context, space: space),
          icon: const AppIcon(AppIcons.add, size: 18),
          label: const Text('Cadastrar primeira conta'),
        ),
      ),
      builder: (context, accounts, refresh) {
        final theme = Theme.of(context);
        final obscure =
            context.watch<PreferencesController?>()?.obscureValues ?? false;
        final active = accounts.where((a) => !a.isArchived).toList();
        final archived = accounts.where((a) => a.isArchived).toList();
        final total = Money(accounts.fold(0, (t, a) => t + a.balance.cents));

        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, AppTokens.p16, 0, 96),
            children: [
              // PAINEL EXECUTIVO HERO KPI: SALDO TOTAL CONSOLIDADO E AÇÕES
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.p16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.p16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cabeçalho do Card: Ícone, Título e Ações
                        SizedBox(
                          width: double.infinity,
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: AppTokens.p12,
                            runSpacing: AppTokens.p8,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                children: [
                                  AppIcon(
                                    AppIcons.accounts,
                                    size: 20,
                                    color: theme.colorScheme.primary,
                                  ),
                                  Text(
                                    'Carteira de Contas',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.2,
                                        ),
                                  ),
                                ],
                              ),
                              Wrap(
                                spacing: AppTokens.p8,
                                runSpacing: AppTokens.p8,
                                children: [
                                  if (active.length >= 2)
                                    FilledButton.tonalIcon(
                                      key: const ValueKey(
                                        'accounts_tab_transfer_button',
                                      ),
                                      onPressed: () =>
                                          Navigator.of(context).push(
                                            spaceRoute(
                                              isPf: space.isPf,
                                              child: TransferFormScreen(
                                                space: space,
                                                accounts: accounts,
                                              ),
                                            ),
                                          ),
                                      icon: const AppIcon(
                                        AppIcons.transfer,
                                        size: 16,
                                      ),
                                      label: const Text('Transferir'),
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size(0, 36),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  FilledButton.icon(
                                    key: const ValueKey(
                                      'accounts_tab_new_account_button',
                                    ),
                                    onPressed: () => showAccountFormModal(
                                      context,
                                      space: space,
                                    ),
                                    icon: const AppIcon(AppIcons.add, size: 16),
                                    label: const Text('Nova conta'),
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(0, 36),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          obscure
                              ? r'Saldo total: R$ ••••••••'
                              : 'Saldo total: ${total.brl}',
                          key: const ValueKey('accounts-total'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          archived.isEmpty
                              ? '${active.length} ${active.length == 1 ? 'conta ativa' : 'contas ativas'}'
                              : '${active.length} ativa${active.length == 1 ? '' : 's'} · '
                                    '${archived.length} arquivada${archived.length == 1 ? '' : 's'} '
                                    '(o total inclui as arquivadas)',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // LISTA ANALÍTICA COMPLETA DE CONTAS
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.p16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppTokens.p8,
                      runSpacing: AppTokens.p4,
                      children: [
                        Text(
                          'Todas as contas',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurfaceVariant,
                            letterSpacing: 0.3,
                          ),
                        ),
                        Text(
                          '${active.length} ${active.length == 1 ? 'conta' : 'contas'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final account in active) ...[
                      _AccountTile(
                        space: space,
                        account: account,
                        obscure: obscure,
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (archived.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          const AppIcon(
                            AppIcons.archive,
                            size: 18,
                            color: AppTokens.neutral,
                          ),
                          Text(
                            'Arquivadas',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      for (final account in archived) ...[
                        _AccountTile(
                          space: space,
                          account: account,
                          obscure: obscure,
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.space,
    required this.account,
    this.obscure = false,
  });

  final Space space;
  final Account account;
  final bool obscure;

  Widget _buildLeading(ThemeData theme) {
    final bank = BankCatalog.findByAccountName(account.name);
    if (bank != null) {
      return Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTokens.r12),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 4,
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
      );
    }

    return CircleAvatar(
      radius: 22,
      backgroundColor: account.isArchived
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.primaryContainer,
      child: AppIcon(
        account.isArchived ? AppIcons.archive : AppIcons.accounts,
        color: account.isArchived
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.onPrimaryContainer,
        size: 20,
      ),
    );
  }

  String _formatSubtitle() {
    if (account.isArchived) return 'Conta arquivada';
    final lower = account.name.toLowerCase();
    String? modalidade;
    if (lower.contains('poupança') || lower.contains('poupanca')) {
      modalidade = 'Poupança';
    } else if (lower.contains('salário') || lower.contains('salario')) {
      modalidade = 'Salário';
    } else if (lower.contains('investimento') || lower.contains('pagamento')) {
      modalidade = 'Investimento';
    } else if (lower.contains('corrente')) {
      modalidade = 'Corrente';
    }
    return modalidade != null
        ? '$modalidade · Saldo disponível'
        : 'Saldo disponível';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isScaled = MediaQuery.textScalerOf(context).scale(1.0) >= 1.5;

    return Card(
      key: ValueKey('account-${account.id}'),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          spaceRoute(
            isPf: space.isPf,
            child: AccountScreen(space: space, accountId: account.id),
          ),
        ),
        borderRadius: BorderRadius.circular(AppTokens.r12),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.p16),
          child: isScaled
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildLeading(theme),
                        const SizedBox(width: AppTokens.p12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                account.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _formatSubtitle(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.p8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: MoneyText(
                        account.balance,
                        obscure: obscure,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    _buildLeading(theme),
                    const SizedBox(width: AppTokens.p12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            account.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            _formatSubtitle(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppTokens.p8),
                    MoneyText(
                      account.balance,
                      obscure: obscure,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
