import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// `stores/{storeId}/menuItems/{itemId}`.
///
/// The id is a stable Firestore id, not the dish name — renaming a dish must
/// not split its sales history into two dishes.
class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    this.categoryId,
    this.icon = defaultIconCodePoint,
    this.sortOrder = 0,
    this.price = 0,
    this.cost = 0,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  /// Icons.restaurant — what a dish gets before anyone picks one.
  static const String defaultIconCodePoint = '0xe56c';

  final String id;
  final String name;
  final String? categoryId;

  /// MaterialIcons code point as a string, e.g. '0xe56c'.
  final String icon;
  final int sortOrder;
  final int price;

  /// Ingredient cost. Optional — 0 means "not filled in yet", which the menu
  /// engineering report treats as unknown rather than as free.
  final int cost;

  /// Soft delete. Retiring a dish must never orphan the orders that contain it,
  /// so items are deactivated instead of removed.
  final bool isActive;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory MenuItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return MenuItem(
      id: doc.id,
      name: data['name'] as String? ?? '',
      categoryId: data['categoryId'] as String?,
      icon: data['icon'] as String? ?? defaultIconCodePoint,
      sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
      price: (data['price'] as num?)?.toInt() ?? 0,
      cost: (data['cost'] as num?)?.toInt() ?? 0,
      isActive: data['isActive'] as bool? ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'categoryId': categoryId,
        'icon': icon,
        'sortOrder': sortOrder,
        'price': price,
        'cost': cost,
        'isActive': isActive,
      };

  IconData get iconData =>
      IconData(int.tryParse(icon) ?? int.parse(defaultIconCodePoint),
          fontFamily: 'MaterialIcons');

  /// Gross margin as a fraction of price, or null when the cost is unknown.
  double? get marginRate {
    if (cost <= 0 || price <= 0) return null;
    return (price - cost) / price;
  }

  int get unitProfit => price - cost;

  MenuItem copyWith({
    String? name,
    String? categoryId,
    String? icon,
    int? sortOrder,
    int? price,
    int? cost,
    bool? isActive,
  }) =>
      MenuItem(
        id: id,
        name: name ?? this.name,
        categoryId: categoryId ?? this.categoryId,
        icon: icon ?? this.icon,
        sortOrder: sortOrder ?? this.sortOrder,
        price: price ?? this.price,
        cost: cost ?? this.cost,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
