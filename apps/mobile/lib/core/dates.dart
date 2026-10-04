/// Datas de calendário (vencimento, recebimento) trafegam como AAAA-MM-DD,
/// sem horário nem conversão de fuso.
DateTime parseApiDate(String value) {
  final parts = value.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

String toApiDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${_two(date.month)}-${_two(date.day)}';

String formatDateBr(String apiDate) {
  final date = parseApiDate(apiDate);
  return '${_two(date.day)}/${_two(date.month)}/${date.year}';
}

String _two(int value) => value.toString().padLeft(2, '0');
