import 'package:flutter_test/flutter_test.dart';
import 'package:bigdevz_finance/core/api_client.dart';
import 'package:bigdevz_finance/features/auth/auth_models.dart';
import 'package:bigdevz_finance/features/members/space_member_models.dart';
import 'package:bigdevz_finance/features/members/space_members_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'dart:convert';

void main() {
  group('SpaceMembersRepository and SpaceMember Tests', () {
    const space = Space(
      id: 2,
      kind: 'PJ',
      name: 'Empresa Teste',
      role: 'administrador',
    );

    test('SpaceMember parses JSON correctly and provides role labels', () {
      final json = {
        'id': 10,
        'name': 'Carlos Operador',
        'email': 'carlos@empresa.com',
        'role': 'operador',
        'is_owner': false,
      };

      final member = SpaceMember.fromJson(json);

      expect(member.id, equals(10));
      expect(member.name, equals('Carlos Operador'));
      expect(member.email, equals('carlos@empresa.com'));
      expect(member.role, equals('operador'));
      expect(member.isOwner, isFalse);
      expect(member.roleLabel, equals('Operador'));
      expect(member.roleDescription, contains('lançamentos'));
    });

    test('SpaceMembersRepository list members from API', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/spaces/2/members'));
        expect(request.method, equals('GET'));

        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 1,
                'name': 'Admin Chefe',
                'email': 'admin@empresa.com',
                'role': 'administrador',
                'is_owner': true,
              },
              {
                'id': 2,
                'name': 'Lucas Financeiro',
                'email': 'lucas@empresa.com',
                'role': 'financeiro',
                'is_owner': false,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
      final repo = SpaceMembersRepository(api: apiClient);

      final members = await repo.list(space: space);

      expect(members.length, equals(2));
      expect(members.first.isAdmin, isTrue);
      expect(members.last.isFinancial, isTrue);
    });

    test('SpaceMembersRepository add/update member', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/spaces/2/members'));
        expect(request.method, equals('POST'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['email'], equals('contador@empresa.com'));
        expect(body['role'], equals('contador'));

        return http.Response(
          jsonEncode({
            'message': 'Membro adicionado ou atualizado com sucesso.',
            'data': {
              'id': 3,
              'name': 'Contador Silva',
              'email': 'contador@empresa.com',
              'role': 'contador',
              'is_owner': false,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
      final repo = SpaceMembersRepository(api: apiClient);

      final member = await repo.saveMember(
        space: space,
        email: 'contador@empresa.com',
        role: 'contador',
      );

      expect(member.role, equals('contador'));
      expect(member.isAccountant, isTrue);
    });

    test('SpaceMembersRepository remove member', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/spaces/2/members/3'));
        expect(request.method, equals('DELETE'));

        return http.Response(
          jsonEncode({'message': 'Membro removido do espaço com sucesso.'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
      final repo = SpaceMembersRepository(api: apiClient);

      await expectLater(
        repo.removeMember(space: space, memberId: 3),
        completes,
      );
    });
  });
}
