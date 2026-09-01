import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../widgets/dish_icons.dart';

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
    this.aliases = const [],
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  /// `Icons.restaurant`, as decimal — what a dish gets before anyone picks one.
  ///
  /// It has to be a literal, because it is a default parameter value and those
  /// must be constant, and a literal is exactly what went wrong before: this
  /// used to read `'0xe56c'`, which *was* `Icons.restaurant` when it was typed
  /// and is `Icons.security_update_warning` today. Material's code points moved
  /// underneath it and every dish on every menu quietly turned into a phone
  /// with a warning triangle on it.
  ///
  /// So the literal stays and a test holds it to account —
  /// `test/models/dish_icon_test.dart` fails the moment this stops being
  /// `Icons.restaurant.codePoint`. The next drift is a red test rather than a
  /// menu full of the wrong picture.
  static const String defaultIconCodePoint = '58674';

  final String id;
  final String name;
  final String? categoryId;

  /// A Material code point as a decimal string. Only the ones in
  /// [kDishIcons] resolve to a glyph; anything else falls back — see
  /// [iconData].
  final String icon;
  final int sortOrder;
  final int price;

  /// Ingredient cost. Optional — 0 means "not filled in yet", which the menu
  /// engineering report treats as unknown rather than as free.
  final int cost;

  /// What the kitchen actually calls it: 牛麵, 乾意, 大乾.
  ///
  /// A menu says 「牛肉麵 (大)」 and every slip in the shop says 「牛麵大」. The
  /// till's search box only ever matched the printed name, so the shorthand
  /// everybody uses found nothing and the dish had to be hunted for by eye.
  ///
  /// It is also the piece that any photo-of-a-slip recognition will stand on:
  /// a model given the menu as its vocabulary can only match what the menu
  /// says, and what the menu says is not what is written on the paper.
  final List<String> aliases;

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
      aliases: ((data['aliases'] as List?) ?? const [])
          .whereType<String>()
          .map((a) => a.trim())
          .where((a) => a.isNotEmpty)
          .toList(),
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
        'aliases': aliases,
        'isActive': isActive,
      };

  /// The glyph this dish wears.
  ///
  /// Resolved through [resolveDishIcon] rather than built from the stored
  /// number. Constructing `IconData(n)` from a database value looks equivalent
  /// and is not: `flutter build --release` tree-shakes the icon font down to
  /// the code points it can see in `const IconData` expressions, so a number
  /// that arrives at runtime has no guarantee of a glyph behind it. Going
  /// through the curated list means every icon a dish can have is one the
  /// build already knows to keep.
  IconData get iconData => resolveDishIcon(icon).icon;

  /// Gross margin as a fraction of price, or null when the cost is unknown.
  double? get marginRate {
    if (cost <= 0 || price <= 0) return null;
    return (price - cost) / price;
  }

  MenuItem copyWith({
    String? name,
    String? categoryId,
    String? icon,
    int? sortOrder,
    int? price,
    int? cost,
    List<String>? aliases,
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
        aliases: aliases ?? this.aliases,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  /// Whether [query] names this dish — by its printed name or by anything the
  /// shop calls it.
  ///
  /// Lives on the model rather than in the search box so that every caller
  /// matches identically: the till's filter today, and whatever reads a
  /// photographed order slip later.
  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    if (name.toLowerCase().contains(needle)) return true;
    for (final alias in aliases) {
      if (alias.toLowerCase().contains(needle)) return true;
    }
    return false;
  }
}
