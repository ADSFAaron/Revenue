import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Revenue/models/menu_item.dart';
import 'package:Revenue/widgets/dish_icons.dart';

/// Material's code points are not stable, and this app learned that the
/// expensive way: `MenuItem.defaultIconCodePoint` was written as the literal
/// `0xe56c` when that was `Icons.restaurant`, and by the time anybody looked
/// again the same number meant `Icons.security_update_warning`. Every dish in
/// the shop was showing a phone with a warning triangle on it, and nothing in
/// the code had changed.
void main() {
  test('the default code point is still Icons.restaurant', () {
    expect(
      MenuItem.defaultIconCodePoint,
      Icons.restaurant.codePoint.toString(),
      reason: 'Material moved its code points again. Update the literal — and '
          'note that every menu already saved carries the old number.',
    );
  });

  test('a dish with no icon on file gets the default, not a blank', () {
    expect(const MenuItem(id: 'a', name: 'x').iconData, Icons.restaurant);
  });

  test('the retired 0xe56c falls back instead of rendering a warning phone',
      () {
    // 0xe56c is what old menus have stored. It must not reach the font.
    const stale = MenuItem(id: 'a', name: 'x', icon: '58732');
    expect(stale.iconData, Icons.restaurant);
    expect(stale.iconData, isNot(Icons.security_update_warning));
  });

  test('every curated icon round-trips through storage', () {
    for (final choice in kDishIcons) {
      expect(resolveDishIcon(choice.codePoint).icon, choice.icon,
          reason: '${choice.name} did not survive being stored');
    }
  });

  test('the curated list has no duplicate glyphs', () {
    final seen = <int>{};
    for (final choice in kDishIcons) {
      expect(seen.add(choice.icon.codePoint), isTrue,
          reason: '${choice.name} repeats an icon already in the list');
    }
  });
}
