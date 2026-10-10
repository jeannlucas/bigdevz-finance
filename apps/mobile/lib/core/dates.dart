/// Datas de calendário (vencimento, recebimento) trafegam como AAAA-MM-DD,
/// ou ISO-8601 (com hora/fuso em timestamps de auditoria como adjusted_at).
DateTime parseApiDate(String value) {
  final datePart = value.contains('T')
      ? value.split('T')[0]
      : (value.contains(' ') ? value.split(' ')[0] : value);
  final parts = datePart.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

String toApiDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${_two(date.month)}-${_two(date.day)}';

String formatDateBr(String apiDate) {
  final date = parseApiDate(apiDate);
  return '${_two(date.day)}/${_two(date.month)}/${date.year}';
}

String _two(int value) => value.toString().padLeft(2, '0');
