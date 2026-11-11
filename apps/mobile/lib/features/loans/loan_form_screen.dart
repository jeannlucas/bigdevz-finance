import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/text_formatters.dart';
import '../../ui/date_field.dart';
import '../accounts/account.dart';
import '../accounts/accounts_repository.dart';
import '../auth/auth_models.dart';
import 'loans_repository.dart';

class LoanFormScreen extends StatefulWidget {
  const LoanFormScreen({super.key, required this.space, this.accounts});

  final Space space;
  final List<Account>? accounts;

  @override
  State<LoanFormScreen> createState() => _LoanFormScreenState();
}

class _LoanFormScreenState extends State<LoanFormScreen> {
  final _form = GlobalKey<FormState>();

  String _kind = 'taken'; // taken, granted
  final _title = TextEditingController();
  final _counterparty = TextEditingController();
  final _principal = TextEditingController();
  final _total = TextEditingController();
  final _installmentCount = TextEditingController(text: '12');
  final _notes = TextEditingController();

  DateTime _firstDueDate = DateUtils.dateOnly(DateTime.now())
      .add(const Duration(days: 30));
  bool _recordDisbursement = false;
  int? _disbursementAccountId;
  DateTime _disbursedAt = DateUtils.dateOnly(DateTime.now());

  bool _loading = false;
  bool _saving = false;
  ApiException? _error;
  List<Account> _accounts = [];

  @override
  void initState() {
    super.initState();
    _principal.addListener(_onAmountChanged);
    _total.addListener(_onAmountChanged);
    if (widget.accounts != null) {
      _accounts = widget.accounts!.where((a) => !a.isArchived).toList();
      if (_accounts.isNotEmpty) {
        _disbursementAccountId = _accounts.first.id;
      }
    } else {
      _loadAccounts();
    }
  }

  void _onAmountChanged() {
    setState(() {});
  }

  Future<void> _loadAccounts() async {
    setState(() => _loading = true);
    try {
      final list = await context.read<AccountsRepository>().list(
        widget.space.id,
      );
      if (!mounted) return;
      setState(() {
        _accounts = list.where((a) => !a.isArchived).toList();
        if (_accounts.isNotEmpty && _disbursementAccountId == null) {
          _disbursementAccountId = _accounts.first.id;
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _principal.removeListener(_onAmountChanged);
    _total.removeListener(_onAmountChanged);
    _title.dispose();
    _counterparty.dispose();
    _principal.dispose();
    _total.dispose();
    _installmentCount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Money? get _parsedPrincipal => Money.fromInput(_principal.text);
  Money? get _parsedTotal => Money.fromInput(_total.text);

  String? get _interestPreview {
    final p = _parsedPrincipal;
    final t = _parsedTotal;
    if (p == null || t == null) return null;
    if (t.cents < p.cents) {
      return 'O total não pode ser menor que o principal.';
    }
    final interest = Money(t.cents - p.cents);
    return 'Juros/Encargos: ${interest.brl}';
  }

  Future<void> _submit() async {
    if (_saving || !_form.currentState!.validate()) return;

    final principal = _parsedPrincipal;
    if (principal == null || principal.cents <= 0) {
      setState(() {
        _error = const ApiException(
          'Informe um valor principal válido.',
          status: 422,
          fieldErrors: {'principal': 'Informe um valor maior que zero.'},
        );
      });
      return;
    }

    final total = _parsedTotal;
    if (total == null || total.cents < principal.cents) {
      setState(() {
        _error = const ApiException(
          'O valor total não pode ser menor que o principal.',
          status: 422,
          fieldErrors: {
            'total': 'O valor total não pode ser menor que o principal.',
          },
        );
      });
      return;
    }

    final count = int.tryParse(_installmentCount.text.trim()) ?? 0;
    if (count < 1 || count > 1200) {
      setState(() {
        _error = const ApiException(
          'Número de parcelas deve estar entre 1 e 1200.',
          status: 422,
          fieldErrors: {'installment_count': 'Número de parcelas inválido.'},
        );
      });
      return;
    }

    if (_recordDisbursement && _disbursementAccountId == null) {
      setState(() {
        _error = const ApiException(
          'Selecione a conta para o desembolso.',
          status: 422,
          fieldErrors: {'disbursement_account_id': 'Selecione uma conta.'},
        );
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final key = 'loan-${DateTime.now().microsecondsSinceEpoch}';

    try {
      await context.read<LoansRepository>().create(
        widget.space.id,
        kind: _kind,
        title: _title.text.trim(),
        counterparty: _counterparty.text.trim(),
        principal: principal,
        total: total,
        installmentCount: count,
        firstDueDate: toApiDate(_firstDueDate),
        disbursementAccountId: _recordDisbursement
            ? _disbursementAccountId
            : null,
        disbursedAt: _recordDisbursement ? toApiDate(_disbursedAt) : null,
        notes: _notes.text.trim().isNotEmpty ? _notes.text.trim() : null,
        idempotencyKey: key,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Empréstimo registrado com sucesso!')),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Novo Empréstimo')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _error!.message,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'taken',
                        label: Text('Tomado (Dívida)'),
                        icon: Icon(Icons.arrow_downward),
                      ),
                      ButtonSegment(
                        value: 'granted',
                        label: Text('Concedido (A Receber)'),
                        icon: Icon(Icons.arrow_upward),
                      ),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (val) {
                      setState(() => _kind = val.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _title,
                    inputFormatters: const [UpperCaseTextFormatter()],
                    decoration: InputDecoration(
                      labelText: 'Descrição / Finalidade',
                      hintText: _kind == 'taken'
                          ? 'Ex: Capital de giro, Carro'
                          : 'Ex: Empréstimo João',
                      border: const OutlineInputBorder(),
                      errorText: _error?.fieldErrors['title'],
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Informe uma descrição.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _counterparty,
                    inputFormatters: const [UpperCaseTextFormatter()],
                    decoration: InputDecoration(
                      labelText: _kind == 'taken'
                          ? 'Credor (Instituição / Pessoa)'
                          : 'Devedor (Beneficiário)',
                      hintText: _kind == 'taken'
                          ? 'Ex: Banco Itaú, Caixa'
                          : 'Ex: Carlos Silva',
                      border: const OutlineInputBorder(),
                      errorText: _error?.fieldErrors['counterparty'],
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Informe o credor/devedor.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _principal,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [MoneyInputFormatter()],
                          decoration: InputDecoration(
                            labelText: 'Valor Principal',
                            prefixText: 'R\$ ',
                            border: const OutlineInputBorder(),
                            errorText: _error?.fieldErrors['principal'],
                          ),
                          validator: (v) {
                            final m = Money.fromInput(v ?? '');
                            return (m == null || m.cents <= 0)
                                ? 'Informe o principal.'
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _total,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [MoneyInputFormatter()],
                          decoration: InputDecoration(
                            labelText: 'Total com Juros',
                            prefixText: 'R\$ ',
                            border: const OutlineInputBorder(),
                            errorText: _error?.fieldErrors['total'],
                          ),
                          validator: (v) {
                            final m = Money.fromInput(v ?? '');
                            return (m == null || m.cents <= 0)
                                ? 'Informe o total.'
                                : null;
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_interestPreview != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _interestPreview!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color:
                            _parsedTotal != null &&
                                _parsedPrincipal != null &&
                                _parsedTotal!.cents < _parsedPrincipal!.cents
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _installmentCount,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Nº de Parcelas',
                            border: const OutlineInputBorder(),
                            errorText: _error?.fieldErrors['installment_count'],
                          ),
                          validator: (v) {
                            final count = int.tryParse(v?.trim() ?? '');
                            if (count == null || count < 1 || count > 1200) {
                              return '1 a 1200 parcelas.';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DateField(
                          label: '1º Vencimento',
                          value: _firstDueDate,
                          onChanged: (d) => setState(() => _firstDueDate = d),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.4,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Registrar movimentação na conta agora',
                            ),
                            subtitle: Text(
                              _kind == 'taken'
                                  ? 'Credita o valor principal na conta bancária'
                                  : 'Debita o valor principal da conta bancária',
                              style: const TextStyle(fontSize: 12),
                            ),
                            value: _recordDisbursement,
                            onChanged: (val) {
                              setState(() => _recordDisbursement = val);
                            },
                          ),
                          if (_recordDisbursement) ...[
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int>(
                              isExpanded: true,
                              initialValue: _disbursementAccountId,
                              decoration: InputDecoration(
                                labelText: 'Conta do Desembolso',
                                border: const OutlineInputBorder(),
                                errorText: _error
                                    ?.fieldErrors['disbursement_account_id'],
                              ),
                              items: _accounts
                                  .map(
                                    (a) => DropdownMenuItem(
                                      value: a.id,
                                      child: Text(
                                        '${toFinancialUpper(a.name)} (${a.balance.brl})',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _disbursementAccountId = val),
                            ),
                            const SizedBox(height: 12),
                            DateField(
                              label: 'Data do Desembolso',
                              value: _disbursedAt,
                              onChanged: (d) =>
                                  setState(() => _disbursedAt = d),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _notes,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Observações (Opcional)',
                      border: const OutlineInputBorder(),
                      errorText: _error?.fieldErrors['notes'],
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const ValueKey('loan_submit_button'),
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Confirmar e Cadastrar'),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}
