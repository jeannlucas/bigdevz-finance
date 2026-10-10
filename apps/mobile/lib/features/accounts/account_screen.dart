import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import 'account.dart';
import 'account_card.dart';
import 'account_edit_screen.dart';
import 'accounts_repository.dart';
import 'opening_adjustment_screen.dart';
import 'opening_adjustments.dart';

/// Detalhe da conta: cartão institucional, dados de abertura, ações de gestão
/// (editar nome, corrigir abertura, arquivar ou reativar) e histórico auditado.
class AccountScreen extends StatelessWidget {
  const AccountScreen({
    super.key,
    required this.space,
    required this.accountId,
  });

  final Space space;
  final int accountId;

  Future<(Account, OpeningAttempt?)> _load(BuildContext context) async {
    final userId = context.read<SessionController>().user?.id;
    final results = await Future.wait([
      context.read<AccountsRepository>().find(space.id, accountId),
      if (userId != null)
        context.read<OpeningAdjustments>().pending(userId, space.id, accountId)
      else
        Future.value(),
    ]);
    return (results[0] as Account, results[1] as OpeningAttempt?);
  }

  void _notify(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _push(BuildContext context, Widget child, String? done) async {
    final result = await Navigator.of(context)
        .push<Object>(spaceRoute(isPf: space.isPf, child: child));
    if (!context.mounted || result == null) return;
    _notify(
      context,
      result is OpeningOutcome ? result.message : (done ?? 'Conta atualizada.'),
    );
  }

  Future<void> _toggleArchive(BuildContext context, Account account) async {
    final archive = !account.isArchived;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(archive ? 'Arquivar conta?' : 'Reativar conta?'),
        content: Text(
          archive
              ? '${account.name} deixa de aparecer como destino de novos '
                    'recebimentos e correções. O saldo (${account.balance.brl}) '
                    'e o histórico continuam, e o saldo segue no total do espaço.'
              : '${account.name} volta a aparecer como destino de recebimentos '
                    'e correções.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(archive ? 'Arquivar' : 'Reativar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<AccountsRepository>().setArchived(
        space.id,
        account.id,
        archived: archive,
      );
      if (!context.mounted) return;
      context.read<SessionController>().dataChanged();
      _notify(context, archive ? 'Conta arquivada.' : 'Conta reativada.');
    } on ApiException catch (error) {
      if (context.mounted) _notify(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LoadView<(Account, OpeningAttempt?)>(
      load: () => _load(context),
      builder: (context, data, refresh) {
        final (account, pending) = data;
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(title: Text(account.name)),
          body: RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              padding: const EdgeInsets.all(AppTokens.p16),
              children: [
                SpaceBadge(space),
                const SizedBox(height: 16),

                // CARTÃO PRINCIPAL DA CONTA COM O DESIGN FINTECH
                AccountCard(
                  space: space,
                  account: account,
                  isHighlighted: true,
                ),

                const SizedBox(height: 16),

                // DETALHES DE ABERTURA
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.p16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dados de abertura',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const AppIcon(AppIcons.calendar, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Saldo inicial ${account.openingBalance.brl} em '
                                '${formatDateBr(account.openingBalanceDate)}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (account.isArchived) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTokens.warning.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(AppTokens.r8),
                              border: Border.all(
                                color: AppTokens.warning.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const AppIcon(
                                  AppIcons.alert,
                                  size: 18,
                                  color: AppTokens.warning,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Arquivada: o saldo continua no total do espaço, '
                                    'mas a conta não recebe operações novas.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppTokens.warning,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // AVISO DE CORREÇÃO PENDENTE SE HOUVER
                if (pending != null) ...[
                  FormErrorBanner(
                    'Há uma correção da abertura sem confirmação '
                    '(${pending.previousBalance.brl} → '
                    '${pending.openingBalance.brl}). Verifique antes de '
                    'fazer outra.',
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    icon: const AppIcon(AppIcons.pending, size: 18),
                    onPressed: () => _push(
                      context,
                      OpeningAdjustmentScreen(
                        space: space,
                        account: account,
                        pending: pending,
                      ),
                      null,
                    ),
                    label: const Text('Verificar correção da abertura'),
                  ),
                  const SizedBox(height: 10),
                ],

                // BOTÕES DE AÇÃO COM TAMANHO DE TOQUE CONFORTÁVEL
                OutlinedButton.icon(
                  icon: const AppIcon(AppIcons.edit, size: 18),
                  label: const Text('Editar conta'),
                  onPressed: () => _push(
                    context,
                    AccountEditScreen(space: space, account: account),
                    'Conta atualizada.',
                  ),
                ),
                const SizedBox(height: 8),
                if (pending == null)
                  OutlinedButton.icon(
                    icon: const AppIcon(AppIcons.correction, size: 18),
                    label: const Text('Corrigir abertura'),
                    onPressed: () => _push(
                      context,
                      OpeningAdjustmentScreen(space: space, account: account),
                      null,
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: AppIcon(
                    account.isArchived ? AppIcons.unarchive : AppIcons.archive,
                    size: 18,
                  ),
                  label: Text(
                    account.isArchived ? 'Reativar conta' : 'Arquivar conta',
                  ),
                  onPressed: () => _toggleArchive(context, account),
                ),

                const SizedBox(height: 24),

                // HISTÓRICO DE CORREÇÕES DA ABERTURA
                Row(
                  children: [
                    const AppIcon(AppIcons.clock, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Histórico de correções da abertura',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (account.openingAdjustments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Nenhuma correção registrada: o saldo inicial nunca foi alterado.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  for (final item in account.openingAdjustments) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppTokens.p14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.previousBalance.brl} → ${item.newBalance.brl}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (item.adjustedAt != null) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    formatDateBr(item.adjustedAt!),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Motivo: ${item.reason}',
                              style: theme.textTheme.bodySmall,
                            ),
                            if (item.previousDate != item.newDate)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'Data: ${formatDateBr(item.previousDate)} → '
                                  '${formatDateBr(item.newDate)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
          ),
        );
      },
    );
  }
}
