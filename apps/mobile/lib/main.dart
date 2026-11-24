import 'package:flutter/material.dart';

import 'bootstrap.dart';
import 'core/config.dart';
import 'core/token_storage.dart';
import 'features/auth/password_recovery_link_native.dart'
    if (dart.library.js_interop) 'features/auth/password_recovery_link_web.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final baseUrl = apiBaseUrl;
    runApp(
      buildApp(
        baseUrl: baseUrl,
        storage: const SecureSessionStorage(),
        recoveryLink: takePasswordRecoveryLink(),
      ),
    );
  } on EnvironmentConfigurationException catch (e) {
    runApp(EnvironmentConfigurationErrorApp(message: e.message));
  } catch (e) {
    runApp(EnvironmentConfigurationErrorApp(message: e.toString()));
  }
}

/// Aplicação de contingência exibida quando há inconsistência de configuração de ambiente.
class EnvironmentConfigurationErrorApp extends StatelessWidget {
  const EnvironmentConfigurationErrorApp({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Configuração de Ambiente — BigDev.Z Finance',
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                color: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.security_update_warning_rounded,
                        color: Color(0xFFEF4444),
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Bloqueio de Segurança de Ambiente',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        message,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFFCBD5E1),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
