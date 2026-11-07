import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../auth/session_controller.dart';
import '../summary/summary.dart';

/// Abre o painel executivo de notificações e vencimentos.
Future<void> showNotificationsModal(
  BuildContext context, {
  SpaceSummary? summary,
  required void Function(int tab, {String? filter}) onNavigate,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _NotificationsDialog(initialSummary: summary, onNavigate: onNavigate),
  );
}

class _NotificationsDialog extends StatefulWidget {
  const _NotificationsDialog({
    required this.initialSummary,
    required this.onNavigate,
  });

  final SpaceSummary? initialSummary;
  final void Function(int tab, {String? filter}) onNavigate;

  @override
  State<_NotificationsDialog> createState() => _NotificationsDialogState();
}

class _NotificationsDialogState extends State<_NotificationsDialog> {
  late SpaceSummary? _summary = widget.initialSummary;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_summary == null) {
      _load();
    }
  }

  Future<void> _load() async {
    final session = context.read<SessionController>();
    final space = session.activeSpace;
    if (space == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = context.read<SummaryRepository>();
      final summary = await repo.load(space.id);
      if (mounted) {
        setState(() {
          _summary = summary;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Não foi possível carregar as notificações.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = _summary;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.r16),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.p24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cabeçalho do Modal
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppTokens.p8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppTokens.r8),
                    ),
                    child: AppIcon(
                      AppIcons.notification,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppTokens.p12),
                  Expanded(
                    child: Text(
                      'Notificações e Vencimentos',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Fechar',
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.p16),
              const Divider(height: 1),
              const SizedBox(height: AppTokens.p16),

              // Conteúdo Dinâmico
              Flexible(child: _buildBody(context, theme, summary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    SpaceSummary? summary,
  ) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(AppTokens.p32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(AppTokens.p16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: AppTokens.p12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(140, 44)),
              onPressed: _load,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    if (summary == null) {
      return const SizedBox.shrink();
    }

    final hasPayablesOverdue = summary.payables.overdueCount > 0;
    final hasAgreementsOverdue = summary.overdueInstallments > 0;
    final hasAwaitingAmount = summary.payables.awaitingAmountCount > 0;
    final hasNext30Days = summary.payables.dueNext30DaysTotal.cents > 0;

    final hasAnyNotification =
        hasPayablesOverdue ||
        hasAgreementsOverdue ||
        hasAwaitingAmount ||
        hasNext30Days;

    if (!hasAnyNotification) {
      return _buildCleanState(theme);
    }

    return ListView(
      shrinkWrap: true,
      children: [
        if (hasPayablesOverdue) ...[
          _NotificationCard(
            icon: AppIcons.alert,
            iconColor: AppTokens.expense,
            title: 'Contas a pagar vencidas',
            description:
                '${summary.payables.overdueCount} conta(s) em atraso somando ${summary.payables.overdueTotal.brl}',
            actionLabel: 'Ver contas a pagar',
            isCritical: true,
            onAction: () {
              Navigator.of(context).pop();
              widget.onNavigate(3, filter: 'overdue');
            },
          ),
          const SizedBox(height: AppTokens.p12),
        ],
        if (hasAgreementsOverdue) ...[
          _NotificationCard(
            icon: AppIcons.alert,
            iconColor: AppTokens.expense,
            title: 'Contas a receber vencidas',
            description:
                '${summary.overdueInstallments} parcela(s) em atraso aguardando recebimento',
            actionLabel: 'Ver a receber',
            isCritical: true,
            onAction: () {
              Navigator.of(context).pop();
              widget.onNavigate(2, filter: 'overdue');
            },
          ),
          const SizedBox(height: AppTokens.p12),
        ],
        if (hasAwaitingAmount) ...[
          _NotificationCard(
            icon: AppIcons.clock,
            iconColor: Colors.amber.shade700,
            title: 'Faturas pendentes',
            description:
                '${summary.payables.awaitingAmountCount} conta(s) de cartão/recorrência aguardando valor',
            actionLabel: 'Ver faturas',
            isCritical: false,
            onAction: () {
              Navigator.of(context).pop();
              widget.onNavigate(3, filter: 'awaiting_amount');
            },
          ),
          const SizedBox(height: AppTokens.p12),
        ],
        if (hasNext30Days) ...[
          _NotificationCard(
            icon: AppIcons.calendar,
            iconColor: theme.colorScheme.primary,
            title: 'Próximos vencimentos a pagar',
            description:
                'Total de ${summary.payables.dueNext30DaysTotal.brl} a vencer nos próximos 30 dias',
            actionLabel: 'Ver agenda',
            isCritical: false,
            onAction: () {
              Navigator.of(context).pop();
              widget.onNavigate(3, filter: 'next_30_days');
            },
          ),
        ],
      ],
    );
  }

  Widget _buildCleanState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.p16,
        vertical: AppTokens.p24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppTokens.p16),
            decoration: BoxDecoration(
              color: AppTokens.income.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const AppIcon(
              AppIcons.check,
              size: 32,
              color: AppTokens.income,
            ),
          ),
          const SizedBox(height: AppTokens.p16),
          Text(
            'Tudo em dia!',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppTokens.p8),
          Text(
            'Nenhum vencimento atrasado ou pendência crítica no momento.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.isCritical,
    required this.onAction,
  });

  final List<List<dynamic>> icon;
  final Color iconColor;
  final String title;
  final String description;
  final String actionLabel;
  final bool isCritical;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppTokens.p16),
      decoration: BoxDecoration(
        color: isCritical
            ? iconColor.withValues(alpha: 0.06)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppTokens.r12),
        border: Border.all(
          color: isCritical
              ? iconColor.withValues(alpha: 0.3)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: AppIcon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: AppTokens.p12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppTokens.p4),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppTokens.p8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: onAction,
                    borderRadius: BorderRadius.circular(AppTokens.r8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppTokens.p4,
                        horizontal: AppTokens.p4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            actionLabel,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: AppTokens.p4),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 11,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
