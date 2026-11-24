import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'features/auth/login_screen.dart';
import 'features/auth/session_controller.dart';
import 'features/auth/password_recovery_dialog.dart';
import 'features/home/home_shell.dart';
import 'features/settings/preferences_controller.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

class FinanceApp extends StatefulWidget {
  const FinanceApp({super.key, this.recoveryLink});

  final ({String email, String token})? recoveryLink;

  @override
  State<FinanceApp> createState() => _FinanceAppState();
}

class _FinanceAppState extends State<FinanceApp> {
  late var _recoveryLink = widget.recoveryLink;

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<PreferencesController?>();
    final link = _recoveryLink;
    return MaterialApp(
      title: 'BigDev.Z Finance',
      debugShowCheckedModeBanner: false,
      themeMode: preferences?.themeMode ?? ThemeMode.system,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: link != null
          ? Scaffold(
              body: SafeArea(
                child: PasswordRecoveryDialog(
                  initialEmail: link.email,
                  token: link.token,
                  onClose: (changed) {
                    if (changed) context.read<SessionController>().restore();
                    setState(() => _recoveryLink = null);
                  },
                ),
              ),
            )
          : const _SessionGate(),
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
