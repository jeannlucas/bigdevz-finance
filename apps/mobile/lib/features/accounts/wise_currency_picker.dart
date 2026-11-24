import 'package:flutter/material.dart';

const _currencyPresentation = {
  'BRL': ('Real brasileiro', 'br'),
  'AUD': ('Dólar australiano', 'au'),
  'CAD': ('Dólar canadense', 'ca'),
  'CHF': ('Franco suíço', 'ch'),
  'CNY': ('Yuan chinês', 'cn'),
  'EUR': ('Euro', 'eu'),
  'GBP': ('Libra esterlina', 'gb'),
  'HKD': ('Dólar de Hong Kong', 'hk'),
  'JPY': ('Iene japonês', 'jp'),
  'KRW': ('Won sul-coreano', 'kr'),
  'KWD': ('Dinar kuwaitiano', 'kw'),
  'MXN': ('Peso mexicano', 'mx'),
  'NZD': ('Dólar neozelandês', 'nz'),
  'PLN': ('Zlóti polonês', 'pl'),
  'SGD': ('Dólar de Singapura', 'sg'),
  'USD': ('Dólar americano', 'us'),
};

String wiseCurrencyName(String code) => _currencyPresentation[code]?.$1 ?? code;

class WiseCurrencyFlag extends StatelessWidget {
  const WiseCurrencyFlag(this.code, {super.key, this.size = 28});

  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final region = _currencyPresentation[code]?.$2;
    final fallback = Icon(Icons.language, size: size);
    if (region == null) return fallback;
    return ClipOval(
      child: Image.asset(
        'assets/currency-flags/$region.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

class WiseCurrencyPicker extends StatefulWidget {
  const WiseCurrencyPicker({
    super.key,
    required this.codes,
    required this.onSelected,
  });

  final List<String> codes;
  final ValueChanged<String> onSelected;

  @override
  State<WiseCurrencyPicker> createState() => _WiseCurrencyPickerState();
}

class _WiseCurrencyPickerState extends State<WiseCurrencyPicker> {
  String _query = '';

  String _normalize(String value) => value
      .toLowerCase()
      .trim()
      .replaceAll(RegExp('[áàâã]'), 'a')
      .replaceAll(RegExp('[éê]'), 'e')
      .replaceAll('í', 'i')
      .replaceAll(RegExp('[óôõ]'), 'o')
      .replaceAll(RegExp('[úü]'), 'u')
      .replaceAll('ç', 'c');

  @override
  Widget build(BuildContext context) {
    final codes =
        widget.codes
            .where(
              (code) =>
                  _normalize('${wiseCurrencyName(code)} $code')
                      .contains(_query),
            )
            .toList()
          ..sort(
            (a, b) =>
                _normalize(wiseCurrencyName(a))
                    .compareTo(_normalize(wiseCurrencyName(b))),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: 'Nome ou código da moeda',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => _query = _normalize(value)),
        ),
        const SizedBox(height: 8),
        if (codes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Nenhuma moeda encontrada.'),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 272),
            child: ListView.builder(
              key: ValueKey(_query),
              primary: false,
              shrinkWrap: true,
              itemCount: codes.length,
              itemBuilder: (context, index) {
                final code = codes[index];
                return ListTile(
                  minTileHeight: 68,
                  leading: WiseCurrencyFlag(code, size: 32),
                  title: Text(wiseCurrencyName(code)),
                  subtitle: Text(code),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => widget.onSelected(code),
                );
              },
            ),
          ),
      ],
    );
  }
}
