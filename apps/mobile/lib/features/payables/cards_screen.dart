import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import 'payable.dart';
import 'payables_repository.dart';

/// Cartões (nome e dia de vencimento; faturas pelo total) e recorrências do
/// espaço. Cartão não é conta: não tem saldo nem dados do cartão.
class CardsScreen extends StatelessWidget {
  const CardsScreen({super.key, required this.space});

  final Space space;

  Future<(List<PayableCard>, List<Recurrence>)> _load(
    BuildContext context,
  ) async {
    final repository = context.read<PayablesRepository>();
    final results = await Future.wait([
      repository.cards(space.id),
      repository.recurrences(space.id),
    ]);
    return (results[0] as List<PayableCard>, results[1] as List<Recurrence>);
  }

  Future<void> _addCard(BuildContext context) async {
    final name = TextEditingController();
    final day = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Novo cartão'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nome do cartão'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: day,
              decoration: const InputDecoration(
                labelText: 'Dia de vencimento (1 a 31)',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            Text(
              'Não informe número, CVV ou senha. As faturas são lançadas pelo total.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final dueDay = int.tryParse(day.text) ?? 0;
              if (name.text.trim().isNotEmpty && dueDay >= 1 && dueDay <= 31) {
                Navigator.of(dialog).pop(true);
              }
            },
            child: const Text('Salvar cartão'),
          ),
        ],
      ),
    );
    if (created != true || !context.mounted) return;
    try {
      await context.read<PayablesRepository>().createCard(
        space.id,
        name.text.trim(),
        int.parse(day.text),
      );
      if (!context.mounted) return;
      context.read<SessionController>().dataChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cartão cadastrado: faturas geradas com valor a informar.',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _toggle(BuildContext context, PayableCard card) async {
    await context.read<PayablesRepository>().setCardArchived(
      space.id,
      card.id,
      !card.archived,
    );
    if (!context.mounted) return;
    context.read<SessionController>().dataChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          card.archived ? 'Cartão reativado.' : 'Cartão arquivado: não gera novas faturas; as existentes continuam pagáveis.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cartões e recorrências')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addCard(context),
        icon: const AppIcon(AppIcons.add, size: 20),
        label: const Text('Novo cartão'),
      ),
      body: LoadView<(List<PayableCard>, List<Recurrence>)>(
        load: () => _load(context),
        builder: (context, data, refresh) {
          final (cards, recurrences) = data;
          final theme = Theme.of(context);
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.p16,
              AppTokens.p16,
              AppTokens.p16,
              96,
            ),
            children: [
              SpaceBadge(space),
              const SizedBox(height: 16),
              Row(
                children: [
                  const AppIcon(AppIcons.card, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Cartões',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (cards.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Nenhum cartão.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final card in cards)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: card.archived
                          ? theme.colorScheme.surfaceContainerHighest
                          : theme.colorScheme.primaryContainer,
                      child: AppIcon(
                        card.archived ? AppIcons.archive : AppIcons.card,
                        size: 18,
                        color: card.archived
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(
                      card.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Vence dia ${card.dueDay}${card.archived ? ' · arquivado' : ''}',
                    ),
                    trailing: TextButton(
                      onPressed: () => _toggle(context, card),
                      child: Text(card.archived ? 'Reativar' : 'Arquivar'),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const AppIcon(AppIcons.recurrence, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Recorrências',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Geradas automaticamente até 12 meses à frente. Para alterar as futuras '
                'ou encerrar, abra uma ocorrência em A pagar.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (recurrences.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Nenhuma recorrência.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final recurrence in recurrences)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      child: const AppIcon(AppIcons.recurrence, size: 18),
                    ),
                    title: Text(
                      recurrence.description,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Desde ${formatDateBr(recurrence.startDate)}'
                      '${recurrence.endDate == null ? '' : ' · até ${formatDateBr(recurrence.endDate!)}'}',
                    ),
                    trailing: MoneyText(
                      recurrence.amount,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
