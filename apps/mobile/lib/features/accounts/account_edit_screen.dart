import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/text_formatters.dart';
import '../../ui/app_tokens.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import 'account.dart';
import 'accounts_repository.dart';
import 'bank_catalog.dart';

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
  final _nameFocus = FocusNode();
  late final _name = TextEditingController(
    text: toFinancialUpper(widget.account.name),
  );
  late BankInfo? _selectedBank = BankCatalog.resolveForAccount(widget.account);
  bool _saving = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _name.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) {
      if (_name.text.trim().isEmpty) {
        focusAndEnsureVisible(_nameFocus);
      }
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final account = await context.read<AccountsRepository>().rename(
        widget.space.id,
        widget.account.id,
        _name.text.trim(),
        bankId: _selectedBank?.id,
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
              focusNode: _nameFocus,
              controller: _name,
              inputFormatters: const [UpperCaseTextFormatter()],
              decoration: InputDecoration(
                labelText: 'Nome da conta *',
                errorText: fieldErrors['name'],
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLength: 80,
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Informe um nome.' : null,
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final currentBank =
                    _selectedBank ?? BankCatalog.findByAccountName(_name.text);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: (currentBank?.color ?? Colors.grey).withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(AppTokens.r8),
                        border: Border.all(
                          color: (currentBank?.color ?? Colors.grey).withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          if (currentBank != null && !currentBank.isOther) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.asset(
                                currentBank.assetPath,
                                width: 18,
                                height: 18,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => Container(
                                  width: 18,
                                  height: 18,
                                  color: currentBank.color,
                                  alignment: Alignment.center,
                                  child: Text(
                                    currentBank.name.substring(0, 1),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Instituição: ${currentBank.name} (COMPE: ${currentBank.code})',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: currentBank.color,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ] else ...[
                            const Icon(
                              Icons.account_balance_outlined,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Instituição: Outro (Personalizada)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Reassociar instituição rapidamente:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ActionChip(
                          avatar: const Icon(
                            Icons.swap_horiz_rounded,
                            size: 16,
                          ),
                          label: const Text('Wise'),
                          onPressed: () {
                            setState(() {
                              _selectedBank = BankCatalog.wise;
                              _name.text = 'WISE';
                            });
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(
                            Icons.swap_horiz_rounded,
                            size: 16,
                          ),
                          label: const Text('DUCZ Benefícios'),
                          onPressed: () {
                            setState(() {
                              _selectedBank = BankCatalog.ducz;
                              _name.text = 'DUCZ BENEFÍCIOS';
                            });
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(
                            Icons.swap_horiz_rounded,
                            size: 16,
                          ),
                          label: const Text('Outro'),
                          onPressed: () {
                            setState(() {
                              _selectedBank = BankCatalog.outro;
                              _name.text = 'OUTRA CONTA';
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
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
