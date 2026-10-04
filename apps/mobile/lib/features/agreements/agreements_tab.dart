import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import 'agreement.dart';
import 'agreement_screen.dart';
import 'agreements_repository.dart';

class AgreementsTab extends StatelessWidget {
  const AgreementsTab({super.key, required this.space});

  final Space space;

  @override
  Widget build(BuildContext context) {
    return LoadView<List<Agreement>>(
      load: () => context.read<AgreementsRepository>().list(space.id),
      isEmpty: (agreements) => agreements.isEmpty,
      empty: (context, _) => const EmptyState(
        icon: Icons.handshake_outlined,
        title: 'Nenhum acordo a receber',
        message: 'Cadastre uma venda parcelada para acompanhar parcelas e recebimentos. Valores previstos não alteram o saldo.',
      ),
      builder: (context, agreements, refresh) => RefreshIndicator(
        onRefresh: refresh,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: agreements.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) => AgreementCard(
            agreement: agreements[index],
            onTap: () => Navigator.of(context).push(
              spaceRoute(isPf: space.isPf, child: AgreementScreen(space: space, agreementId: agreements[index].id)),
            ),
          ),
        ),
      ),
    );
  }
}

class AgreementCard extends StatelessWidget {
  const AgreementCard({super.key, required this.agreement, this.onTap});

  final Agreement agreement;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = agreement.total.cents == 0 ? 0.0 : agreement.received.cents / agreement.total.cents;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(agreement.description, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
              if (agreement.overdueInstallments > 0)
                StatusChip(label: '${agreement.overdueInstallments} vencida(s)', tone: StatusTone.danger)
              else if (agreement.remaining.isZero)
                const StatusChip(label: 'Quitado', tone: StatusTone.success),
            ]),
            const SizedBox(height: 12),
            // Proporção só para a barra visual; valores exibidos vêm da API.
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(value: progress, minHeight: 8, semanticsLabel: 'Recebido do acordo'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _Labeled(label: 'Falta receber', child: MoneyText(agreement.remaining, style: theme.textTheme.titleMedium))),
              _Labeled(label: 'Total', alignEnd: true, child: MoneyText(agreement.total, style: theme.textTheme.bodyLarge)),
            ]),
            const SizedBox(height: 8),
            Text(
              '${agreement.paidInstallments} de ${agreement.installmentCount} parcelas quitadas'
              '${agreement.nextDueDate != null ? ' · próximo vencimento ${formatDateBr(agreement.nextDueDate!)}' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child, this.alignEnd = false});

  final String label;
  final Widget child;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [Text(label, style: Theme.of(context).textTheme.labelSmall), const SizedBox(height: 2), child],
      );
}
