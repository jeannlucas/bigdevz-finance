import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../ui/app_brand.dart';
import '../../ui/widgets.dart';
import 'login_credit_native.dart'
    if (dart.library.js_interop) 'login_credit_web.dart';
import 'password_recovery_dialog.dart';
import 'session_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_form.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await context.read<SessionController>().login(
        _email.text.trim(),
        _password.text,
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final notice = context.select<SessionController, String?>(
      (session) => session.message,
    );

    final form = Form(
      key: _form,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Acesse sua conta',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            if (!currentEnvironment.isProduction) ...[
              const SizedBox(height: 6),
              Text(
                currentEnvironment.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (_error != null || notice != null) ...[
              FormErrorBanner(_error ?? notice!),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(
                labelText: 'E-mail',
                prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
              ),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              autocorrect: false,
              validator: (value) => (value ?? '').trim().contains('@')
                  ? null
                  : 'Informe seu e-mail.',
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              decoration: InputDecoration(
                labelText: 'Senha',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Mostrar senha' : 'Ocultar senha',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                ),
              ),
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              validator: (value) =>
                  (value ?? '').isEmpty ? 'Informe sua senha.' : null,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _submitting
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (_) => PasswordRecoveryDialog(
                          initialEmail: _email.text.trim(),
                        ),
                      ),
                child: const Text('Esqueci minha senha'),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text('Entrar'),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 840;
            final gutter = desktop ? 32.0 : 16.0;
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(gutter, 20, gutter, 12),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: (constraints.maxWidth - gutter * 2).clamp(
                    0,
                    double.infinity,
                  ),
                  minHeight: (constraints.maxHeight - 32).clamp(
                    0,
                    double.infinity,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(height: 28),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: desktop ? 1000 : 440,
                      ),
                      child: Container(
                        key: const ValueKey('login-panel'),
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: colors.surface,
                          border: Border.all(color: colors.outlineVariant),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: desktop
                            ? IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const Expanded(
                                      flex: 6,
                                      child: _LoginBrand(desktop: true),
                                    ),
                                    Expanded(
                                      flex: 5,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 36,
                                          vertical: 40,
                                        ),
                                        child: form,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const _LoginBrand(desktop: false),
                                  Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: form,
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const _LoginCredit(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand({required this.desktop});

  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF253C82),
                  Color(0xFF142145),
                  Color(0xFF111A2F),
                ],
              ),
            ),
          ),
        ),
        if (desktop)
          const Positioned(
            right: -28,
            bottom: -54,
            child: ExcludeSemantics(
              child: GorillaSymbol(
                size: 310,
                color: Color(0xFFB7CBFF),
                opacity: 0.13,
                brightness: Brightness.dark,
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.all(desktop ? 44 : 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: desktop ? 390 : 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Row(
                  children: [
                    GorillaSymbol(
                      size: 34,
                      color: Colors.white,
                      brightness: Brightness.dark,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'BigDev',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '.Z',
                      style: TextStyle(
                        color: Color(0xFFADC2FF),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(width: 9),
                    Text(
                      'FINANCE',
                      style: TextStyle(
                        color: Color(0xFFCFD8F7),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: desktop ? 36 : 12),
                Text(
                  'Finanças pessoais e da empresa, separadas.',
                  style:
                      (desktop
                              ? theme.textTheme.displaySmall
                              : theme.textTheme.bodyMedium)
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: desktop
                                ? FontWeight.w700
                                : FontWeight.w500,
                            letterSpacing: desktop ? -1.2 : 0,
                            height: desktop ? 1.12 : 1.35,
                          ),
                ),
                if (desktop) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Veja seus saldos e acompanhe o que tem a pagar e a receber em cada espaço.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFFD2DDFB),
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginCredit extends StatelessWidget {
  const _LoginCredit();

  static const _url = 'https://bigdevz.com/';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Text('Desenvolvido por', style: theme.textTheme.bodySmall),
          Semantics(
            link: kIsWeb,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                textStyle: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: () async {
                await openCompanySite(_url);
                if (!kIsWeb && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link da BigDev.Z copiado.')),
                  );
                }
              },
              child: const Text('BigDev.Z - IT Consulting'),
            ),
          ),
        ],
      ),
    );
  }
}
