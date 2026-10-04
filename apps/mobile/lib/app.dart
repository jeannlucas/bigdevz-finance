import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'features/auth/login_screen.dart';
import 'features/auth/session_controller.dart';
import 'features/home/home_shell.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BigDev.Z Finance',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const _SessionGate(),
    );
  }
}

class _SessionGate extends StatelessWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return switch (session.status) {
      SessionStatus.restoring => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      SessionStatus.unreachable => Scaffold(
        body: SafeArea(
          child: ErrorState(
            message: session.message ?? 'API indisponível.',
            onRetry: session.restore,
          ),
        ),
      ),
      SessionStatus.signedOut => const LoginScreen(),
      SessionStatus.signedIn => const HomeShell(),
    };
  }
}
