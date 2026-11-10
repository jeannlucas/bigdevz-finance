import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import 'agreement.dart';
import 'agreement_modal.dart';
import 'agreements_repository.dart';
import 'agreements_tab.dart';
import 'installment_screen.dart';

class AgreementScreen extends StatelessWidget {
  const AgreementScreen({
    super.key,
    required this.space,
    required this.agreementId,
  });

  final Space space;
  final int agreementId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conta a receber')),
      body: LoadView<Agreement>(
        load: () =>
            context.read<AgreementsRepository>().find(space.id, agreementId),
        builder: (context, agreement, refresh) => RefreshIndicator(
          onRefresh: refresh,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SpaceBadge(space),
                  const SizedBox(height: 16),
                  AgreementCard(agreement: agreement),
                  if (agreement.isCancelled) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer
                            .withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.error
                              .withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cancel_outlined,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Conta a receber cancelada'
                              '${agreement.cancelReason != null ? ': ${agreement.cancelReason}' : ''}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (!agreement.isCancelled && agreement.received.isZero) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Editar conta'),
                            onPressed: () => _edit(context, agreement, refresh),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: Icon(
                              Icons.cancel_outlined,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            label: Text(
                              'Cancelar conta',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            onPressed: () => _cancel(context, agreement),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'Parcelas do recebimento',
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  for (final installment in agreement.installments)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InstallmentTile(
                        installment: installment,
                        count: agreement.installmentCount,
                        onTap: () => Navigator.of(context).push(
                          spaceRoute(
                            isPf: space.isPf,
                            child: InstallmentScreen(
                              space: space,
                              installmentId: installment.id,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cancel(BuildContext context, Agreement agreement) async {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: Colors.redAccent),
            SizedBox(width: 8),
            Expanded(child: Text('Cancelar conta a receber')),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tem certeza que deseja cancelar esta conta a receber? '
                'Esta ação anula o compromisso e não altera saldos bancários.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: reasonController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Motivo do cancelamento *',
                  hintText: 'Ex.: Lançado por engano, desistência do cliente',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Informe o motivo do cancelamento.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogCtx).pop(true);
              }
            },
            child: const Text('Confirmar cancelamento'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      await context.read<AgreementsRepository>().cancel(
        space.id,
        agreement.id,
        reasonController.text.trim(),
      );
      if (!context.mounted) return;
      context.read<SessionController>().dataChanged();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conta a receber cancelada com sucesso.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao cancelar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _edit(
    BuildContext context,
    Agreement agreement,
    Future<void> Function() refresh,
  ) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) =>
          EditAgreementDialog(space: space, agreement: agreement),
    );

    if (updated == true && context.mounted) {
      context.read<SessionController>().dataChanged();
      await refresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Conta a receber atualizada e parcelas recalculadas com sucesso.',
            ),
          ),
        );
      }
    }
  }
}

class InstallmentTile extends StatelessWidget {
  const InstallmentTile({
    super.key,
    required this.installment,
    required this.count,
    this.onTap,
  });

  final Installment installment;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text('Parcela ${installment.number}/$count'),
        subtitle: Text(
          'Vence em ${formatDateBr(installment.dueDate)}'
          '${installment.status == InstallmentStatus.partial ? ' · falta ${installment.remaining.brl}' : ''}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            MoneyText(installment.amount, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            installmentStatusChip(installment),
          ],
        ),
      ),
    );
  }
}

Widget installmentStatusChip(Installment installment) {
  if (installment.overdue) {
    return StatusChip(
      label: installment.status == InstallmentStatus.partial
          ? 'Parcial · vencida'
          : 'Vencida',
      tone: StatusTone.danger,
    );
  }
  return StatusChip(
    label: installment.status.label,
    tone: switch (installment.status) {
      InstallmentStatus.paid => StatusTone.success,
      InstallmentStatus.partial => StatusTone.warning,
      InstallmentStatus.pending => StatusTone.neutral,
    },
  );
}
