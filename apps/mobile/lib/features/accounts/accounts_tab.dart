import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import 'account.dart';
import 'account_card.dart';
import 'account_form_screen.dart';
import 'account_screen.dart';
import 'accounts_repository.dart';

/// Carteira de contas do espaço com visual fintech.
/// Topo: PageView com os cartões em destaque (gradiente, marca-d'água do gorila oficial).
/// Abaixo: Totalizador consolidado e lista completa de todas as contas ativas e arquivadas.
class AccountsTab extends StatefulWidget {
  const AccountsTab({super.key, required this.space});

  final Space space;

  @override
  State<AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends State<AccountsTab> {
  int _activeCardIndex = 0;
  late final PageController _pageController = PageController(
    viewportFraction: 0.92,
  );

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final space = widget.space;
    return LoadView<List<Account>>(
      load: () => context.read<AccountsRepository>().list(space.id),
      isEmpty: (accounts) => accounts.isEmpty,
      empty: (context, _) => const EmptyState(
        icon: AppIcons.accounts,
        title: 'Nenhuma conta neste espaço',
        message: 'Cadastre uma conta com o saldo inicial e a data de referência. Recebimentos posteriores atualizam o saldo.',
      ),
      builder: (context, accounts, refresh) {
        final theme = Theme.of(context);
        final active = accounts.where((a) => !a.isArchived).toList();
        final archived = accounts.where((a) => a.isArchived).toList();
        final total = Money(accounts.fold(0, (t, a) => t + a.balance.cents));

        // Lista para os cartões de topo (prioriza ativas, inclui arquivadas se não houver ativas)
        final cardList = active.isNotEmpty ? active : accounts;

        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, AppTokens.p16, 0, 96),
            children: [
              // CARTEIRA EM DESTAQUE (PAGEVIEW)
              if (cardList.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.p16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          children: [
                            Text(
                              'Carteira de Contas',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                            if (cardList.length > 1)
                              Text(
                                '${_activeCardIndex + 1} de ${cardList.length}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: () => Navigator.of(context).push(
                          spaceRoute(
                            isPf: space.isPf,
                            child: AccountFormScreen(space: space),
                          ),
                        ),
                        icon: const AppIcon(AppIcons.add, size: 16),
                        label: const Text('Nova conta'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
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
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 200,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: cardList.length,
                    onPageChanged: (index) {
                      setState(() => _activeCardIndex = index);
                    },
                    itemBuilder: (context, index) {
                      final item = cardList[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: AccountCard(
                          space: space,
                          account: item,
                          isHighlighted: index == _activeCardIndex,
                          onTap: () => Navigator.of(context).push(
                            spaceRoute(
                              isPf: space.isPf,
                              child: AccountScreen(
                                space: space,
                                accountId: item.id,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Área reservada abaixo do cartão (32 pixels lógicos), padronizada
                // entre PF (com indicadores) e PJ (sem indicadores falsos), garantindo
                // alinhamento vertical idêntico do bloco "Saldo total".
                SizedBox(
                  height: 32,
                  child: cardList.length > 1
                      ? Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              cardList.length > 8 ? 8 : cardList.length,
                              (i) => AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                width:
                                    (cardList.length > 8
                                        ? (i ==
                                              (_activeCardIndex *
                                                  8 ~/
                                                  cardList.length))
                                        : (i == _activeCardIndex))
                                    ? 18
                                    : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color:
                                      (cardList.length > 8
                                          ? (i ==
                                                (_activeCardIndex *
                                                    8 ~/
                                                    cardList.length))
                                          : (i == _activeCardIndex))
                                      ? theme.colorScheme.primary
                                      : theme
                                            .colorScheme
                                            .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
              ],

              // TOTALIZADOR CONSOLIDADO
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.p16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.p16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Saldo total: ${total.brl}',
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

              // LISTA COMPLETA DE CONTAS ATIVAS
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.p16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Todas as contas',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final account in active) ...[
                      _AccountTile(space: space, account: account),
                      const SizedBox(height: 8),
                    ],
                    if (archived.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const AppIcon(
                            AppIcons.archive,
                            size: 18,
                            color: AppTokens.neutral,
                          ),
                          const SizedBox(width: 8),
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
                        _AccountTile(space: space, account: account),
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
  const _AccountTile({required this.space, required this.account});

  final Space space;
  final Account account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: ValueKey('account-${account.id}'),
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          spaceRoute(
            isPf: space.isPf,
            child: AccountScreen(space: space, accountId: account.id),
          ),
        ),
        leading: CircleAvatar(
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
        ),
        title: Text(
          account.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          account.isArchived ? 'Conta arquivada' : 'Saldo disponível',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: MoneyText(
          account.balance,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
