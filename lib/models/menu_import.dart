import 'menu_item.dart';

/// Why a row read off a photograph is being put in front of somebody.
///
/// Two sources, deliberately mixed into one list. [unsure] is the model's own
/// hedge — it saw a blur and said so. The rest are arithmetic the app does
/// afterwards, and they exist because the model's hedge misses the case that
/// matters most: a price read *confidently* and wrongly. 120 transcribed as
/// 720 raises no doubt in the reader and would otherwise sail through.
enum MenuImportFlag {
  /// The model said it could not be certain of this row.
  unsure('Unclear in the photo'),

  /// No price at all, or zero.
  priceMissing('No price read'),

  /// Not a multiple of five. Taiwanese menus almost always are, so this is
  /// usually a digit that was misread rather than a genuinely odd price.
  priceOdd('Unusual price'),

  /// Far from the other dishes in the same section — the shape a lost or
  /// gained digit makes.
  priceOutlier('Price out of line with the section'),

  /// Another row has the same name and portion. Either the menu repeats it or
  /// one of the two was read wrong.
  duplicate('Appears twice');

  const MenuImportFlag(this.label);

  final String label;
}

/// One dish as read off a photograph, on its way to becoming a [MenuItem].
///
/// [name] and [variant] are kept apart all the way to the point of writing.
/// Asked for a single field the model returns "牛肉麵 大" one time and
/// "牛肉麵(大)" the next, and two dishes differing only by a separator are two
/// dishes forever — so the app composes the string itself, once, in
/// [displayName].
class MenuImportItem {
  const MenuImportItem({
    required this.name,
    this.variant,
    this.price = 0,
    this.categoryName,
    this.modelUnsure = false,
    this.modelNote,
    this.flags = const {},
    this.reviewed = false,
  });

  /// The dish alone: no price, no portion, no currency.
  final String name;

  /// The portion or option this price is for — 大, 小, 套餐 — or null when the
  /// dish is sold at one price. A dish with two prices arrives as two items
  /// sharing a [name], which is what lets the analysis pages tell later which
  /// size actually sells.
  final String? variant;

  /// Whole New Taiwan dollars.
  final int price;

  /// The section heading it sat under, as printed. Resolved to a category id
  /// only at the moment of writing, because the id may not exist yet.
  final String? categoryName;

  /// The model's own doubt about this row. Never recomputed — it is a fact
  /// about the photograph, not about the current values.
  final bool modelUnsure;

  /// One short phrase from the model saying what was unclear.
  final String? modelNote;

  /// Recomputed from scratch every time the draft changes.
  final Set<MenuImportFlag> flags;

  /// Set once somebody has looked at this row, so a corrected dish stops
  /// asking for attention it no longer needs.
  final bool reviewed;

  /// What goes into `MenuItem.name`.
  String get displayName =>
      (variant == null || variant!.isEmpty) ? name : '$name $variant';

  bool get needsReview => flags.isNotEmpty && !reviewed;

  /// Every dish starts on the default icon. The model is never asked to pick
  /// one: `MenuItem.icon` is a MaterialIcons code point, and a model guessing
  /// at code points produces dishes with an icon nobody chose and no way to
  /// tell which were guesses.
  MenuItem toMenuItem({String? categoryId, required int sortOrder}) => MenuItem(
        id: '',
        name: displayName,
        categoryId: categoryId,
        sortOrder: sortOrder,
        price: price,
      );

  factory MenuImportItem.fromMap(Map<String, dynamic> map) {
    final variant = (map['variant'] as String?)?.trim();
    final category = (map['category'] as String?)?.trim();
    final note = (map['reviewNote'] as String?)?.trim();
    return MenuImportItem(
      name: (map['name'] as String? ?? '').trim(),
      variant: (variant == null || variant.isEmpty) ? null : variant,
      price: (map['price'] as num?)?.toInt() ?? 0,
      categoryName: (category == null || category.isEmpty) ? null : category,
      modelUnsure: map['needsReview'] == true,
      modelNote: (note == null || note.isEmpty) ? null : note,
    );
  }

  MenuImportItem copyWith({
    String? name,
    String? variant,
    bool clearVariant = false,
    int? price,
    String? categoryName,
    bool clearCategory = false,
    Set<MenuImportFlag>? flags,
    bool? reviewed,
  }) =>
      MenuImportItem(
        name: name ?? this.name,
        variant: clearVariant ? null : (variant ?? this.variant),
        price: price ?? this.price,
        categoryName:
            clearCategory ? null : (categoryName ?? this.categoryName),
        modelUnsure: modelUnsure,
        modelNote: modelNote,
        flags: flags ?? this.flags,
        reviewed: reviewed ?? this.reviewed,
      );
}

/// A whole menu as read off one or more photographs, before anybody has
/// approved it. Nothing here has been written anywhere.
class MenuImportDraft {
  const MenuImportDraft({this.categories = const [], this.items = const []});

  /// Section headings in the order they appeared on the menu, which is the
  /// order they should end up in on screen.
  final List<String> categories;

  final List<MenuImportItem> items;

  bool get isEmpty => items.isEmpty;

  int get reviewCount => items.where((i) => i.needsReview).length;
}
