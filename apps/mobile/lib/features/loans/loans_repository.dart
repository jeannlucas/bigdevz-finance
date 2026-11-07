import '../../core/api_client.dart';
import '../../core/money.dart';
import 'loan.dart';

class LoansRepository {
  const LoansRepository(this._api);

  final ApiClient _api;

  Future<List<Loan>> list(int spaceId, {String? kind, String? status}) async {
    final queryParams = <String>[];
    if (kind != null && kind.isNotEmpty && kind != 'all') {
      queryParams.add('kind=$kind');
    }
    if (status != null && status.isNotEmpty && status != 'all') {
      queryParams.add('status=$status');
    }
    final qs = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final response = await _api.get('/spaces/$spaceId/loans$qs');
    final data = (response['data'] as List)
        .map((item) => Loan.fromJson(item as Map<String, dynamic>))
        .toList();
    return data;
  }

  Future<Loan> find(int spaceId, int loanId) async {
    final response = await _api.get('/spaces/$spaceId/loans/$loanId');
    return Loan.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<Loan> create(
    int spaceId, {
    required String kind,
    required String title,
    required String counterparty,
    required Money principal,
    required Money total,
    required int installmentCount,
    required String firstDueDate,
    int? disbursementAccountId,
    String? disbursedAt,
    String? notes,
    required String idempotencyKey,
  }) async {
    final body = <String, dynamic>{
      'kind': kind,
      'title': title,
      'counterparty': counterparty,
      'principal': principal.toApi(),
      'total': total.toApi(),
      'installment_count': installmentCount,
      'first_due_date': firstDueDate,
      'disbursement_account_id': ?disbursementAccountId,
      'disbursed_at': ?disbursedAt,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    };

    final response = await _api.post(
      '/spaces/$spaceId/loans',
      body,
      idempotencyKey: idempotencyKey,
    );

    return Loan.fromJson(response['data'] as Map<String, dynamic>);
  }
}
