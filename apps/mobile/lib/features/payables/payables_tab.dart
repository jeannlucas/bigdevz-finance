import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import 'cards_screen.dart';
import 'payable.dart';
import 'payable_creations.dart';
import 'payable_form_screen.dart';
import 'payable_screen.dart';
import 'payables_repository.dart';
import 'pending_creation_card.dart';

/// Obrigações a pagar do espaço, com filtro por situação. Cadastrar não
/// altera saldo: só pagamentos movimentam contas.
class PayablesTab extends StatefulWidget {
  const PayablesTab({super.key, required this.space});

  final Space space;

  @override
  State<PayablesTab> createState() => _PayablesTabState();
}

class _PayablesTabState extends State<PayablesTab> {
  static const _filters = {
    'open': 'Em aberto',
    'overdue': 'Vencidas',
    'awaiting_amount': 'Valor a informar',
    'paid': 'Pagas',
    'cancelled': 'Canceladas',
    'all': 'Todas',
  };

  String _filter = 'open';
  PendingCreation? _pending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPending());
  }

  /// Cadastro sem confirmação deste usuário e espaço; não bloqueia pagamentos.
  Future<void> _loadPending() async {
    final user = context.read<SessionController>().user;
    final pending = user == null
        ? null
        : await context.read<PayableCreations>().pending(
            user.id,
            widget.space.id,
          );
    if (mounted) setState(() => _pending = pending);
  }

  @override
  Widget build(BuildContext context) {
    final space = widget.space;
    final pending = _pending;
    return Column(
      children: [
        if (pending != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.p16,
              AppTokens.p8,
              AppTokens.p16,
              0,
            ),
            child: PendingCreationCard(
              key: ValueKey(pending.idempotencyKey),
              pending: pending,
              onSettled: (outcome) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(outcome.message)));
                setState(() => _pending = null);
                context.read<SessionController>().dataChanged();
              },
            ),
          ),
        // Cabeçalho da aba A pagar com ação principal
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.p16,
            AppTokens.p12,
            AppTokens.p16,
            0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'A pagar',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  spaceRoute(
                    isPf: space.isPf,
                    child: PayableFormScreen(space: space),
                  ),
                ),
                icon: const AppIcon(AppIcons.add, size: 18),
                label: const Text('Nova conta a pagar'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.p16,
              vertical: 6,
            ),
            children: [
              for (final MapEntry(key: value, value: label) in _filters.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _filter == value,
                    onSelected: (_) => setState(() => _filter = value),
                  ),
                ),
              ActionChip(
                avatar: const AppIcon(AppIcons.card, size: 16),
                label: const Text('Cartões e recorrências'),
                onPressed: () => Navigator.of(context).push(
                  spaceRoute(
                    isPf: space.isPf,
                    child: CardsScreen(space: space),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LoadView<List<Payable>>(
            key: ValueKey('payables-$_filter'),
            load: () => context.read<PayablesRepository>().list(
              space.id,
              status: _filter,
            ),
            isEmpty: (items) => items.isEmpty,
            empty: (context, _) => EmptyState(
              icon: AppIcons.payables,
              title: 'Nada em "${_filters[_filter]}"',
              message:
                  'Cadastre contas a pagar avulsas, parceladas ou recorrentes. '
                  'Faturas de cartão aparecem com valor a informar.',
            ),
            builder: (context, items, refresh) => RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.p16,
                  4,
                  AppTokens.p16,
                  96,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      items.length == 1
                          ? '1 conta a pagar'
                          : '${items.length} contas a pagar',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  for (final item in items) ...[
                    PayableCard(
                      space: space,
                      payable: item,
                      onTap: () => Navigator.of(context).push(
                        spaceRoute(
                          isPf: space.isPf,
                          child: PayableScreen(
                            space: space,
                            payableId: item.id,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class PayableCard extends StatelessWidget {
  const PayableCard({
    super.key,
    required this.space,
    required this.payable,
    this.onTap,
  });

  final Space space;
  final Payable payable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAwaiting =
        payable.status == PayableStatus.awaitingAmount ||
        payable.remaining == null;
    final isPaid = payable.status == PayableStatus.paid;
    final isCancelled = payable.status == PayableStatus.cancelled;
    final isPartial = payable.status == PayableStatus.partial;

    return Card(
      key: ValueKey('payable-${payable.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.r16),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.p16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Linha Superior: Descrição e StatusChip alinhados
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          payable.description,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${payable.kindLabel} · vence ${formatDateBr(payable.dueDate)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (payable.payee != null &&
                            payable.payee!.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            payable.payee!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.8),
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  payableStatusChip(payable),
                ],
              ),
              const SizedBox(height: 12),

              // Bloco de Valores com destaque fintech
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isPaid
                              ? 'Total pago'
                              : isCancelled
                              ? 'Valor cancelado'
                              : 'Restante a pagar',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: payable.overdue
                                ? AppTokens.expense
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (isAwaiting)
                          Text(
                            'Valor a informar',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppTokens.warning,
                              letterSpacing: -0.2,
                            ),
                          )
                        else
                          MoneyText(
                            isPaid
                                ? payable.paid
                                : (payable.remaining ??
                                      payable.amount ??
                                      const Money(0)),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                              color: payable.overdue ? AppTokens.expense : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isPartial && payable.amount != null) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Pago líquido',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        MoneyText(
                          payable.paid,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppTokens.income,
                          ),
                        ),
                      ],
                    ),
                  ] else if (!isPaid &&
                      !isCancelled &&
                      payable.amount != null &&
                      !isAwaiting) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Valor total',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        MoneyText(
                          payable.amount!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Situação com vencimento: parcial e vencida podem coexistir.
Widget payableStatusChip(Payable payable) => StatusChip(
  label: payable.overdue
      ? (payable.status == PayableStatus.partial
            ? 'Parcial · vencida'
            : 'Vencida')
      : payable.status.label,
  tone: switch (payable.status) {
    _ when payable.overdue => StatusTone.danger,
    PayableStatus.paid => StatusTone.success,
    PayableStatus.partial || PayableStatus.awaitingAmount => StatusTone.warning,
    _ => StatusTone.neutral,
  },
);
