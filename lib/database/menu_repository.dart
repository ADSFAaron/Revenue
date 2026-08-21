import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/menu_item.dart';
import '../models/store.dart';

/// Everything that touches `stores/{storeId}/menuItems/{itemId}`.
///
/// The menu is a subcollection rather than an array on the store document so
/// that each dish keeps a stable id across renames and price changes.
class MenuRepository {
  MenuRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _items(String storeId) =>
      _db.collection('stores').doc(storeId).collection('menuItems');

  /// The categories a brand-new store starts with.
  static List<StoreCategory> get defaultCategories => const [
        StoreCategory(id: 'cat_main', name: '主餐', sortOrder: 0),
        StoreCategory(id: 'cat_side', name: '小菜', sortOrder: 1),
        StoreCategory(id: 'cat_drink', name: '飲料', sortOrder: 2),
      ];

  /// A starter menu, so a new store is not an empty screen. Every field here is
  /// editable in Store Settings → Edit Menu; costs are left at 0 for the owner
  /// to fill in.
  static List<MenuItem> get defaultMenu => [
        MenuItem(
            id: '',
            name: '牛肉麵',
            categoryId: 'cat_main',
            icon: Icons.ramen_dining.codePoint.toString(),
            price: 130,
            sortOrder: 0),
        MenuItem(
            id: '',
            name: '滷肉飯',
            categoryId: 'cat_main',
            icon: Icons.rice_bowl.codePoint.toString(),
            price: 45,
            sortOrder: 1),
        MenuItem(
            id: '',
            name: '乾麵',
            categoryId: 'cat_main',
            icon: Icons.ramen_dining.codePoint.toString(),
            price: 50,
            sortOrder: 2),
        MenuItem(
            id: '',
            name: '燙青菜',
            categoryId: 'cat_side',
            icon: Icons.eco.codePoint.toString(),
            price: 35,
            sortOrder: 3),
        MenuItem(
            id: '',
            name: '滷蛋',
            categoryId: 'cat_side',
            icon: Icons.egg.codePoint.toString(),
            price: 15,
            sortOrder: 4),
        MenuItem(
            id: '',
            name: '紅茶',
            categoryId: 'cat_drink',
            icon: Icons.local_cafe.codePoint.toString(),
            price: 25,
            sortOrder: 5),
      ];

  /// Dishes currently on sale, in menu order.
  Stream<List<MenuItem>> watchActive(String storeId) => _items(storeId)
      .where('isActive', isEqualTo: true)
      .snapshots()
      .map(_sorted);

  /// Every dish including retired ones — the menu editor needs these so a
  /// retired dish can be brought back.
  Stream<List<MenuItem>> watchAll(String storeId) =>
      _items(storeId).snapshots().map(_sorted);

  Future<List<MenuItem>> fetchActive(String storeId) async =>
      _sorted(await _items(storeId).where('isActive', isEqualTo: true).get());

  Future<List<MenuItem>> fetchAll(String storeId) async =>
      _sorted(await _items(storeId).get());

  List<MenuItem> _sorted(QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs.map(MenuItem.fromDoc).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  Future<String> add(String storeId, MenuItem item) async {
    final ref = await _items(storeId).add({
      ...item.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> update(String storeId, MenuItem item) =>
      _items(storeId).doc(item.id).update({
        ...item.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Retires a dish. Never deletes it: past orders reference this id, and a
  /// missing item turns them into rows nobody can interpret.
  Future<void> deactivate(String storeId, String itemId) =>
      _setActive(storeId, itemId, false);

  Future<void> reactivate(String storeId, String itemId) =>
      _setActive(storeId, itemId, true);

  Future<void> _setActive(String storeId, String itemId, bool isActive) =>
      _items(storeId).doc(itemId).update({
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Persists a drag-to-reorder as consecutive `sortOrder` values.
  Future<void> reorder(String storeId, List<MenuItem> ordered) async {
    final batch = _db.batch();
    for (var i = 0; i < ordered.length; i++) {
      batch.update(_items(storeId).doc(ordered[i].id), {
        'sortOrder': i,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// Writes the starter menu. Called once, when a store is first created.
  Future<void> seedDefaults(String storeId) async {
    final batch = _db.batch();
    for (final item in defaultMenu) {
      batch.set(_items(storeId).doc(), {
        ...item.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}
