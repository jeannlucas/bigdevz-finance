import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/text_formatters.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../../ui/date_field.dart';
import '../accounts/account.dart';
import '../accounts/accounts_repository.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';

/// Abre o fluxo de transferência (Modal Dialog em Desktop / Bottom Sheet em Mobile).
Future<void> showTransferFormModal(
  BuildContext context, {
  required Space space,
  List<Account>? accounts,
  int? initialSourceAccountId,
  int? initialDestinationSpaceId,
}) {
  final isDesktop = MediaQuery.sizeOf(context).width >= 640;
  if (isDesktop) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.r24),
        ),
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 580,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.9,
          ),
          child: TransferFormScreen(
            space: space,
            accounts: accounts,
            initialSourceAccountId: initialSourceAccountId,
            initialDestinationSpaceId: initialDestinationSpaceId,
            asModal: true,
          ),
        ),
      ),
    );
  } else {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTokens.r24),
        ),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.92,
          ),
          child: TransferFormScreen(
            space: space,
            accounts: accounts,
            initialSourceAccountId: initialSourceAccountId,
            initialDestinationSpaceId: initialDestinationSpaceId,
            asModal: true,
          ),
        ),
      ),
    );
  }
}

/// Tela para realização de transferências financeiras entre contas (do mesmo espaço ou entre espaços).
class TransferFormScreen extends StatefulWidget {
  const TransferFormScreen({
    super.key,
    required this.space,
    this.accounts,
    this.initialSourceAccountId,
    this.initialDestinationSpaceId,
    this.asModal = false,
  });

  final Space space;
  final List<Account>? accounts;
  final int? initialSourceAccountId;
  final int? initialDestinationSpaceId;
  final bool asModal;

  @override
  State<TransferFormScreen> createState() => _TransferFormScreenState();
}

class _TransferFormScreenState extends State<TransferFormScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  DateTime _date = DateUtils.dateOnly(DateTime.now());

  late int _sourceSpaceId;
  late int _destinationSpaceId;
  int? _sourceAccountId;
  int? _destinationAccountId;

  final bool _loading = false;
  bool _saving = false;
  bool _reviewing = false;
  ApiException? _error;

  final Map<int, List<Account>> _accountsBySpace = {};
  final Set<int> _loadingSpaces = {};

  @override
  void initState() {
    super.initState();
    // 1. Origem inicial configurada estritamente com o espaço ativo de onde foi aberta
    _sourceSpaceId = widget.space.id;
    _destinationSpaceId = widget.initialDestinationSpaceId ?? widget.space.id;

    // 2. Contas bancárias sem seleção inicial: usuário escolhe conscientemente
    _sourceAccountId = null;
    _destinationAccountId = null;

    if (widget.accounts != null) {
      _accountsBySpace[widget.space.id] = widget.accounts!
          .where((a) => !a.isArchived)
          .toList();
      _ensureValidSelection();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureAccountsLoaded(_sourceSpaceId);
      if (_destinationSpaceId != _sourceSpaceId) {
        _ensureAccountsLoaded(_destinationSpaceId);
      }
    });
  }

  void _ensureValidSelection() {
    final sourceList = _accountsBySpace[_sourceSpaceId] ?? const [];
    if (_sourceAccountId != null &&
        !sourceList.any((a) => a.id == _sourceAccountId)) {
      _sourceAccountId = null;
    }
    final destList = _accountsBySpace[_destinationSpaceId] ?? const [];
    if (_destinationAccountId != null &&
        !destList.any((a) => a.id == _destinationAccountId)) {
      _destinationAccountId = null;
    }
  }

  Future<void> _ensureAccountsLoaded(int spaceId) async {
    if (_accountsBySpace.containsKey(spaceId) ||
        _loadingSpaces.contains(spaceId)) {
      return;
    }

    setState(() => _loadingSpaces.add(spaceId));
    try {
      final list = await context.read<AccountsRepository>().list(spaceId);
      if (!mounted) return;
      setState(() {
        _accountsBySpace[spaceId] = list.where((a) => !a.isArchived).toList();
        _ensureValidSelection();
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loadingSpaces.remove(spaceId));
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _review() {
    if (_saving || !_form.currentState!.validate()) return;

    final parsedAmount = Money.fromInput(_amount.text);
    if (parsedAmount == null || parsedAmount.cents <= 0) {
      setState(() {
        _error = const ApiException(
          'Informe um valor maior que zero.',
          status: 422,
          fieldErrors: {'amount': 'Informe um valor maior que zero.'},
        );
      });
      return;
    }

    setState(() {
      _reviewing = true;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_saving) return;

    final parsedAmount = Money.fromInput(_amount.text);
    if (parsedAmount == null || parsedAmount.cents <= 0) {
      setState(() {
        _error = const ApiException(
          'Informe um valor maior que zero.',
          status: 422,
          fieldErrors: {'amount': 'Informe um valor maior que zero.'},
        );
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final idempotencyKey =
          'transfer-${DateTime.now().microsecondsSinceEpoch}';

      await context.read<AccountsRepository>().transfer(
        _sourceSpaceId,
        destinationSpaceId: _destinationSpaceId,
        sourceAccountId: _sourceAccountId!,
        destinationAccountId: _destinationAccountId!,
        amount: parsedAmount,
        date: toApiDate(_date),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        idempotencyKey: idempotencyKey,
      );

      if (!mounted) return;
      context.read<SessionController>().dataChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _sourceSpaceId != _destinationSpaceId
                ? 'Transferência entre espaços registrada com sucesso.'
                : 'Transferência realizada com sucesso.',
          ),
        ),
      );
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<Space> _availableSpaces() {
    try {
      final session = context.read<SessionController>();
      final spaces = session.spaces.where((s) => s.canMoveMoney).toList();
      if (spaces.isNotEmpty) return spaces;
    } catch (_) {}
    return [widget.space];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fieldErrors = _error?.fieldErrors ?? const {};
    final spaces = _availableSpaces();

    final sourceAccounts = _accountsBySpace[_sourceSpaceId] ?? const [];
    final destinationAccounts =
        _accountsBySpace[_destinationSpaceId] ?? const [];
    final isSourceLoading = _loadingSpaces.contains(_sourceSpaceId);
    final isDestLoading = _loadingSpaces.contains(_destinationSpaceId);

    final totalAccountsAcrossSpaces = _accountsBySpace.values
        .expand((list) => list)
        .map((a) => a.id)
        .toSet()
        .length;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transferir')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_accountsBySpace.containsKey(_sourceSpaceId) &&
        _accountsBySpace.containsKey(_destinationSpaceId) &&
        totalAccountsAcrossSpaces < 2 &&
        spaces.length <= 1) {
      final insufficientContent = Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: AppIcon(AppIcons.alert, size: 48)),
            const SizedBox(height: 16),
            Text(
              'Contas insuficientes',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'É necessário possuir ao menos duas contas ativas para realizar uma transferência.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Voltar'),
            ),
          ],
        ),
      );

      return widget.asModal
          ? insufficientContent
          : Scaffold(
              appBar: AppBar(title: const Text('Transferir')),
              body: insufficientContent,
            );
    }

    final isCrossSpace = _sourceSpaceId != _destinationSpaceId;
    final sourceSpace = spaces.firstWhere(
      (s) => s.id == _sourceSpaceId,
      orElse: () => widget.space,
    );
    final destSpace = spaces.firstWhere(
      (s) => s.id == _destinationSpaceId,
      orElse: () => widget.space,
    );

    final formContent = _reviewing
        ? _buildReviewContent(context, sourceSpace, destSpace)
        : Form(
            key: _form,
            child: ListView(
              shrinkWrap: widget.asModal,
              padding: const EdgeInsets.all(AppTokens.p20),
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
                  const SizedBox(height: 12),
                ],

                // Aviso Explícito: Não executa Pix bancário externo
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(AppTokens.r12),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.4,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Registro contábil de movimentação: não executa Pix no banco.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Badge destacando transferência entre espaços
                if (isCrossSpace) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.35,
                      ),
                      borderRadius: BorderRadius.circular(AppTokens.r8),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.sync_alt_rounded,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Entre espaços: ${sourceSpace.label} → ${destSpace.label}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                if (spaces.length > 1) ...[
                  DropdownButtonFormField<int>(
                    key: const ValueKey('transfer_source_space'),
                    initialValue: _sourceSpaceId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Espaço de origem',
                      prefixIcon: Icon(Icons.domain_rounded, size: 20),
                    ),
                    items: spaces
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(s.label),
                          ),
                        )
                        .toList(),
                    onChanged: (id) {
                      if (id == null || id == _sourceSpaceId) return;
                      setState(() {
                        _sourceSpaceId = id;
                        _sourceAccountId =
                            null; // Limpa a conta de origem ao alterar o espaço
                      });
                      _ensureAccountsLoaded(id);
                    },
                  ),
                  const SizedBox(height: 12),
                ],

                DropdownButtonFormField<int>(
                  key: const ValueKey('transfer_source_account'),
                  initialValue: _sourceAccountId,
                  isExpanded: true,
                  hint: isSourceLoading
                      ? const Text('Carregando contas...')
                      : const Text('Selecione uma conta'),
                  decoration: InputDecoration(
                    labelText: 'Conta de origem',
                    errorText: fieldErrors['source_account_id'],
                    prefixIcon: const Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 20,
                    ),
                  ),
                  items: sourceAccounts
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
                  onChanged: isSourceLoading
                      ? null
                      : (id) => setState(() => _sourceAccountId = id),
                  validator: (v) =>
                      v == null ? 'Selecione a conta de origem' : null,
                ),
                const SizedBox(height: 12),

                if (spaces.length > 1) ...[
                  DropdownButtonFormField<int>(
                    key: const ValueKey('transfer_destination_space'),
                    initialValue: _destinationSpaceId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Espaço de destino',
                      prefixIcon: Icon(Icons.domain_rounded, size: 20),
                    ),
                    items: spaces
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(s.label),
                          ),
                        )
                        .toList(),
                    onChanged: (id) {
                      if (id == null || id == _destinationSpaceId) return;
                      setState(() {
                        _destinationSpaceId = id;
                        _destinationAccountId = null; // Limpa a conta de destino ao alterar o espaço
                      });
                      _ensureAccountsLoaded(id);
                    },
                  ),
                  const SizedBox(height: 12),
                ],

                DropdownButtonFormField<int>(
                  key: const ValueKey('transfer_destination_account'),
                  initialValue: _destinationAccountId,
                  isExpanded: true,
                  hint: isDestLoading
                      ? const Text('Carregando contas...')
                      : const Text('Selecione uma conta'),
                  decoration: InputDecoration(
                    labelText: 'Conta de destino',
                    errorText: fieldErrors['destination_account_id'],
                    prefixIcon: const Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 20,
                    ),
                  ),
                  items: destinationAccounts
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
                  onChanged: isDestLoading
                      ? null
                      : (id) => setState(() => _destinationAccountId = id),
                  validator: (v) {
                    if (v == null) return 'Selecione a conta de destino';
                    if (_sourceSpaceId == _destinationSpaceId &&
                        v == _sourceAccountId) {
                      return 'A conta de destino deve ser diferente da origem';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Valor
                TextFormField(
                  key: const ValueKey('transfer_amount'),
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [MoneyInputFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Valor (R\$)',
                    hintText: '0,00',
                    errorText: fieldErrors['amount'],
                    prefixIcon: const Icon(
                      Icons.attach_money_rounded,
                      size: 20,
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Informe o valor';
                    final parsed = Money.fromInput(v);
                    if (parsed == null || parsed.cents <= 0) {
                      return 'Informe um valor maior que zero';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Data
                DateField(
                  key: const ValueKey('transfer_date'),
                  label: 'Data da transferência',
                  value: _date,
                  onChanged: (d) => setState(() => _date = d),
                  errorText: fieldErrors['transferred_at'],
                ),
                const SizedBox(height: 12),

                // Observações
                TextFormField(
                  key: const ValueKey('transfer_notes'),
                  controller: _notes,
                  maxLines: 1,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: 'Finalidade / Observação (opcional)',
                    hintText: 'Ex: Reembolso de despesa, aporte ou Pix',
                    errorText: fieldErrors['notes'],
                    prefixIcon: const Icon(Icons.notes_rounded, size: 20),
                  ),
                ),
                const SizedBox(height: 16),

                FilledButton(
                  key: const ValueKey('transfer_submit_button'),
                  onPressed: _saving ? null : _review,
                  child: const Text('Revisar transferência'),
                ),
              ],
            ),
          );

    if (widget.asModal) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.p20,
              AppTokens.p16,
              AppTokens.p12,
              AppTokens.p12,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTokens.r12),
                  ),
                  child: Center(
                    child: AppIcon(
                      _reviewing ? AppIcons.check : AppIcons.transfer,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _reviewing
                            ? 'Revisar transferência'
                            : 'Transferir entre contas',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _reviewing
                            ? 'Confira a origem, o destino e o valor antes de confirmar'
                            : (isCrossSpace
                                  ? 'Movimentação entre espaços distintos'
                                  : 'Movimentação financeira interna no espaço'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    if (_reviewing) {
                      setState(() => _reviewing = false);
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                  tooltip: _reviewing ? 'Voltar ao formulário' : 'Fechar',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(child: formContent),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _reviewing ? 'Revisar transferência' : 'Transferir entre contas',
        ),
        leading: _reviewing
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _reviewing = false),
                tooltip: 'Voltar ao formulário',
              )
            : null,
      ),
      body: formContent,
    );
  }

  Widget _buildReviewContent(
    BuildContext context,
    Space sourceSpace,
    Space destSpace,
  ) {
    final theme = Theme.of(context);
    final sourceAccount = (_accountsBySpace[_sourceSpaceId] ?? const [])
        .where((a) => a.id == _sourceAccountId)
        .firstOrNull;
    final destAccount = (_accountsBySpace[_destinationSpaceId] ?? const [])
        .where((a) => a.id == _destinationAccountId)
        .firstOrNull;

    final parsedAmount = Money.fromInput(_amount.text) ?? const Money(0);
    final isCrossSpace = _sourceSpaceId != _destinationSpaceId;

    return ListView(
      shrinkWrap: widget.asModal,
      padding: const EdgeInsets.all(AppTokens.p20),
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
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Badge informativo
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isCrossSpace
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
            borderRadius: BorderRadius.circular(AppTokens.r8),
            border: Border.all(
              color: isCrossSpace
                  ? theme.colorScheme.primary.withValues(alpha: 0.3)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isCrossSpace
                    ? Icons.sync_alt_rounded
                    : Icons.swap_horiz_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isCrossSpace
                      ? 'Entre espaços distintos: ${sourceSpace.label} → ${destSpace.label}'
                      : 'Transferência interna: ${sourceSpace.label}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isCrossSpace
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Card de Origem
        _buildReviewAccountCard(
          context,
          role: 'ORIGEM (SAÍDA)',
          space: sourceSpace,
          account: sourceAccount,
          isDebit: true,
          amount: parsedAmount,
        ),
        const SizedBox(height: 8),

        Center(
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.arrow_downward_rounded,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Card de Destino
        _buildReviewAccountCard(
          context,
          role: 'DESTINO (ENTRADA)',
          space: destSpace,
          account: destAccount,
          isDebit: false,
          amount: parsedAmount,
        ),
        const SizedBox(height: 14),

        // Card do Valor e Detalhes
        Container(
          padding: const EdgeInsets.all(AppTokens.p16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.35,
            ),
            borderRadius: BorderRadius.circular(AppTokens.r12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Valor a ser movimentado',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                parsedAmount.brl,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Data contábil:',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    formatDateBr(toApiDate(_date)),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (_notes.text.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Finalidade / Observação:',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _notes.text.trim(),
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Aviso Explícito do Pix
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
            borderRadius: BorderRadius.circular(AppTokens.r12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Registro contábil de movimentação: não executa Pix no banco.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('transfer_back_button'),
                onPressed: _saving
                    ? null
                    : () => setState(() => _reviewing = false),
                child: const Text('Voltar e editar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const ValueKey('transfer_confirm_button'),
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirmar transferência'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReviewAccountCard(
    BuildContext context, {
    required String role,
    required Space space,
    required Account? account,
    required bool isDebit,
    required Money amount,
  }) {
    final theme = Theme.of(context);
    final balanceBefore = account?.balance ?? const Money(0);
    final balanceAfter = Money(
      isDebit
          ? balanceBefore.cents - amount.cents
          : balanceBefore.cents + amount.cents,
    );

    return Container(
      padding: const EdgeInsets.all(AppTokens.p14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppTokens.r12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isDebit
                      ? theme.colorScheme.errorContainer.withValues(alpha: 0.5)
                      : theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.5,
                        ),
                  borderRadius: BorderRadius.circular(AppTokens.r8),
                ),
                child: Text(
                  role,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: isDebit
                        ? theme.colorScheme.onErrorContainer
                        : theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Espaço: ${space.label}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            account != null
                ? toFinancialUpper(account.name)
                : 'Conta não selecionada',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Saldo disponível: ${balanceBefore.brl} → ${balanceAfter.brl}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
