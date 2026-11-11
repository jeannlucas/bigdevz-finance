import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../core/text_formatters.dart';
import '../../ui/app_tokens.dart';
import '../../ui/widgets.dart';
import '../accounts/account.dart';
import '../accounts/accounts_repository.dart';
import '../auth/auth_models.dart';
import 'ofx_models.dart';
import 'ofx_repository.dart';

class OfxScreen extends StatefulWidget {
  const OfxScreen({super.key, required this.space, this.repository});

  final Space space;
  final OfxRepository? repository;

  @override
  State<OfxScreen> createState() => _OfxScreenState();
}

class _OfxScreenState extends State<OfxScreen> {
  late final OfxRepository _repo =
      widget.repository ?? OfxRepository(context.read<ApiClient>());

  final TextEditingController _contentController = TextEditingController();
  int? _selectedAccountId;
  List<Account> _accounts = [];

  bool _loadingAccounts = true;
  bool _parsing = false;
  bool _submitting = false;
  String? _errorMessage;
  OfxParseResult? _parseResult;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    try {
      final accountsRepo = context.read<AccountsRepository?>();
      if (accountsRepo != null) {
        final list = await accountsRepo.list(widget.space.id);
        if (mounted) {
          setState(() {
            _accounts = list.where((a) => !a.isArchived).toList();
            if (_accounts.isNotEmpty) {
              _selectedAccountId = _accounts.first.id;
            }
            _loadingAccounts = false;
          });
        }
      } else {
        if (mounted) setState(() => _loadingAccounts = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAccounts = false);
    }
  }

  Future<void> _processOfx() async {
    final text = _contentController.text.trim();
    if (_selectedAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione uma conta bancária para conciliar.'),
        ),
      );
      return;
    }
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cole ou carregue o conteúdo do arquivo OFX.'),
        ),
      );
      return;
    }

    setState(() {
      _parsing = true;
      _errorMessage = null;
      _parseResult = null;
    });

    try {
      final result = await _repo.parseOfx(
        spaceId: widget.space.id,
        accountId: _selectedAccountId!,
        ofxContent: text,
      );

      // Preenche ação inicial sugerida para cada item não conciliado
      for (final tx in result.transactions) {
        if (!tx.alreadyReconciled) {
          if (tx.suggestedMatch != null) {
            tx.selectedAction = tx.suggestedMatch!.type == 'payable'
                ? 'match_payable'
                : 'match_installment';
          } else {
            tx.selectedAction = 'new_movement';
          }
        }
      }

      if (mounted) {
        setState(() {
          _parseResult = result;
          _parsing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e is ApiException
              ? e.message
              : 'Falha ao processar arquivo OFX.';
          _parsing = false;
        });
      }
    }
  }

  Future<void> _confirmReconciliation() async {
    if (_parseResult == null || _selectedAccountId == null) return;

    final toReconcile = _parseResult!.transactions
        .where((tx) => !tx.alreadyReconciled && tx.selectedAction != null)
        .map((tx) {
          return {
            'fitid': tx.fitid,
            'action': tx.selectedAction,
            'amount_cents': tx.amountCents,
            'posted_at': tx.postedAt,
            'memo': tx.memo,
            'payable_id': tx.selectedAction == 'match_payable'
                ? tx.suggestedMatch?.id
                : null,
            'installment_id': tx.selectedAction == 'match_installment'
                ? tx.suggestedMatch?.id
                : null,
          };
        })
        .toList();

    if (toReconcile.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhuma transação pendente selecionada para conciliar.',
          ),
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final res = await _repo.reconcile(
        spaceId: widget.space.id,
        accountId: _selectedAccountId!,
        transactions: toReconcile,
      );

      if (mounted) {
        final reconciled = res['reconciled_count'] ?? 0;
        final ignored = res['ignored_count'] ?? 0;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0F8A5F),
            content: Text(
              'Conciliação finalizada! $reconciled lançamentos conciliados e $ignored ignorados.',
            ),
          ),
        );

        setState(() {
          _submitting = false;
          _parseResult = null;
          _contentController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTokens.expense,
            content: Text(
              e is ApiException ? e.message : 'Falha ao confirmar conciliação.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = widget.space.isPf
        ? const Color(0xFF1E5BB8)
        : const Color(0xFF0F8A5F);

    return Scaffold(
      appBar: AppBar(title: const Text('Conciliação Bancária OFX')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(AppTokens.p16),
            children: [
              SpaceBadge(widget.space, prefix: 'Conciliação no espaço'),
              const SizedBox(height: 16),

              // Card de Instruções e Importação
              _buildImportCard(theme, primaryColor),
              const SizedBox(height: 20),

              if (_parsing)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorMessage != null)
                _buildErrorBanner(theme)
              else if (_parseResult != null)
                _buildPreviewSection(theme, primaryColor),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _parseResult != null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.p16),
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _confirmReconciliation,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F8A5F),
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.r12),
                    ),
                  ),
                  icon: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: Text(
                    _submitting
                        ? 'Gravando conciliação...'
                        : 'Confirmar Conciliação Manual',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildImportCard(ThemeData theme, Color primaryColor) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.r12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.p16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.file_upload_outlined, color: primaryColor),
                const SizedBox(width: 8),
                Text(
                  'Importação Manual de Extrato OFX',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Importe arquivos .ofx exportados do seu banco para conciliar movimentações com contas a pagar e a receber. Nenhuma conexão bancária externa é exigida.',
              style: TextStyle(color: AppTokens.neutral, fontSize: 13),
            ),
            const SizedBox(height: 16),

            // Dropdown de Conta Bancária
            if (_loadingAccounts)
              const LinearProgressIndicator()
            else if (_accounts.isEmpty)
              const Text(
                'Nenhuma conta ativa disponível neste espaço.',
                style: TextStyle(color: AppTokens.expense),
              )
            else
              DropdownButtonFormField<int>(
                initialValue: _selectedAccountId,
                decoration: InputDecoration(
                  labelText: 'Conta Bancária de Destino',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTokens.r8),
                  ),
                ),
                items: [
                  for (final acc in _accounts)
                    DropdownMenuItem(
                      value: acc.id,
                      child: Text(toFinancialUpper(acc.name)),
                    ),
                ],
                onChanged: (val) => setState(() => _selectedAccountId = val),
              ),
            const SizedBox(height: 16),

            // Textarea para conteúdo OFX
            TextFormField(
              key: const ValueKey('ofx-input'),
              controller: _contentController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Conteúdo ou texto do arquivo .OFX',
                hintText: 'Cole o conteúdo do seu arquivo .ofx baixado do banco aqui...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTokens.r8),
                ),
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: _parsing ? null : _processOfx,
                icon: const Icon(Icons.analytics_outlined, size: 20),
                label: const Text(
                  'Analisar Extrato OFX',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewSection(ThemeData theme, Color primaryColor) {
    final res = _parseResult!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Métricas da prévia
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Transações Encontradas (${res.transactions.length})',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (res.alreadyReconciledCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppTokens.neutral.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${res.alreadyReconciledCount} já conciliadas',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.neutral,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Lista de transações
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: res.transactions.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final tx = res.transactions[index];
            final isCredit = tx.type == 'credit';

            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.r12),
                side: BorderSide(
                  color: tx.alreadyReconciled
                      ? theme.colorScheme.outlineVariant.withValues(alpha: 0.3)
                      : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.p14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Ícone Crédito / Débito
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                (isCredit
                                        ? AppTokens.income
                                        : AppTokens.expense)
                                    .withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isCredit
                                ? Icons.arrow_downward_rounded
                                : Icons.arrow_upward_rounded,
                            size: 18,
                            color: isCredit
                                ? AppTokens.income
                                : AppTokens.expense,
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Memo e Data
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tx.memo.isNotEmpty
                                    ? tx.memo
                                    : 'Lançamento bancário',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Data: ${formatDateBr(tx.postedAt)} · FITID: ${tx.fitid}',
                                style: const TextStyle(
                                  color: AppTokens.neutral,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Valor
                        Text(
                          '${isCredit ? '+' : '-'}${tx.amount.brl}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: isCredit
                                ? AppTokens.income
                                : AppTokens.expense,
                          ),
                        ),
                      ],
                    ),

                    if (tx.alreadyReconciled) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTokens.neutral.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppTokens.r8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_outline_rounded,
                              size: 14,
                              color: AppTokens.neutral,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Transação já conciliada anteriormente (Deduplicada)',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTokens.neutral,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 10),
                      const Divider(height: 1),
                      const SizedBox(height: 10),

                      // Sugestão de correspondência automática
                      if (tx.suggestedMatch != null) ...[
                        Container(
                          padding: const EdgeInsets.all(AppTokens.p12),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F8A5F)
                                .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(AppTokens.r8),
                            border: Border.all(
                              color: const Color(0xFF0F8A5F)
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.auto_awesome_rounded,
                                size: 16,
                                color: Color(0xFF0F8A5F),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Correspondência sugerida: ${toFinancialUpper(tx.suggestedMatch!.title)} (${tx.suggestedMatch!.amount})',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0F8A5F),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Opções de ação para confirmação humana
                      Row(
                        children: [
                          const Text(
                            'Ação: ',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: tx.selectedAction,
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppTokens.r8,
                                  ),
                                ),
                              ),
                              items: [
                                if (tx.suggestedMatch != null)
                                  DropdownMenuItem(
                                    value: tx.suggestedMatch!.type == 'payable'
                                        ? 'match_payable'
                                        : 'match_installment',
                                    child: Text(
                                      'Conciliar com "${toFinancialUpper(tx.suggestedMatch!.title)}"',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                const DropdownMenuItem(
                                  value: 'new_movement',
                                  child: Text(
                                    'Criar novo lançamento avulso na conta',
                                  ),
                                ),
                                const DropdownMenuItem(
                                  value: 'ignore',
                                  child: Text('Ignorar esta transação'),
                                ),
                              ],
                              onChanged: (val) {
                                setState(() => tx.selectedAction = val);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildErrorBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(AppTokens.p14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppTokens.r12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: theme.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage ?? 'Erro inesperado.',
              style: TextStyle(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
