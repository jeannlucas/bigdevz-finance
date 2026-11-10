import 'package:flutter_test/flutter_test.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';

void main() {
  group('Space RBAC and Period Closing Model Tests', () {
    test('Space parses role and closedUntil correctly from JSON', () {
      final json = {
        'id': 10,
        'kind': 'PJ',
        'name': 'BigDev.Z Corp',
        'role': 'operador',
        'closed_until': '2026-10-31',
      };

      final space = Space.fromJson(json);

      expect(space.id, equals(10));
      expect(space.kind, equals('PJ'));
      expect(space.name, equals('BigDev.Z Corp'));
      expect(space.role, equals('operador'));
      expect(space.closedUntil, equals('2026-10-31'));

      expect(space.isPf, isFalse);
      expect(space.isOperator, isTrue);
      expect(space.isAdmin, isFalse);
      expect(space.isAccountant, isFalse);
      expect(space.isFinancial, isFalse);

      // Permissões de operador
      expect(space.canCancel, isFalse);
      expect(space.canExport, isFalse);
      expect(space.canMoveMoney, isTrue);
    });

    test('Space defaults role to administrador when not present', () {
      final json = {'id': 1, 'kind': 'PF', 'name': 'Pessoal'};

      final space = Space.fromJson(json);

      expect(space.role, equals('administrador'));
      expect(space.isAdmin, isTrue);
      expect(space.canCancel, isTrue);
      expect(space.canExport, isTrue);
      expect(space.canMoveMoney, isTrue);
    });

    test('Space role contador has read-only and export permissions only', () {
      final space = Space(id: 2, kind: 'PJ', name: 'Holding', role: 'contador');

      expect(space.isAccountant, isTrue);
      expect(space.canCancel, isFalse);
      expect(space.canMoveMoney, isFalse);
      expect(space.canExport, isTrue);
    });
  });
}
