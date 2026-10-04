import 'package:bigdevz_finance/core/dates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('converte data de calendário sem fuso', () {
    expect(formatDateBr('2026-02-28'), '28/02/2026');
    expect(toApiDate(DateTime(2026, 3, 1)), '2026-03-01');
    expect(parseApiDate('2026-01-31'), DateTime(2026, 1, 31));
  });
}
