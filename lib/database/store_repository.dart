import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/store.dart';

/// Everything that touches `stores/{storeId}`.
class StoreRepository {
  StoreRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _stores =>
      _db.collection('stores');

  DocumentReference<Map<String, dynamic>> doc(String storeId) =>
      _stores.doc(storeId);

  Future<bool> exists(String storeId) async =>
      (await _stores.doc(storeId).get()).exists;

  Future<Store?> fetch(String storeId) async {
    final doc = await _stores.doc(storeId).get();
    return doc.exists ? Store.fromDoc(doc) : null;
  }

  Stream<Store?> watch(String storeId) => _stores
      .doc(storeId)
      .snapshots()
      .map((doc) => doc.exists ? Store.fromDoc(doc) : null);

  Future<void> create(Store store) async {
    await _stores.doc(store.id).set({
      ...store.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateName(String storeId, String name) =>
      _update(storeId, {'name': name});

  Future<void> updateDayCutoffHour(String storeId, int hour) {
    assert(hour >= 0 && hour <= 23);
    return _update(storeId, {'dayCutoffHour': hour});
  }

  Future<void> updateTax(String storeId,
          {required double taxRate, required bool taxIncluded}) =>
      _update(storeId, {'taxRate': taxRate, 'taxIncluded': taxIncluded});

  Future<void> updateTargets(String storeId, StoreTargets targets) =>
      _update(storeId, {'targets': targets.toMap()});

  Future<void> updateCategories(
          String storeId, List<StoreCategory> categories) =>
      _update(storeId,
          {'categories': categories.map((c) => c.toMap()).toList()});

  Future<void> updateDeliveryPlatforms(
          String storeId, List<DeliveryPlatform> platforms) =>
      _update(storeId,
          {'deliveryPlatforms': platforms.map((p) => p.toMap()).toList()});

  Future<void> _update(String storeId, Map<String, dynamic> data) =>
      _stores.doc(storeId).update({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
