import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/dates.dart';
import '../../ui/widgets.dart';
import '../auth/session_controller.dart';
import 'account.dart';
import 'accounts_repository.dart';
import 'wise_currency.dart';
import 'wise_currency_picker.dart';

class WiseDashboardCard extends StatelessWidget {
  const WiseDashboardCard({
    super.key,
    required this.accounts,
    required this.obscure,
  });

  final List<Account> accounts;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    final wallets = accounts.where(
      (account) => account.wiseCurrencies.isNotEmpty,
    );
    if (wallets.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saldos em outras moedas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final account in wallets) ...[
              Text(account.name),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final currency in account.wiseCurrencies)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            WiseCurrencyFlag(currency.code, size: 20),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                obscure
                                    ? '${currency.code} ••••'
                                    : currency.label,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class WiseWalletPanel extends StatelessWidget {
  const WiseWalletPanel({
    super.key,
    required this.account,
    required this.spaceId,
    required this.refresh,
  });

  final Account account;
  final int spaceId;
  final Future<void> Function() refresh;

  Future<void> _changed(BuildContext context) async {
    context.read<SessionController>().dataChanged();
    await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<AccountsRepository>();
    final foreign = account.wiseCurrencies;
    final codes = ['BRL', ...foreign.map((row) => row.code)];
    final missing = WiseCurrency.scales.keys
        .where((code) => !codes.contains(code))
        .toList();
    final nonzero = foreign.where((currency) => currency.hasBalance);
    final missingQuotes = nonzero.where((currency) => currency.brlRate == null);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Carteira Wise',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const WiseCurrencyFlag('BRL'),
              title: const Text('Real brasileiro · BRL'),
              trailing: Text(account.balance.brl),
            ),
            for (final currency in foreign)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: WiseCurrencyFlag(currency.code),
                title: Text(currency.label),
                subtitle: Text(
                  currency.quotedOn == null
                      ? 'Sem cotação'
                      : 'Cotação de ${formatDateBr(currency.quotedOn!)}',
                ),
                trailing: account.isArchived
                    ? null
                    : TextButton(
                        onPressed: () async {
                          final saved = await _showEditor(
                            context,
                            _EditKind.quote,
                            [currency.code],
                            (payload, _) => repository.saveWiseQuote(
                              spaceId,
                              account.id,
                              currency.code,
                              payload['brl_rate']! as String,
                              payload['effective_date']! as String,
                            ),
                            fetchMarketRate: () =>
                                repository.fetchWiseMarketRate(
                                  spaceId,
                                  account.id,
                                  currency.code,
                                ),
                          );
                          if (saved && context.mounted) await _changed(context);
                        },
                        child: const Text('Cotação'),
                      ),
              ),
            if (nonzero.isNotEmpty)
              Text(
                missingQuotes.isEmpty
                    ? 'Equivalente estimado: ${WiseCurrency.estimatedBrl(nonzero, account.balance.cents)}'
                    : 'Cotação pendente: ${missingQuotes.map((currency) => currency.code).join(', ')}',
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!account.isArchived && missing.isNotEmpty)
                  FilledButton.tonal(
                    onPressed: () async {
                      final saved = await _showEditor(
                        context,
                        _EditKind.currency,
                        missing,
                        (payload, key) => repository.saveWiseOperation(
                          spaceId,
                          account.id,
                          'currencies',
                          payload,
                          key,
                        ),
                      );
                      if (saved && context.mounted) await _changed(context);
                    },
                    child: const Text('Adicionar moeda'),
                  ),
                if (!account.isArchived && foreign.isNotEmpty)
                  OutlinedButton(
                    onPressed: () async {
                      final saved = await _showEditor(
                        context,
                        _EditKind.conversion,
                        codes,
                        (payload, key) => repository.saveWiseOperation(
                          spaceId,
                          account.id,
                          'conversions',
                          payload,
                          key,
                        ),
                      );
                      if (saved && context.mounted) await _changed(context);
                    },
                    child: const Text('Registrar conversão'),
                  ),
                if (foreign.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      await showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => _WiseHistory(
                          repository: repository,
                          spaceId: spaceId,
                          account: account,
                          onChanged: () => _changed(context),
                        ),
                      );
                    },
                    child: const Text('Histórico de conversões'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _EditKind { currency, conversion, reversal, quote }

typedef _Save = Future<void> Function(Map<String, Object?> payload, String key);
typedef _FetchRate = Future<WiseMarketRate> Function();

Future<bool> _showEditor(
  BuildContext context,
  _EditKind kind,
  List<String> codes,
  _Save save, {
  _FetchRate? fetchMarketRate,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WiseEditor(
        kind: kind,
        codes: codes,
        save: save,
        fetchMarketRate: fetchMarketRate,
      ),
    ) ??
    false;

class _WiseEditor extends StatefulWidget {
  const _WiseEditor({
    required this.kind,
    required this.codes,
    required this.save,
    this.fetchMarketRate,
  });

  final _EditKind kind;
  final List<String> codes;
  final _Save save;
  final _FetchRate? fetchMarketRate;

  @override
  State<_WiseEditor> createState() => _WiseEditorState();
}

class _WiseEditorState extends State<_WiseEditor> {
  final _value = TextEditingController();
  final _received = TextEditingController();
  final _fee = TextEditingController();
  final _random = Random.secure();
  DateTime _date = DateTime.now();
  String? _currency;
  String? _destination;
  String? _feeCurrency;
  String? _error;
  String? _pendingKey;
  Map<String, Object?>? _pending;
  bool _saving = false;
  bool _reviewing = false;
  bool _fetchingRate = false;

  @override
  void dispose() {
    _value.dispose();
    _received.dispose();
    _fee.dispose();
    super.dispose();
  }

  Map<String, Object?>? _prepare() {
    final date = toApiDate(_date);
    switch (widget.kind) {
      case _EditKind.currency:
        final code = _currency;
        if (code == null) return null;
        final value = _value.text.trim();
        final opening = value.isEmpty
            ? null
            : WiseCurrency.normalize(code, value);
        if (opening == null && value.isNotEmpty) return null;
        return {'currency': code, 'opening_balance': ?opening};
      case _EditKind.conversion:
        final source = _currency;
        final destination = _destination;
        final feeCurrency = _feeCurrency;
        if (source == null || destination == null || source == destination) {
          return null;
        }
        final debit = WiseCurrency.normalize(source, _value.text);
        final credit = WiseCurrency.normalize(destination, _received.text);
        if (debit == null || credit == null) return null;
        final hasFee = _fee.text.trim().isNotEmpty;
        final fee = feeCurrency == null
            ? null
            : WiseCurrency.normalize(feeCurrency, _fee.text);
        if (hasFee && fee == null) return null;
        return {
          'source': source,
          'destination': destination,
          'debited': debit,
          'credited': credit,
          'effective_date': date,
          if (hasFee) ...{'fee': fee, 'fee_currency': feeCurrency},
        };
      case _EditKind.reversal:
        return {'effective_date': date};
      case _EditKind.quote:
        final rate = _value.text.trim().replaceFirst(',', '.');
        if (!RegExp(r'^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,8})?$')
            .hasMatch(rate)) {
          return null;
        }
        return {'brl_rate': rate, 'effective_date': date};
    }
  }

  void _review() {
    final payload = _prepare();
    if (payload == null) {
      setState(
        () => _error = 'Confira as moedas e as casas decimais dos valores.',
      );
      return;
    }
    setState(() {
      _pending = payload;
      _pendingKey = List.generate(
        4,
        (_) => _random.nextInt(1 << 30).toRadixString(16).padLeft(8, '0'),
      ).join();
      _reviewing = true;
      _error = null;
    });
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(_pending!, _pendingKey!);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _saving = false;
        if (error.rejectionRecorded || widget.kind == _EditKind.quote) {
          _pending = null;
          _reviewing = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final title = switch (kind) {
      _EditKind.currency => 'Adicionar moeda',
      _EditKind.conversion => 'Registrar conversão',
      _EditKind.reversal => 'Estornar conversão',
      _EditKind.quote => 'Cotação de ${widget.codes.single}',
    };
    return PopScope(
      canPop: !_saving && !_fetchingRate,
      child: AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_reviewing)
                  Text(switch (kind) {
                    _EditKind.currency =>
                      '${_pending!['currency']} · saldo inicial ${_pending!['opening_balance'] ?? 'zero'}',
                    _EditKind.conversion =>
                      'Debitar ${_pending!['source']} ${_pending!['debited']} e creditar ${_pending!['destination']} ${_pending!['credited']}${_pending!['fee'] == null ? '' : '\nTarifa adicional: ${_pending!['fee_currency']} ${_pending!['fee']}'}',
                    _EditKind.reversal =>
                      'Registrar os movimentos inversos em ${formatDateBr(toApiDate(_date))}.',
                    _EditKind.quote =>
                      '1 ${widget.codes.single} = BRL ${_pending!['brl_rate']}',
                  })
                else ...[
                  if (kind == _EditKind.currency)
                    if (_currency case final code?)
                      ListTile(
                        leading: WiseCurrencyFlag(code),
                        title: Text(wiseCurrencyName(code)),
                        subtitle: Text(code),
                        trailing: const Text('Trocar'),
                        onTap: () => setState(() {
                          _currency = null;
                          _value.clear();
                        }),
                      )
                    else
                      WiseCurrencyPicker(
                        codes: widget.codes,
                        onSelected: (code) => setState(() => _currency = code),
                      ),
                  if (kind == _EditKind.conversion)
                    _selector(
                      'Moeda debitada',
                      _currency,
                      (code) => setState(() => _currency = code),
                    ),
                  if (kind != _EditKind.reversal &&
                      (kind != _EditKind.currency || _currency != null))
                    _amount(_value, switch (kind) {
                      _EditKind.currency => 'Saldo inicial (opcional)',
                      _EditKind.conversion => 'Valor debitado antes da tarifa',
                      _ => 'Reais por unidade de ${widget.codes.single}',
                    }),
                  if (kind == _EditKind.quote &&
                      widget.fetchMarketRate != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        icon: _fetchingRate
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.trending_up, size: 18),
                        label: const Text('Buscar cotação de mercado'),
                        onPressed: _fetchingRate || _saving
                            ? null
                            : () async {
                                setState(() {
                                  _fetchingRate = true;
                                  _error = null;
                                });
                                try {
                                  final marketRate =
                                      await widget.fetchMarketRate!();
                                  if (mounted) {
                                    setState(() {
                                      _value.text = marketRate.rate
                                          .replaceFirst('.', ',');
                                      _date = marketRate.quotedOn;
                                      _fetchingRate = false;
                                    });
                                  }
                                } on ApiException catch (e) {
                                  if (mounted) {
                                    setState(() {
                                      _error = e.message;
                                      _fetchingRate = false;
                                    });
                                  }
                                } catch (_) {
                                  if (mounted) {
                                    setState(() {
                                      _error = 'Cotação de mercado não disponível para esta moeda no momento.';
                                      _fetchingRate = false;
                                    });
                                  }
                                }
                              },
                      ),
                    ),
                  ],
                  if (kind == _EditKind.conversion) ...[
                    _selector(
                      'Moeda creditada',
                      _destination,
                      (code) => setState(() => _destination = code),
                    ),
                    _amount(_received, 'Valor creditado antes da tarifa'),
                    _amount(_fee, 'Tarifa adicional (opcional)'),
                    _selector(
                      'Moeda da tarifa',
                      _feeCurrency,
                      (code) => setState(() => _feeCurrency = code),
                    ),
                  ],
                  if (kind != _EditKind.currency)
                    TextButton.icon(
                      onPressed: () async {
                        final now = DateTime.now();
                        final selected = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(2000),
                          lastDate: now,
                        );
                        if (selected != null && mounted) {
                          setState(() => _date = selected);
                        }
                      },
                      icon: const Icon(Icons.event_outlined),
                      label: Text(formatDateBr(toApiDate(_date))),
                    ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving || _fetchingRate
                ? null
                : () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed:
                _saving ||
                    _fetchingRate ||
                    (kind == _EditKind.currency && _currency == null)
                ? null
                : (_reviewing ? _submit : _review),
            child: Text(
              _saving ? 'Salvando…' : (_reviewing ? 'Confirmar' : 'Revisar'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selector(
    String label,
    String? current,
    ValueChanged<String?> changed,
  ) => DropdownButtonFormField<String>(
    initialValue: current,
    isExpanded: true,
    menuMaxHeight: 320,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final code in widget.codes)
        DropdownMenuItem(
          value: code,
          child: Row(
            children: [
              WiseCurrencyFlag(code, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$code · ${wiseCurrencyName(code)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
    ],
    onChanged: changed,
  );

  Widget _amount(TextEditingController controller, String label) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label),
  );
}

class _WiseHistory extends StatefulWidget {
  const _WiseHistory({
    required this.repository,
    required this.spaceId,
    required this.account,
    required this.onChanged,
  });

  final Future<void> Function() onChanged;
  final AccountsRepository repository;
  final int spaceId;
  final Account account;

  @override
  State<_WiseHistory> createState() => _WiseHistoryState();
}

class _WiseHistoryState extends State<_WiseHistory> {
  int _page = 1;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Histórico de conversões'),
    content: SizedBox(
      width: 480,
      height: 320,
      child: LoadView(
        key: ValueKey(_page),
        load: () => widget.repository.wiseHistory(
          widget.spaceId,
          widget.account.id,
          _page,
        ),
        builder: (context, data, refresh) => ListView(
          children: [
            if (_page == 1 && data.entries.isEmpty)
              const Text('Nenhuma conversão registrada.'),
            for (final event in data.entries)
              ListTile(
                title: Text(
                  event['reverses_id'] != null
                      ? "Estorno da conversão #${event['reverses_id']}"
                      : "${event['details']['source']} ${event['details']['debited']} → ${event['details']['destination']} ${event['details']['credited']}",
                ),
                subtitle: Text(formatDateBr(event['effective_date'] as String)),
                trailing:
                    !widget.account.isArchived &&
                        event['reverses_id'] == null &&
                        event['reversal_exists'] != true
                    ? TextButton(
                        child: const Text('Estornar'),
                        onPressed: () async {
                          final saved = await _showEditor(
                            context,
                            _EditKind.reversal,
                            [],
                            (payload, key) =>
                                widget.repository.saveWiseOperation(
                                  widget.spaceId,
                                  widget.account.id,
                                  "conversions/${event['id']}/reversal",
                                  payload,
                                  key,
                                ),
                          );
                          if (!saved || !mounted) return;
                          await widget.onChanged();
                          if (mounted) await refresh();
                        },
                      )
                    : null,
              ),
            if (_page > 1 || data.hasNext)
              Wrap(
                children: [
                  TextButton(
                    onPressed: _page > 1 ? () => setState(() => _page--) : null,
                    child: const Text('Anterior'),
                  ),
                  TextButton(
                    onPressed: data.hasNext
                        ? () => setState(() => _page++)
                        : null,
                    child: const Text('Próxima'),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Fechar'),
      ),
    ],
  );
}
