import 'package:flutter/material.dart';

/// Informações institucionais e visuais padronizadas de um banco ou instituição de pagamento.
class BankInfo {
  const BankInfo({
    required this.id,
    required this.name,
    required this.code,
    required this.assetPath,
    required this.color,
    this.initialNameSuggestion,
  });

  /// Identificador canônico (ex.: 'nubank', 'itau', 'bb')
  final String id;

  /// Nome amigável de exibição
  final String name;

  /// Código COMPE oficial (ou '000' / '---')
  final String code;

  /// Caminho do ativo de imagem PNG transparente e padronizado (256x256)
  final String assetPath;

  /// Cor principal da identidade visual
  final Color color;

  /// Sugestão de nome para criação rápida de conta
  final String? initialNameSuggestion;

  bool get isCashOrWallet => id == 'dinheiro';
  bool get isOther => id == 'outro';
}

/// Catálogo de bancos brasileiros com logos oficiais padronizados.
class BankCatalog {
  BankCatalog._();

  static const String _basePath = 'assets/banks';

  static const BankInfo nubank = BankInfo(
    id: 'nubank',
    name: 'Nubank',
    code: '260',
    assetPath: '$_basePath/nubank.png',
    color: Color(0xFF820AD1),
  );

  static const BankInfo itau = BankInfo(
    id: 'itau',
    name: 'Itaú',
    code: '341',
    assetPath: '$_basePath/itau.png',
    color: Color(0xFFEC7000),
  );

  static const BankInfo bradesco = BankInfo(
    id: 'bradesco',
    name: 'Bradesco',
    code: '237',
    assetPath: '$_basePath/bradesco.png',
    color: Color(0xFFCC092F),
  );

  static const BankInfo bb = BankInfo(
    id: 'bb',
    name: 'Banco do Brasil',
    code: '001',
    assetPath: '$_basePath/bb.png',
    color: Color(0xFF003882),
  );

  static const BankInfo caixa = BankInfo(
    id: 'caixa',
    name: 'Caixa Econômica',
    code: '104',
    assetPath: '$_basePath/caixa.png',
    color: Color(0xFF005CA9),
  );

  static const BankInfo santander = BankInfo(
    id: 'santander',
    name: 'Santander',
    code: '033',
    assetPath: '$_basePath/santander.png',
    color: Color(0xFFEC0000),
  );

  static const BankInfo inter = BankInfo(
    id: 'inter',
    name: 'Banco Inter',
    code: '077',
    assetPath: '$_basePath/inter.png',
    color: Color(0xFFFF7A00),
  );

  static const BankInfo sicoob = BankInfo(
    id: 'sicoob',
    name: 'Sicoob',
    code: '756',
    assetPath: '$_basePath/sicoob.png',
    color: Color(0xFF003641),
  );

  static const BankInfo sicredi = BankInfo(
    id: 'sicredi',
    name: 'Sicredi',
    code: '748',
    assetPath: '$_basePath/sicredi.png',
    color: Color(0xFF006837),
  );

  static const BankInfo mercadopago = BankInfo(
    id: 'mercadopago',
    name: 'Mercado Pago',
    code: '323',
    assetPath: '$_basePath/mercadopago.png',
    color: Color(0xFF009EE3),
  );

  static const BankInfo c6 = BankInfo(
    id: 'c6',
    name: 'C6 Bank',
    code: '336',
    assetPath: '$_basePath/c6.png',
    color: Color(0xFF242424),
  );

  static const BankInfo btg = BankInfo(
    id: 'btg',
    name: 'BTG Pactual',
    code: '208',
    assetPath: '$_basePath/btg.png',
    color: Color(0xFF0D1E3A),
  );

  static const BankInfo picpay = BankInfo(
    id: 'picpay',
    name: 'PicPay',
    code: '380',
    assetPath: '$_basePath/picpay.png',
    color: Color(0xFF11C76F),
  );

  static const BankInfo pagbank = BankInfo(
    id: 'pagbank',
    name: 'PagBank',
    code: '290',
    assetPath: '$_basePath/pagbank.png',
    color: Color(0xFF00B066),
  );

  static const BankInfo neon = BankInfo(
    id: 'neon',
    name: 'Neon',
    code: '536',
    assetPath: '$_basePath/neon.png',
    color: Color(0xFF00E5FF),
  );

  static const BankInfo stone = BankInfo(
    id: 'stone',
    name: 'Stone',
    code: '197',
    assetPath: '$_basePath/stone.png',
    color: Color(0xFF00A868),
  );

  static const BankInfo dinheiro = BankInfo(
    id: 'dinheiro',
    name: 'Dinheiro em Espécie',
    code: '000',
    assetPath: '$_basePath/dinheiro.png',
    color: Color(0xFF10B981),
    initialNameSuggestion: 'Carteira Física',
  );

  static const BankInfo outro = BankInfo(
    id: 'outro',
    name: 'Outra Instituição',
    code: '---',
    assetPath: '$_basePath/outro.png',
    color: Color(0xFF475569),
  );

  /// Lista completa de instituições catalogadas
  static const List<BankInfo> all = [
    nubank,
    itau,
    bradesco,
    bb,
    caixa,
    santander,
    inter,
    sicoob,
    sicredi,
    mercadopago,
    c6,
    btg,
    picpay,
    pagbank,
    neon,
    stone,
    dinheiro,
    outro,
  ];

  /// Busca instituição pelo id
  static BankInfo? findById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final bank in all) {
      if (bank.id == id) return bank;
    }
    return null;
  }

  /// Identifica automaticamente o banco a partir do nome da conta digitado pelo usuário.
  static BankInfo? findByAccountName(String accountName) {
    final lower = accountName.trim().toLowerCase();
    if (lower.isEmpty) return null;

    // Dinheiro / Carteira
    if (lower.contains('dinheiro') ||
        lower.contains('carteira') ||
        lower.contains('espécie') ||
        lower.contains('especie') ||
        lower.contains('caixa físico') ||
        lower.contains('caixa fisico')) {
      return dinheiro;
    }

    // Nubank / Nu
    if (lower.contains('nubank') ||
        lower == 'nu' ||
        lower.startsWith('nu ') ||
        lower.endsWith(' nu') ||
        lower.contains(' nu ')) {
      return nubank;
    }

    // Itaú
    if (lower.contains('itau') || lower.contains('itaú')) {
      return itau;
    }

    // Bradesco
    if (lower.contains('bradesco')) {
      return bradesco;
    }

    // Banco do Brasil / BB
    if (lower.contains('brasil') ||
        lower == 'bb' ||
        lower.startsWith('bb ') ||
        lower.endsWith(' bb') ||
        lower.contains(' bb ')) {
      return bb;
    }

    // Caixa Econômica / CEF
    if (lower.contains('caixa') || lower.contains('cef')) {
      return caixa;
    }

    // Santander
    if (lower.contains('santander')) {
      return santander;
    }

    // Inter
    if (lower.contains('inter')) {
      return inter;
    }

    // Sicoob
    if (lower.contains('sicoob')) {
      return sicoob;
    }

    // Sicredi
    if (lower.contains('sicredi')) {
      return sicredi;
    }

    // Mercado Pago
    if (lower.contains('mercado pago') || lower.contains('mercadopago')) {
      return mercadopago;
    }

    // C6 Bank
    if (lower.contains('c6')) {
      return c6;
    }

    // BTG Pactual
    if (lower.contains('btg')) {
      return btg;
    }

    // PicPay
    if (lower.contains('picpay') || lower.contains('pic pay')) {
      return picpay;
    }

    // PagBank / PagSeguro
    if (lower.contains('pagbank') ||
        lower.contains('pagseguro') ||
        lower.contains('pag seguro')) {
      return pagbank;
    }

    // Neon
    if (lower.contains('neon')) {
      return neon;
    }

    // Stone
    if (lower.contains('stone')) {
      return stone;
    }

    return null;
  }
}
