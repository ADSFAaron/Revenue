import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/menu_import.dart';
import '../models/menu_item.dart';
import '../models/store.dart';
import 'data_exception.dart';

/// Must match `REGION` in functions/src/config.ts. Getting this wrong fails at
/// call time with a bare "not found", not at build time.
const String menuImportFunctionsRegion = 'asia-east1';

/// Must be at least `TIMEOUT_SECONDS` in functions/src/menu_import.ts.
///
/// The client default is seventy seconds, which one photo usually beats and a
/// four-photo menu usually does not. Left at the default, a two-page menu
/// fails on the client while the server is still working — the least useful
/// failure available, because it looks like a bug and costs the call anyway.
const Duration menuImportTimeout = Duration(minutes: 5);

/// A photograph on its way to the recogniser.
class MenuImportPhoto {
  const MenuImportPhoto({required this.bytes, required this.mimeType});

  final Uint8List bytes;

  /// JPEG, PNG or WebP — the function rejects anything else.
  final String mimeType;
}

class MenuImportException implements AppException {
  const MenuImportException(this.message);

  @override
  final String message;

  @override
  String toString() => message;
}

/// Turning a photograph of a menu into dishes.
///
/// Split in three deliberately. [recognise] talks to the server and returns a
/// draft; [flag] decides which rows a person has to look at; [commit] writes.
/// They are separate because a draft must be correctable before it is written
/// — an import that went straight into Firestore would leave a store that
/// wanted to undo it deleting dishes one at a time, and menu items are retired
/// rather than deleted, so "undo" would leave a drawer of inactive dishes
/// nobody can explain.
class MenuImportRepository {
  MenuImportRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _functions = functions ??
            FirebaseFunctions.instanceFor(region: menuImportFunctionsRegion);

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  /// The most photographs one menu may be. Mirrors `MAX_PHOTOS` in the
  /// function, which is what actually enforces it.
  static const int maxPhotos = 4;

  // -------------------------------------------------------------------------
  // Recognising
  // -------------------------------------------------------------------------

  /// Reads a menu off [photos]. Writes nothing.
  Future<MenuImportDraft> recognise(List<MenuImportPhoto> photos) async {
    if (photos.isEmpty) {
      throw const MenuImportException('Take a photo of the menu first.');
    }

    final Map<String, dynamic> data;
    try {
      final result = await _functions
          .httpsCallable(
            'importMenuFromPhotos',
            options: HttpsCallableOptions(timeout: menuImportTimeout),
          )
          .call({
        'photos': [
          for (final photo in photos)
            {'mimeType': photo.mimeType, 'data': base64Encode(photo.bytes)},
        ],
      });
      data = _asMap(result.data);
    } on FirebaseFunctionsException catch (e) {
      throw _translate(e);
    }

    final categories =
        ((data['categories'] as List?) ?? const []).whereType<String>().toList();
    final items = ((data['items'] as List?) ?? const [])
        .map((row) => MenuImportItem.fromMap(_asMap(row)))
        .where((item) => item.name.isNotEmpty)
        .toList();

    return MenuImportDraft(categories: categories, items: flag(items));
  }

  // -------------------------------------------------------------------------
  // Deciding what needs a second look
  // -------------------------------------------------------------------------

  /// Recomputes every row's flags across the whole draft.
  ///
  /// Whole-draft rather than per-row because two of the four rules — duplicates
  /// and outliers — are about a row's neighbours, so correcting one price can
  /// clear or raise a flag on a different row. Cheap enough to run on every
  /// edit at menu sizes; a long menu is two hundred dishes.
  static List<MenuImportItem> flag(List<MenuImportItem> items) {
    final counts = <String, int>{};
    for (final item in items) {
      final key = '${item.name} ${item.variant ?? ''}';
      counts[key] = (counts[key] ?? 0) + 1;
    }

    final medians = _sectionMedians(items);

    return [
      for (final item in items)
        item.copyWith(flags: _flagsFor(item, counts, medians)),
    ];
  }

  static Set<MenuImportFlag> _flagsFor(
    MenuImportItem item,
    Map<String, int> counts,
    Map<String, int> medians,
  ) {
    final flags = <MenuImportFlag>{};
    if (item.modelUnsure) flags.add(MenuImportFlag.unsure);

    if (item.price <= 0) {
      flags.add(MenuImportFlag.priceMissing);
    } else {
      if (item.price % 5 != 0) flags.add(MenuImportFlag.priceOdd);

      // Three times either side of the section's median. Wide on purpose: a
      // section really can hold a 60 dollar side and a 300 dollar hotpot, and
      // a rule that cried wolf would train people to approve without looking,
      // which is the one outcome that makes this worse than typing it in.
      final median = medians[item.categoryName ?? ''];
      if (median != null &&
          (item.price > median * 3 || item.price * 3 < median)) {
        flags.add(MenuImportFlag.priceOutlier);
      }
    }

    if ((counts['${item.name} ${item.variant ?? ''}'] ?? 0) > 1) {
      flags.add(MenuImportFlag.duplicate);
    }
    return flags;
  }

  /// Median price per section, for sections big enough for a median to mean
  /// anything. Four dishes is the floor — below that the "typical" price is
  /// whatever the outlier happens to be.
  static Map<String, int> _sectionMedians(List<MenuImportItem> items) {
    final bySection = <String, List<int>>{};
    for (final item in items) {
      if (item.price <= 0) continue;
      bySection.putIfAbsent(item.categoryName ?? '', () => []).add(item.price);
    }

    final medians = <String, int>{};
    bySection.forEach((section, prices) {
      if (prices.length < 4) return;
      prices.sort();
      medians[section] = prices[prices.length ~/ 2];
    });
    return medians;
  }

  // -------------------------------------------------------------------------
  // Writing
  // -------------------------------------------------------------------------

  /// Writes an approved draft into the store, creating any category it names
  /// that does not exist yet. Returns how many dishes were added.
  ///
  /// The order is fixed and matters: categories live inline on the store
  /// document while dishes live in a subcollection, so a dish written before
  /// its category exists is a dish pointing at a `categoryId` nothing
  /// resolves. The category update is therefore the first write of the first
  /// batch — no dish can land ahead of the section it names.
  ///
  /// Atomic up to Firestore's 500-write batch limit, and not beyond it. A menu
  /// past ~400 dishes is split across batches, and a failure partway leaves
  /// the earlier batches committed. That is deliberate rather than overlooked:
  /// the alternative is one transaction the size of the whole menu, which
  /// Firestore will not take, and a partial import is recoverable — re-running
  /// it adds the remainder, and the rows already written come back flagged as
  /// duplicates rather than silently doubling the menu. [MenuImportException]
  /// says how many dishes did land so the message can be honest about it.
  ///
  /// No audit entry. The log covers the four actions that can move money
  /// without a sale happening — voiding, editing, discounting, repricing — and
  /// adding dishes is none of them, any more than typing them in by hand is.
  Future<int> commit({
    required Store store,
    required List<MenuImportItem> items,
    required List<MenuItem> existing,
  }) async {
    final approved = items.where((i) => i.name.trim().isNotEmpty).toList();
    if (approved.isEmpty) return 0;

    final categories = [...store.categories];
    final idsByName = {
      for (final category in categories) _key(category.name): category.id,
    };

    // One stamp for the whole import, so ids created together sort together
    // and read as one event rather than as a scatter.
    final stamp = DateTime.now().microsecondsSinceEpoch;
    var created = 0;
    for (final item in approved) {
      final name = item.categoryName?.trim();
      if (name == null || name.isEmpty) continue;
      if (idsByName.containsKey(_key(name))) continue;

      final id = 'cat_${stamp}_$created';
      idsByName[_key(name)] = id;
      categories.add(
        StoreCategory(id: id, name: name, sortOrder: categories.length),
      );
      created += 1;
    }

    // Imported dishes land after whatever is already there. Nothing gets
    // reordered by an import — a shop that has arranged its menu should not
    // find it rearranged because somebody photographed a second page.
    var sortOrder = existing.fold<int>(
      -1,
      (highest, item) => item.sortOrder > highest ? item.sortOrder : highest,
    );

    final storeDoc = _db.collection('stores').doc(store.id);
    final menuItems = storeDoc.collection('menuItems');

    final writes = <void Function(WriteBatch)>[];
    if (created > 0) {
      writes.add((batch) => batch.update(storeDoc, {
            'categories': categories.map((c) => c.toMap()).toList(),
            'updatedAt': FieldValue.serverTimestamp(),
          }));
    }
    for (final item in approved) {
      sortOrder += 1;
      final data = item
          .toMenuItem(
            categoryId: idsByName[_key(item.categoryName ?? '')],
            sortOrder: sortOrder,
          )
          .toMap();
      writes.add((batch) => batch.set(menuItems.doc(), {
            ...data,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }));
    }

    // Firestore caps a batch at 500 writes. A menu is rarely a quarter of
    // that, but "rarely" is not "never", and the failure would be the whole
    // import rejected after somebody had already checked every row.
    var written = 0;
    for (var start = 0; start < writes.length; start += _batchSize) {
      final chunk = writes.skip(start).take(_batchSize).toList();
      final batch = _db.batch();
      for (final write in chunk) {
        write(batch);
      }
      try {
        await batch.commit();
      } on FirebaseException catch (e) {
        throw _translateWrite(e, dishesWritten: written);
      }
      // The category update rides in the first batch and is not a dish.
      written += chunk.length - (start == 0 && created > 0 ? 1 : 0);
    }

    return approved.length;
  }

  /// Writes per batch. Under Firestore's limit of 500 with room to spare, so
  /// that a future field on a dish cannot quietly push a real menu over it.
  static const int _batchSize = 400;

  /// Category names match on trimmed, case-folded text, so an import does not
  /// create a second "Drinks" alongside the existing "drinks".
  static String _key(String name) => name.trim().toLowerCase();

  /// A failed write, said in terms of what actually happened to the menu.
  ///
  /// [dishesWritten] is the count that committed before the failure — zero for
  /// all but a menu long enough to be split across batches. Saying "nothing
  /// was added" when eighty dishes were is worse than saying nothing at all:
  /// it is what makes somebody import the same menu twice.
  MenuImportException _translateWrite(
    FirebaseException e, {
    required int dishesWritten,
  }) {
    final partial = dishesWritten > 0
        ? ' $dishesWritten ${dishesWritten == 1 ? 'dish was' : 'dishes were'} '
            'added before it stopped — check the menu before importing again.'
        : '';
    return switch (e.code) {
      'permission-denied' => MenuImportException(
          'Only an owner or a manager can add dishes.$partial'),
      'not-found' => MenuImportException(
          'This store no longer exists, so nothing could be added.$partial'),
      'unavailable' => MenuImportException(
          'No connection to the database. Nothing was added — try again once '
          'you are back online.$partial'),
      _ => MenuImportException(
          e.message ?? 'The dishes could not be saved (${e.code}).$partial'),
    };
  }

  // -------------------------------------------------------------------------

  /// Callables hand back `Map<Object?, Object?>` on Android and
  /// `Map<String, dynamic>` on web.
  static Map<String, dynamic> _asMap(Object? value) {
    if (value is! Map) return <String, dynamic>{};
    return value.map((key, item) => MapEntry('$key', item));
  }

  MenuImportException _translate(FirebaseFunctionsException e) =>
      switch (e.code) {
        'unauthenticated' =>
          const MenuImportException('Sign in before importing a menu.'),
        'permission-denied' => MenuImportException(
            e.message ?? 'Only an owner or a manager can import a menu.'),
        'invalid-argument' =>
          MenuImportException(e.message ?? 'Those photos could not be sent.'),
        'resource-exhausted' => MenuImportException(
            e.message ?? 'The menu reader is busy. Try again in a moment.'),
        'deadline-exceeded' => const MenuImportException(
            'Reading the menu took too long. Try fewer photos at a time.'),
        'not-found' => const MenuImportException(
            'The menu reader is not deployed. Run '
            '`firebase deploy --only functions`.'),
        'unavailable' => const MenuImportException(
            'Could not reach the menu reader. Check your network.'),
        _ => MenuImportException(
            e.message ?? 'The menu reader failed (${e.code}).'),
      };
}
