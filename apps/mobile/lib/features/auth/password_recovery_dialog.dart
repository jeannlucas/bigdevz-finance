import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../ui/widgets.dart';
import 'session_controller.dart';

class PasswordRecoveryDialog extends StatefulWidget {
  const PasswordRecoveryDialog({
    super.key,
    required this.initialEmail,
    this.token,
    this.onClose,
  });

  final String initialEmail;
  final String? token;
  final ValueChanged<bool>? onClose;

  @override
  State<PasswordRecoveryDialog> createState() => _PasswordRecoveryDialogState();
}

class _PasswordRecoveryDialogState extends State<PasswordRecoveryDialog> {
  static const _passwordRequirement =
      'Use pelo menos 8 caracteres e inclua uma letra.';
  static final _letter = RegExp(r'\p{L}', unicode: true);

  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  bool _done = false;
  String? _error;

  bool get _resetting => widget.token != null;
  bool get _invalidLink =>
      _resetting && (widget.token!.length != 64 || widget.initialEmail.isEmpty);

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _close() {
    final onClose = widget.onClose;
    if (onClose == null) {
      Navigator.of(context).pop();
    } else {
      onClose(_done && _resetting);
    }
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = context.read<SessionController>();
      if (_resetting) {
        await session.resetPassword(
          email: widget.initialEmail,
          token: widget.token!,
          password: _password.text,
          confirmation: _confirmation.text,
        );
      } else {
        await session.requestPasswordLink(_email.text.trim());
      }
      if (mounted) setState(() => _done = true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(
          () => _error =
              error.fieldErrors['token'] ??
              error.fieldErrors['password'] ??
              error.fieldErrors['email'] ??
              error.message,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final finished = _done || _invalidLink;
    return AlertDialog(
      scrollable: true,
      title: Text(_resetting ? 'Redefinir senha' : 'Recuperar senha'),
      content: SizedBox(
        width: 400,
        child: finished
            ? Text(
                _invalidLink
                    ? 'Link inválido. Volte ao login e solicite um novo link.'
                    : _resetting
                    ? 'Senha alterada. Entre com sua nova senha.'
                    : 'Se o e-mail estiver cadastrado, você receberá um link para redefinir a senha.',
              )
            : Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error case final error?) ...[
                        FormErrorBanner(error),
                        const SizedBox(height: 12),
                      ],
                      if (_resetting) ...[
                        TextFormField(
                          controller: _password,
                          decoration: const InputDecoration(
                            labelText: 'Nova senha',
                            helperText: _passwordRequirement,
                            helperMaxLines: 2,
                            errorMaxLines: 2,
                          ),
                          obscureText: true,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            final password = value ?? '';
                            if (password.runes.length < 8 ||
                                !_letter.hasMatch(password)) {
                              return _passwordRequirement;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirmation,
                          decoration: const InputDecoration(
                            labelText: 'Confirme a nova senha',
                          ),
                          obscureText: true,
                          autofillHints: const [AutofillHints.newPassword],
                          onFieldSubmitted: (_) => _submit(),
                          validator: (value) => value != _password.text
                              ? 'As senhas precisam ser iguais.'
                              : null,
                        ),
                      ] else
                        TextFormField(
                          controller: _email,
                          decoration: const InputDecoration(
                            labelText: 'E-mail',
                          ),
                          autofillHints: const [AutofillHints.email],
                          keyboardType: TextInputType.emailAddress,
                          onFieldSubmitted: (_) => _submit(),
                          validator: (value) =>
                              (value ?? '').trim().contains('@')
                              ? null
                              : 'Informe seu e-mail.',
                        ),
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _close,
          child: Text(finished || _resetting ? 'Voltar ao login' : 'Cancelar'),
        ),
        if (!finished)
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(
              _busy
                  ? 'Aguarde…'
                  : _resetting
                  ? 'Alterar senha'
                  : 'Enviar link',
            ),
          ),
      ],
    );
  }
}
