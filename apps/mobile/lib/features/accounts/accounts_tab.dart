import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import 'account.dart';
import 'accounts_repository.dart';

class AccountsTab extends StatelessWidget {
  const AccountsTab({super.key, required this.space});

  final Space space;

  @override
  Widget build(BuildContext context) {
    return LoadView<List<Account>>(
      load: () => context.read<AccountsRepository>().list(space.id),
      isEmpty: (accounts) => accounts.isEmpty,
      empty: (context, _) => const EmptyState(
        icon: Icons.account_balance_outlined,
        title: 'Nenhuma conta neste espaço',
        message: 'Cadastre uma conta com o saldo inicial e a data de referência. Recebimentos posteriores atualizam o saldo.',
      ),
      builder: (context, accounts, refresh) => RefreshIndicator(
        onRefresh: refresh,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: accounts.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final account = accounts[index];
            final theme = Theme.of(context);
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    Icons.account_balance,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                title: Text(account.name),
                subtitle: Text(
                  'Saldo inicial ${account.openingBalance.brl} em ${formatDateBr(account.openingBalanceDate)}',
                ),
                trailing: MoneyText(
                  account.balance,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
