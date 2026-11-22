import 'package:flutter/material.dart';

import 'category_style_catalog.dart';

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
    this.parentId,
    this.parentName,
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
      parentId: json['parent_id'] as int?,
      parentName: json['parent'] != null
          ? (json['parent']['name'] as String?)
          : (json['parent_name'] as String?),
    );
  }

  final int id;
  final int spaceId;
  final String name;
  final String type; // 'income' | 'expense'
  final String icon;
  final String color;
  final bool isDefault;
  final int? parentId;
  final String? parentName;

  bool get isSubcategory => parentId != null;
  bool get isIncome => type == 'income';
  bool get isExpense => type == 'expense';

  String get fullName => parentName != null && parentName!.isNotEmpty
      ? '$parentName > $name'
      : name;

  Color get colorValue =>
      CategoryStyleCatalog.colorFromHex(color, isIncome: isIncome);

  static Color colorHexToColor(String colorHex, {bool isIncome = false}) =>
      CategoryStyleCatalog.colorFromHex(colorHex, isIncome: isIncome);

  IconData get iconData => CategoryStyleCatalog.getIcon(icon);

  static IconData iconToMaterial(String iconName) =>
      CategoryStyleCatalog.getIcon(iconName);

  Map<String, dynamic> toJson() => {
    'id': id,
    'space_id': spaceId,
    'name': name,
    'type': type,
    'icon': icon,
    'color': color,
    'is_default': isDefault,
    'parent_id': parentId,
    'parent_name': parentName,
  };
}
