import 'package:flutter_test/flutter_test.dart';
import 'package:bigdevz_finance/core/config.dart';

void main() {
  group('AppEnvironment', () {
    test('converte strings com tolerância a maiúsculas e espaços', () {
      expect(AppEnvironment.fromString('local'), AppEnvironment.local);
      expect(AppEnvironment.fromString('DEV'), AppEnvironment.local);
      expect(AppEnvironment.fromString('development '), AppEnvironment.local);
      expect(AppEnvironment.fromString('staging'), AppEnvironment.staging);
      expect(AppEnvironment.fromString('HML'), AppEnvironment.staging);
      expect(
        AppEnvironment.fromString('production'),
        AppEnvironment.production,
      );
      expect(AppEnvironment.fromString('PROD'), AppEnvironment.production);
      expect(AppEnvironment.fromString('desconhecido'), AppEnvironment.local);
    });

    test('propriedades booleanas identificam ambiente corretamente', () {
      expect(AppEnvironment.local.isLocal, isTrue);
      expect(AppEnvironment.local.isProduction, isFalse);
      expect(AppEnvironment.production.isProduction, isTrue);
      expect(AppEnvironment.production.isLocal, isFalse);
      expect(AppEnvironment.staging.isStaging, isTrue);
    });
  });

  group('resolveApiBaseUrl', () {
    test(
      'em ambiente local sem URL informada retorna endpoint local padrão',
      () {
        final url = resolveApiBaseUrl(
          environmentName: 'local',
          configuredUrl: '',
          isWeb: false,
        );
        expect(url, 'http://127.0.0.1:8000/api');
      },
    );

    test('em ambiente local aceita endpoint local customizado', () {
      final url = resolveApiBaseUrl(
        environmentName: 'local',
        configuredUrl: 'http://192.168.1.100:8000/api',
        isWeb: false,
      );
      expect(url, 'http://192.168.1.100:8000/api');
    });

    test('em ambiente local rejeita terminantemente domínio de produção', () {
      expect(
        () => resolveApiBaseUrl(
          environmentName: 'local',
          configuredUrl: 'https://finance.bigdevz.com/api',
          isWeb: false,
        ),
        throwsA(isA<EnvironmentConfigurationException>()),
      );
    });

    test('no navegador em host local rejeita chamada para produção', () {
      expect(
        () => resolveApiBaseUrl(
          environmentName: 'local',
          configuredUrl: 'https://finance.bigdevz.com/api',
          isWeb: true,
          runtimeUri: Uri.parse('http://localhost:8085/#/login'),
        ),
        throwsA(isA<EnvironmentConfigurationException>()),
      );
    });

    test('no navegador em host 127.0.0.1 rejeita chamada para produção', () {
      expect(
        () => resolveApiBaseUrl(
          environmentName: 'local',
          configuredUrl: 'https://finance.bigdevz.com/api',
          isWeb: true,
          runtimeUri: Uri.parse('http://127.0.0.1:8085/'),
        ),
        throwsA(isA<EnvironmentConfigurationException>()),
      );
    });

    test('no navegador em domínio de produção rejeita endpoints locais de loopback', () {
      expect(
        () => resolveApiBaseUrl(
          environmentName: 'production',
          configuredUrl: 'http://127.0.0.1:8000/api',
          isWeb: true,
          runtimeUri: Uri.parse('https://finance.bigdevz.com/'),
        ),
        throwsA(isA<EnvironmentConfigurationException>()),
      );
    });

    test('no navegador em domínio de produção sem URL informada deriva endpoint relativo da mesma origem', () {
      final url = resolveApiBaseUrl(
        environmentName: 'production',
        configuredUrl: '',
        isWeb: true,
        runtimeUri: Uri.parse('https://finance.bigdevz.com/'),
      );
      expect(url, 'https://finance.bigdevz.com/api');
    });

    test('em produção rejeita transporte inseguro HTTP', () {
      expect(
        () => resolveApiBaseUrl(
          environmentName: 'production',
          configuredUrl: 'http://finance.bigdevz.com/api',
          isWeb: false,
        ),
        throwsA(isA<EnvironmentConfigurationException>()),
      );
    });

    test('em produção rejeita portas ou endereços locais', () {
      expect(
        () => resolveApiBaseUrl(
          environmentName: 'production',
          configuredUrl: 'https://127.0.0.1:8000/api',
          isWeb: false,
        ),
        throwsA(isA<EnvironmentConfigurationException>()),
      );
    });

    test('em produção aceita URL HTTPS válida', () {
      final url = resolveApiBaseUrl(
        environmentName: 'production',
        configuredUrl: 'https://finance.bigdevz.com/api',
        isWeb: false,
      );
      expect(url, 'https://finance.bigdevz.com/api');
    });
  });
}
