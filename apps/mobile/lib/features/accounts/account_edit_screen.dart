import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import 'account.dart';
import 'accounts_repository.dart';

/// Edição da identificação (nome). Atualiza a mesma conta: id, espaço, saldo
/// e histórico não mudam. Abertura tem fluxo próprio, auditado.
class AccountEditScreen extends StatefulWidget {
  const AccountEditScreen({
    super.key,
    required this.space,
    required this.account,
  });

  final Space space;
  final Account account;

  @override
  State<AccountEditScreen> createState() => _AccountEditScreenState();
}

class _AccountEditScreenState extends State<AccountEditScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.account.name);
  bool _saving = false;
  ApiException? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final account = await context.read<AccountsRepository>().rename(
        widget.space.id,
        widget.account.id,
        _name.text.trim(),
      );
      if (!mounted) return;
      context.read<SessionController>().dataChanged();
      Navigator.of(context).pop(account);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fieldErrors = _error?.fieldErrors ?? const {};
    return Scaffold(
      appBar: AppBar(title: const Text('Editar conta')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SpaceBadge(widget.space, prefix: 'Conta do espaço'),
            const SizedBox(height: 20),
            if (_error != null && fieldErrors.isEmpty) ...[
              FormErrorBanner(_error!.message),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                labelText: 'Nome da conta',
                errorText: fieldErrors['name'],
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLength: 80,
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Informe um nome.' : null,
            ),
            const SizedBox(height: 8),
            Text(
              'Renomear não altera saldos nem o histórico. Saldo inicial e data '
              'de abertura são corrigidos em "Corrigir abertura".',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text('Salvar alterações'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}
