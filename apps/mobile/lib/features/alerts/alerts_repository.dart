import '../../core/api_client.dart';
import '../../core/money.dart';

/// Alerta financeiro auditável (sininho de notificações).
class AlertItem {
  const AlertItem({
    required this.key,
    required this.targetId,
    required this.type,
    required this.title,
    required this.description,
    this.dueDate,
    this.amount,
    this.amountCents,
    this.isCritical = false,
    this.isRead = false,
    this.isDismissed = false,
    this.readAt,
    this.dismissedAt,
  });

  factory AlertItem.fromJson(Map<String, dynamic> json) => AlertItem(
    key: json['key'] as String,
    targetId: json['target_id'] as int,
    type: json['type'] as String,
    title: json['title'] as String,
    description: json['description'] as String,
    dueDate: json['due_date'] as String?,
    amount: json['amount'] != null
        ? Money.parse(json['amount'] as String)
        : null,
    amountCents: json['amount_cents'] as int?,
    isCritical: json['is_critical'] as bool? ?? false,
    isRead: json['is_read'] as bool? ?? false,
    isDismissed: json['is_dismissed'] as bool? ?? false,
    readAt: json['read_at'] as String?,
    dismissedAt: json['dismissed_at'] as String?,
  );

  final String key;
  final int targetId;
  final String type;
  final String title;
  final String description;
  final String? dueDate;
  final Money? amount;
  final int? amountCents;
  final bool isCritical;
  final bool isRead;
  final bool isDismissed;
  final String? readAt;
  final String? dismissedAt;

  AlertItem copyWith({
    bool? isRead,
    bool? isDismissed,
    String? readAt,
    String? dismissedAt,
  }) => AlertItem(
    key: key,
    targetId: targetId,
    type: type,
    title: title,
    description: description,
    dueDate: dueDate,
    amount: amount,
    amountCents: amountCents,
    isCritical: isCritical,
    isRead: isRead ?? this.isRead,
    isDismissed: isDismissed ?? this.isDismissed,
    readAt: readAt ?? this.readAt,
    dismissedAt: dismissedAt ?? this.dismissedAt,
  );
}

class AlertsResult {
  const AlertsResult({
    required this.alerts,
    required this.unreadActiveCount,
    required this.totalActiveCount,
  });

  final List<AlertItem> alerts;
  final int unreadActiveCount;
  final int totalActiveCount;
}

/// Repositório de alertas e notificações com persistência por usuário e espaço.
class AlertsRepository {
  const AlertsRepository(this._api);

  final ApiClient _api;

  /// Lista alertas para o espaço e usuário logado.
  Future<AlertsResult> list(
    int spaceId, {
    bool includeDismissed = false,
  }) async {
    final query = includeDismissed ? '?include_dismissed=true' : '';
    final res = await _api.get('/spaces/$spaceId/alerts$query');
    final data = res['data'] as List<dynamic>;
    final meta = res['meta'] as Map<String, dynamic>? ?? {};

    return AlertsResult(
      alerts: data
          .map((item) => AlertItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      unreadActiveCount: meta['unread_active_count'] as int? ?? 0,
      totalActiveCount: meta['total_active_count'] as int? ?? 0,
    );
  }

  /// Consulta apenas a contagem não lida ativa para badge da barra superior.
  Future<int> badge(int spaceId) async {
    try {
      final res = await _api.get('/spaces/$spaceId/alerts/badge');
      final data = res['data'] as Map<String, dynamic>;
      return data['unread_active_count'] as int? ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Marca alerta como lido (decrementa contador e mantém consultável).
  Future<void> read(int spaceId, String alertKey) async {
    await _api.post('/spaces/$spaceId/alerts/$alertKey/read', {});
  }

  /// Marca alerta como dispensado (remove da lista ativa, preservando a obrigação).
  Future<void> dismiss(int spaceId, String alertKey) async {
    await _api.post('/spaces/$spaceId/alerts/$alertKey/dismiss', {});
  }
}
