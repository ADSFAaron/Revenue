import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/database/menu_import_repository.dart';
import 'package:Revenue/models/menu_import.dart';
import 'package:Revenue/models/menu_item.dart';

/// The rules that decide which rows a person is made to look at.
///
/// These matter more than they look. The model flags its own doubt, which
/// catches blur and glare — but the failure that costs money is a price read
/// *confidently* and wrongly, and by definition it arrives unflagged. These
/// checks are the only thing standing in front of it, so they are tested
/// against the shapes a misread digit actually makes.
void main() {
  MenuImportItem dish(
    String name, {
    int price = 100,
    String? category = '麵類',
    String? variant,
    bool unsure = false,
  }) =>
      MenuImportItem(
        name: name,
        price: price,
        categoryName: category,
        variant: variant,
        modelUnsure: unsure,
      );

  Set<MenuImportFlag> flagsOn(List<MenuImportItem> items, String name) =>
      MenuImportRepository.flag(items).firstWhere((i) => i.name == name).flags;

  group('flagging', () {
    test('a clean menu raises nothing', () {
      final items = [
        dish('牛肉麵', price: 120),
        dish('陽春麵', price: 60),
        dish('餛飩麵', price: 80),
        dish('炸醬麵', price: 90),
      ];
      for (final item in MenuImportRepository.flag(items)) {
        expect(item.flags, isEmpty, reason: item.name);
      }
    });

    test("the model's own doubt is carried through", () {
      expect(
        flagsOn([dish('牛肉麵', unsure: true)], '牛肉麵'),
        contains(MenuImportFlag.unsure),
      );
    });

    test('a missing price is flagged and does not also read as odd', () {
      final flags = flagsOn([dish('牛肉麵', price: 0)], '牛肉麵');
      expect(flags, contains(MenuImportFlag.priceMissing));
      expect(flags, isNot(contains(MenuImportFlag.priceOdd)));
    });

    test('a price that is not a multiple of five is flagged', () {
      expect(flagsOn([dish('牛肉麵', price: 123)], '牛肉麵'),
          contains(MenuImportFlag.priceOdd));
      expect(flagsOn([dish('牛肉麵', price: 125)], '牛肉麵'),
          isNot(contains(MenuImportFlag.priceOdd)));
    });

    // The case the model's own flag misses: 120 read as 720 is a perfectly
    // legible number, so nothing upstream doubts it.
    test('a gained digit is caught as an outlier', () {
      final items = [
        dish('牛肉麵', price: 720),
        dish('陽春麵', price: 60),
        dish('餛飩麵', price: 80),
        dish('炸醬麵', price: 90),
        dish('乾麵', price: 70),
      ];
      expect(flagsOn(items, '牛肉麵'), contains(MenuImportFlag.priceOutlier));
      expect(flagsOn(items, '陽春麵'), isNot(contains(MenuImportFlag.priceOutlier)));
    });

    test('a lost digit is caught too', () {
      final items = [
        dish('牛肉麵', price: 12),
        dish('陽春麵', price: 60),
        dish('餛飩麵', price: 80),
        dish('炸醬麵', price: 90),
        dish('乾麵', price: 70),
      ];
      expect(flagsOn(items, '牛肉麵'), contains(MenuImportFlag.priceOutlier));
    });

    // Deliberately wide. A section really can hold a 60 dollar side next to a
    // 150 dollar main, and a rule that cried wolf would teach people to
    // approve without reading — which is worse than not flagging at all.
    test('an honestly expensive dish in a mixed section is left alone', () {
      final items = [
        dish('招牌牛肉麵', price: 180),
        dish('陽春麵', price: 60),
        dish('餛飩麵', price: 80),
        dish('炸醬麵', price: 90),
        dish('乾麵', price: 70),
      ];
      expect(flagsOn(items, '招牌牛肉麵'),
          isNot(contains(MenuImportFlag.priceOutlier)));
    });

    test('a section too small for a median does not get one invented', () {
      final items = [
        dish('牛肉麵', price: 700),
        dish('陽春麵', price: 60),
        dish('餛飩麵', price: 80),
      ];
      expect(
          flagsOn(items, '牛肉麵'), isNot(contains(MenuImportFlag.priceOutlier)));
    });

    test('sections are judged against themselves, not the whole menu', () {
      final items = [
        dish('紅茶', price: 30, category: '飲料'),
        dish('綠茶', price: 30, category: '飲料'),
        dish('奶茶', price: 40, category: '飲料'),
        dish('豆漿', price: 35, category: '飲料'),
        dish('牛肉麵', price: 120),
        dish('陽春麵', price: 60),
        dish('餛飩麵', price: 80),
        dish('炸醬麵', price: 90),
      ];
      // 120 is four times the drinks median and would be an outlier there.
      expect(flagsOn(items, '牛肉麵'), isNot(contains(MenuImportFlag.priceOutlier)));
    });

    test('two identical rows are both flagged', () {
      final items = [dish('牛肉麵', price: 120), dish('牛肉麵', price: 120)];
      for (final item in MenuImportRepository.flag(items)) {
        expect(item.flags, contains(MenuImportFlag.duplicate));
      }
    });

    // The whole reason name and variant are kept apart: one dish sold at two
    // prices is two rows, and they must not read as a duplicate.
    test('the same dish in two portions is not a duplicate', () {
      final items = [
        dish('牛肉麵', price: 130, variant: '大'),
        dish('牛肉麵', price: 100, variant: '小'),
      ];
      for (final item in MenuImportRepository.flag(items)) {
        expect(item.flags, isNot(contains(MenuImportFlag.duplicate)));
      }
    });

    test('flags are recomputed from scratch, not accumulated', () {
      final flagged = MenuImportRepository.flag([dish('牛肉麵', price: 123)]);
      expect(flagged.single.flags, contains(MenuImportFlag.priceOdd));

      final corrected =
          MenuImportRepository.flag([flagged.single.copyWith(price: 125)]);
      expect(corrected.single.flags, isEmpty);
    });

    test("a hand correction stops the row asking, but the model's note stays",
        () {
      final flagged =
          MenuImportRepository.flag([dish('牛肉麵', price: 120, unsure: true)]);
      expect(flagged.single.needsReview, isTrue);

      final reviewed =
          MenuImportRepository.flag([flagged.single.copyWith(reviewed: true)]);
      expect(reviewed.single.needsReview, isFalse);
      // Still on record — the photo was unclear whatever anybody typed.
      expect(reviewed.single.flags, contains(MenuImportFlag.unsure));
    });
  });

  group('reading the model back', () {
    test('name and portion stay apart and are joined once, here', () {
      final item = MenuImportItem.fromMap({
        'name': '牛肉麵',
        'variant': '大',
        'price': 130,
        'category': '麵類',
        'needsReview': false,
        'reviewNote': null,
      });
      expect(item.name, '牛肉麵');
      expect(item.variant, '大');
      expect(item.displayName, '牛肉麵 大');
      expect(item.toMenuItem(sortOrder: 0).name, '牛肉麵 大');
    });

    test('a dish with one price gets no portion suffix', () {
      final item = MenuImportItem.fromMap({
        'name': '滷蛋',
        'variant': null,
        'price': 15,
        'category': null,
        'needsReview': false,
        'reviewNote': null,
      });
      expect(item.displayName, '滷蛋');
    });

    test('blank strings from the model become null, not empty fields', () {
      final item = MenuImportItem.fromMap({
        'name': '  滷蛋  ',
        'variant': '   ',
        'price': 15,
        'category': '',
        'needsReview': true,
        'reviewNote': '  ',
      });
      expect(item.name, '滷蛋');
      expect(item.variant, isNull);
      expect(item.categoryName, isNull);
      expect(item.modelNote, isNull);
      expect(item.displayName, '滷蛋');
    });

    test('a missing price reads as zero rather than throwing', () {
      final item = MenuImportItem.fromMap({'name': '滷蛋'});
      expect(item.price, 0);
      expect(
        MenuImportRepository.flag([item]).single.flags,
        contains(MenuImportFlag.priceMissing),
      );
    });

    test('an imported dish never carries a guessed icon', () {
      final item = MenuImportItem.fromMap({'name': '牛肉麵', 'price': 120});
      expect(item.toMenuItem(sortOrder: 0).icon,
          MenuItem.defaultIconCodePoint);
    });
  });
}