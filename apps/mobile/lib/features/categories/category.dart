import 'package:flutter/material.dart';

/// Categoria financeira para classificação de receitas e despesas.
class Category {
  const Category({
    required this.id,
    required this.spaceId,
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
    this.isDefault = false,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as int,
      spaceId: json['space_id'] as int? ?? 0,
      name: json['name'] as String,
      type: json['type'] as String,
      icon: json['icon'] as String? ?? 'category',
      color: json['color'] as String? ?? '#1E5BB8',
      isDefault: json['is_default'] as bool? ?? false,
    );
  }

  final int id;
  final int spaceId;
  final String name;
  final String type; // 'income' | 'expense'
  final String icon;
  final String color;
  final bool isDefault;

  bool get isIncome => type == 'income';
  bool get isExpense => type == 'expense';

  Color get colorValue => colorHexToColor(color, isIncome: isIncome);

  static Color colorHexToColor(String colorHex, {bool isIncome = false}) {
    try {
      final hex = colorHex.replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
      if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    } catch (_) {}
    return isIncome ? const Color(0xFF0F8A5F) : const Color(0xFFE57373);
  }

  IconData get iconData => iconToMaterial(icon);

  static IconData iconToMaterial(String iconName) {
    return switch (iconName) {
      'work' => Icons.work_rounded,
      'trending_up' => Icons.trending_up_rounded,
      'monetization_on' => Icons.monetization_on_rounded,
      'home' => Icons.home_rounded,
      'restaurant' => Icons.restaurant_rounded,
      'directions_car' => Icons.directions_car_rounded,
      'health_and_safety' => Icons.health_and_safety_rounded,
      'school' => Icons.school_rounded,
      'local_activity' => Icons.local_activity_rounded,
      'shopping_cart' => Icons.shopping_cart_rounded,
      'business_center' => Icons.business_center_rounded,
      'group' => Icons.group_rounded,
      'local_shipping' => Icons.local_shipping_rounded,
      'account_balance' => Icons.account_balance_rounded,
      'cloud' => Icons.cloud_rounded,
      'campaign' => Icons.campaign_rounded,
      'pets' => Icons.pets_rounded,
      'fitness_center' => Icons.fitness_center_rounded,
      'palette' => Icons.palette_rounded,
      'local_gas_station' => Icons.local_gas_station_rounded,
      'receipt' => Icons.receipt_long_rounded,
      _ => Icons.category_rounded,
    };
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'space_id': spaceId,
    'name': name,
    'type': type,
    'icon': icon,
    'color': color,
    'is_default': isDefault,
  };
}
