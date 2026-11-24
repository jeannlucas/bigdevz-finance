import 'package:flutter/foundation.dart';

/// Ambientes suportados pelo BigDev.Z Finance.
enum AppEnvironment {
  local,
  staging,
  production;

  static AppEnvironment fromString(String value) {
    switch (value.trim().toLowerCase()) {
      case 'production':
      case 'prod':
        return AppEnvironment.production;
      case 'staging':
      case 'homolog':
      case 'hml':
        return AppEnvironment.staging;
      case 'local':
      case 'dev':
      case 'development':
      default:
        return AppEnvironment.local;
    }
  }

  bool get isLocal => this == AppEnvironment.local;
  bool get isStaging => this == AppEnvironment.staging;
  bool get isProduction => this == AppEnvironment.production;

  String get label {
    switch (this) {
      case AppEnvironment.production:
        return 'Produção';
      case AppEnvironment.staging:
        return 'Homologação';
      case AppEnvironment.local:
        return 'Ambiente Local (Desenvolvimento)';
    }
  }

  String get badgeText {
    switch (this) {
      case AppEnvironment.production:
        return 'PRODUÇÃO';
      case AppEnvironment.staging:
        return 'HOMOLOGAÇÃO';
      case AppEnvironment.local:
        return 'DEV LOCAL';
    }
  }
}

/// Exceção de segurança e conformidade de ambiente.
class EnvironmentConfigurationException implements Exception {
  const EnvironmentConfigurationException(this.message);

  final String message;

  @override
  String toString() => 'EnvironmentConfigurationException: $message';
}

/// Ambiente informado no build via --dart-define=APP_ENV=... (padrão: local).
const String rawAppEnv = String.fromEnvironment(
  'APP_ENV',
  defaultValue: 'local',
);

/// URL bruta informada via --dart-define=API_BASE_URL=...
const String rawConfiguredApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: '',
);

/// Ambiente ativo na execução.
AppEnvironment get currentEnvironment => AppEnvironment.fromString(rawAppEnv);

/// Resolve o endpoint canônico da API com validações rigorosas de segurança
/// para impedir contaminação cruzada entre desenvolvimento, homologação e produção.
String resolveApiBaseUrl({
  String? configuredUrl,
  String? environmentName,
  bool isWeb = kIsWeb,
  Uri? runtimeUri,
}) {
  final env = AppEnvironment.fromString(environmentName ?? rawAppEnv);
  final raw = (configuredUrl ?? rawConfiguredApiBaseUrl).trim();

  // Validações específicas para execução Web (navegador)
  if (isWeb && runtimeUri != null) {
    final host = runtimeUri.host.toLowerCase();
    final isLocalHost =
        host == 'localhost' || host == '127.0.0.1' || host == '0.0.0.0';

    // Regra 1 (Anti-Vazamento): Execução em host local jamais pode chamar o domínio de produção.
    if (isLocalHost) {
      if (raw.toLowerCase().contains('finance.bigdevz.com') ||
          (raw.toLowerCase().contains('bigdevz.com') &&
              !raw.toLowerCase().contains('local'))) {
        throw const EnvironmentConfigurationException(
          'Bloqueio de Segurança: A execução em host local do navegador foi configurada '
          'com o domínio de produção. Altere API_BASE_URL para a API local (http://127.0.0.1:8000/api).',
        );
      }
    }

    // Regra 2: Aplicação hospedada no domínio de produção jamais pode chamar endpoints de loopback/local.
    if (host.contains('finance.bigdevz.com')) {
      if (raw.contains('localhost') ||
          raw.contains('127.0.0.1') ||
          raw.contains('10.0.2.2') ||
          raw.contains(':8000')) {
        throw const EnvironmentConfigurationException(
          'Bloqueio de Segurança: O frontend hospedado em produção não pode consumir endpoints locais.',
        );
      }

      // Se a URL não foi explicitada ou for relativa, utiliza a mesma origem do host em HTTPS.
      if (raw.isEmpty || raw.startsWith('/')) {
        return '${runtimeUri.origin}/api';
      }
    }
  }

  // Regra 3: Validação de Produção (APP_ENV=production)
  if (env.isProduction) {
    if (raw.isEmpty) {
      if (isWeb && runtimeUri != null && runtimeUri.origin.isNotEmpty) {
        return '${runtimeUri.origin}/api';
      }
      return 'https://finance.bigdevz.com/api';
    }

    if (raw.startsWith('http://')) {
      throw const EnvironmentConfigurationException(
        'Bloqueio de Segurança: O ambiente de produção exige obrigatoriamente transporte seguro HTTPS.',
      );
    }

    if (raw.contains('localhost') ||
        raw.contains('127.0.0.1') ||
        raw.contains('10.0.2.2') ||
        raw.contains(':8000') ||
        raw.contains(':8080')) {
      throw const EnvironmentConfigurationException(
        'Bloqueio de Segurança: O build de produção não pode conter endereços locais de desenvolvimento.',
      );
    }

    return raw;
  }

  // Regra 4: Validação de Ambiente Local (APP_ENV=local)
  if (env.isLocal) {
    if (raw.toLowerCase().contains('finance.bigdevz.com')) {
      throw const EnvironmentConfigurationException(
        'Bloqueio de Segurança: O ambiente local (APP_ENV=local) não pode apontar para o domínio de produção.',
      );
    }

    if (raw.isEmpty) {
      return 'http://127.0.0.1:8000/api';
    }

    return raw;
  }

  // Regra 5: Homologação / Staging
  if (env.isStaging) {
    if (raw.toLowerCase().contains('finance.bigdevz.com') &&
        !raw.contains('staging') &&
        !raw.contains('hml')) {
      throw const EnvironmentConfigurationException(
        'Bloqueio de Segurança: O ambiente de homologação não pode apontar para a produção.',
      );
    }
    if (raw.isEmpty) {
      return 'https://staging-finance.bigdevz.com/api';
    }
    return raw;
  }

  return raw.isEmpty ? 'http://127.0.0.1:8000/api' : raw;
}

/// Endpoint canônico resolvido da API.
String get apiBaseUrl =>
    resolveApiBaseUrl(isWeb: kIsWeb, runtimeUri: kIsWeb ? Uri.base : null);

/// Versão e número de build incorporados ao artefato durante a compilação.
const String appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.0.0',
);

const String appBuildNumber = String.fromEnvironment(
  'APP_BUILD',
  defaultValue: '1',
);

const String appVersionLabel = '$appVersion (Build $appBuildNumber)';
