import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../auth/auth_models.dart';
import 'audit_models.dart';
import 'audit_repository.dart';

/// Seção reutilizável que exibe a timeline de auditoria de um registro específico.
class AuditTimelineSection extends StatefulWidget {
  const AuditTimelineSection({
    super.key,
    required this.api,
    required this.space,
    required this.subject,
    required this.subjectId,
  });

  final ApiClient api;
  final Space space;
  final String subject;
  final int subjectId;

  @override
  State<AuditTimelineSection> createState() => _AuditTimelineSectionState();
}

class _AuditTimelineSectionState extends State<AuditTimelineSection> {
  bool _loading = true;
  List<AuditItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AuditTimelineSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subject != widget.subject ||
        oldWidget.subjectId != widget.subjectId ||
        oldWidget.space.id != widget.space.id) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await AuditRepository(api: widget.api).list(
        space: widget.space,
        subject: widget.subject,
        subjectId: widget.subjectId,
        limit: 15,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _loading = false;
      });
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year.toString();
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  'Histórico de Auditoria',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_items.isEmpty)
              Text(
                'Nenhum registro de auditoria para este item.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              )
            else
              Column(
                children: [
                  for (var i = 0; i < _items.length; i++)
                    _TimelineRow(
                      item: _items[i],
                      isLast: i == _items.length - 1,
                      formattedDate: _formatDate(_items[i].createdAt),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.item,
    required this.isLast,
    required this.formattedDate,
  });

  final AuditItem item;
  final bool isLast;
  final String formattedDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dotColor = item.isCritical ? colors.error : colors.primary;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                const SizedBox(height: 4),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: colors.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.humanAction,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        formattedDate,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (item.userName != null && item.userName!.isNotEmpty)
                    Text(
                      'Por ${item.userName}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  if (item.reason != null && item.reason!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        item.reason!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
