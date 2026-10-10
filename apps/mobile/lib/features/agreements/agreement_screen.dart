import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import 'agreement.dart';
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
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SpaceBadge(space),
              const SizedBox(height: 16),
              AgreementCard(agreement: agreement),
              const SizedBox(height: 16),
              Text('Parcelas', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
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
    );
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
