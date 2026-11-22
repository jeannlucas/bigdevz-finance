import 'package:flutter/material.dart';

/// Informações visuais e semânticas padronizadas de um ícone de categoria financeira.
class CategoryIconInfo {
  const CategoryIconInfo({
    required this.id,
    required this.label,
    required this.iconData,
    required this.defaultColorHex,
  });

  /// Identificador estável persistido na API (ex.: 'home', 'bolt')
  final String id;

  /// Nome amigável de exibição em português
  final String label;

  /// Ícone Material nativo do SDK Flutter
  final IconData iconData;

  /// Cor padrão sugerida em formato hexadecimal ('#RRGGBB')
  final String defaultColorHex;

  Color get defaultColor => CategoryStyleCatalog.colorFromHex(defaultColorHex);
}

/// Catálogo centralizado de identidades visuais de categorias financeiras (ícones e cores).
/// Garante que cadastro, lista, extrato, filtros e relatórios usem exatamente a mesma identidade.
class CategoryStyleCatalog {
  CategoryStyleCatalog._();

  static const List<CategoryIconInfo> icons = [
    // 1. Moradia — casa em azul
    CategoryIconInfo(
      id: 'home',
      label: 'Moradia',
      iconData: Icons.home_rounded,
      defaultColorHex: '#1E5BB8',
    ),
    // 2. Energia — raio em âmbar
    CategoryIconInfo(
      id: 'bolt',
      label: 'Energia elétrica',
      iconData: Icons.bolt_rounded,
      defaultColorHex: '#D97706',
    ),
    // 3. Água — gota em ciano
    CategoryIconInfo(
      id: 'water_drop',
      label: 'Água e saneamento',
      iconData: Icons.water_drop_rounded,
      defaultColorHex: '#06B6D4',
    ),
    // 4. Mercado — carrinho em verde
    CategoryIconInfo(
      id: 'shopping_cart',
      label: 'Mercado e compras',
      iconData: Icons.shopping_cart_rounded,
      defaultColorHex: '#10B981',
    ),
    // 5. Alimentação fora de casa — talheres em laranja
    CategoryIconInfo(
      id: 'restaurant',
      label: 'Alimentação fora de casa',
      iconData: Icons.restaurant_rounded,
      defaultColorHex: '#EA580C',
    ),
    // 6. Transporte — veículo em índigo
    CategoryIconInfo(
      id: 'directions_car',
      label: 'Transporte e veículos',
      iconData: Icons.directions_car_rounded,
      defaultColorHex: '#4F46E5',
    ),
    // 7. Saúde — símbolo médico em turquesa
    CategoryIconInfo(
      id: 'medical_services',
      label: 'Saúde e cuidados',
      iconData: Icons.medical_services_rounded,
      defaultColorHex: '#0D9488',
    ),
    // 8. Folha de pagamento — pessoas em violeta
    CategoryIconInfo(
      id: 'groups',
      label: 'Folha de pagamento e equipe',
      iconData: Icons.groups_rounded,
      defaultColorHex: '#7C3AED',
    ),
    // 9. Tributos — documento em ocre
    CategoryIconInfo(
      id: 'description',
      label: 'Tributos e impostos',
      iconData: Icons.description_rounded,
      defaultColorHex: '#B45309',
    ),
    // 10. Software e assinaturas — monitor em azul-petróleo
    CategoryIconInfo(
      id: 'computer',
      label: 'Software e assinaturas',
      iconData: Icons.computer_rounded,
      defaultColorHex: '#0891B2',
    ),
    // Ícones complementares essenciais
    CategoryIconInfo(
      id: 'work',
      label: 'Trabalho e serviços',
      iconData: Icons.work_rounded,
      defaultColorHex: '#2563EB',
    ),
    CategoryIconInfo(
      id: 'trending_up',
      label: 'Investimentos',
      iconData: Icons.trending_up_rounded,
      defaultColorHex: '#059669',
    ),
    CategoryIconInfo(
      id: 'savings',
      label: 'Poupança e reservas',
      iconData: Icons.savings_rounded,
      defaultColorHex: '#10B981',
    ),
    CategoryIconInfo(
      id: 'credit_card',
      label: 'Cartão de crédito',
      iconData: Icons.credit_card_rounded,
      defaultColorHex: '#6366F1',
    ),
    CategoryIconInfo(
      id: 'school',
      label: 'Educação e cursos',
      iconData: Icons.school_rounded,
      defaultColorHex: '#8B5CF6',
    ),
    CategoryIconInfo(
      id: 'pets',
      label: 'Animais de estimação',
      iconData: Icons.pets_rounded,
      defaultColorHex: '#F59E0B',
    ),
    CategoryIconInfo(
      id: 'local_gas_station',
      label: 'Combustível',
      iconData: Icons.local_gas_station_rounded,
      defaultColorHex: '#EF4444',
    ),
    CategoryIconInfo(
      id: 'fitness_center',
      label: 'Academia e esportes',
      iconData: Icons.fitness_center_rounded,
      defaultColorHex: '#EC4899',
    ),
    CategoryIconInfo(
      id: 'receipt',
      label: 'Contas e faturas',
      iconData: Icons.receipt_long_rounded,
      defaultColorHex: '#64748B',
    ),
    CategoryIconInfo(
      id: 'category',
      label: 'Outros / Geral',
      iconData: Icons.category_rounded,
      defaultColorHex: '#475569',
    ),
  ];

  /// Cores predefinidas para personalização na paleta.
  static const List<String> presetColors = [
    '#1E5BB8', // Azul Moradia
    '#D97706', // Âmbar Energia
    '#06B6D4', // Ciano Água
    '#10B981', // Verde Mercado
    '#EA580C', // Laranja Restaurante
    '#4F46E5', // Índigo Transporte
    '#0D9488', // Turquesa Saúde
    '#7C3AED', // Violeta Folha
    '#B45309', // Ocre Tributos
    '#0891B2', // Azul-petróleo Software
    '#EF4444', // Vermelho vivo
    '#EC4899', // Rosa
    '#64748B', // Ardósia
  ];

  /// Encontra o ícone pelo identificador estável, com fallback seguro para desconhecidos.
  static IconData getIcon(String? iconId) {
    if (iconId == null || iconId.isEmpty) return Icons.category_rounded;
    for (final info in icons) {
      if (info.id == iconId) return info.iconData;
    }
    // Suporte legado
    return switch (iconId) {
      'monetization_on' => Icons.monetization_on_rounded,
      'health_and_safety' => Icons.health_and_safety_rounded,
      'local_activity' => Icons.local_activity_rounded,
      'business_center' => Icons.business_center_rounded,
      'group' => Icons.group_rounded,
      'local_shipping' => Icons.local_shipping_rounded,
      'account_balance' => Icons.account_balance_rounded,
      'cloud' => Icons.cloud_rounded,
      'campaign' => Icons.campaign_rounded,
      'palette' => Icons.palette_rounded,
      'receipt_long' => Icons.receipt_long_rounded,
      'add_circle' => Icons.add_circle_outline_rounded,
      'more_horiz' => Icons.more_horiz_rounded,
      'attach_money' => Icons.attach_money_rounded,
      'payments' => Icons.payments_rounded,
      _ => Icons.category_rounded,
    };
  }

  /// Retorna a informação completa do ícone ou fallback.
  static CategoryIconInfo getIconInfo(String? iconId) {
    if (iconId != null) {
      for (final info in icons) {
        if (info.id == iconId) return info;
      }
    }
    return icons.last; // 'category'
  }

  /// Retorna a cor padrão associada a um identificador de ícone.
  static String getDefaultColorHex(String? iconId, {String? type}) {
    if (iconId != null) {
      for (final info in icons) {
        if (info.id == iconId) return info.defaultColorHex;
      }
    }
    return type == 'income' ? '#0F8A5F' : '#1E5BB8';
  }

  /// Converte cor hexadecimal para `Color` com fallback robusto.
  static Color colorFromHex(String? hexString, {bool isIncome = false}) {
    if (hexString == null || hexString.isEmpty) {
      return isIncome ? const Color(0xFF0F8A5F) : const Color(0xFF1E5BB8);
    }
    try {
      final hex = hexString.replaceAll('#', '').trim();
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
      if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    } catch (_) {}
    return isIncome ? const Color(0xFF0F8A5F) : const Color(0xFF1E5BB8);
  }

  /// Ajusta a cor para contraste ideal em fundos claros (ex.: âmbar #D97706 -> mais escuro para texto).
  static Color readableOnLight(Color color) {
    // Se a luminância for alta (ex.: âmbar claro, amarelo), escurece levemente
    if (color.computeLuminance() > 0.45) {
      return HSLColor.fromColor(color).withLightness(0.35).toColor();
    }
    return color;
  }
}
