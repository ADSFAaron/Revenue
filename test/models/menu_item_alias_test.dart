import 'package:flutter_test/flutter_test.dart';

import 'package:Revenue/models/menu_item.dart';

/// A menu says 「牛肉麵 (大)」 and every slip in the shop says 「牛麵大」. The till's
/// search only ever matched the printed name, so the shorthand everybody
/// actually uses found nothing.
void main() {
  const item = MenuItem(
    id: 'i1',
    name: '牛肉麵 (大)',
    aliases: ['牛麵大', 'big beef noodle'],
  );

  test('the printed name still matches', () {
    expect(item.matches('牛肉麵'), isTrue);
    expect(item.matches('(大)'), isTrue);
  });

  test('what the kitchen calls it matches too', () {
    expect(item.matches('牛麵大'), isTrue);
    expect(item.matches('牛麵'), isTrue);
  });

  test('aliases are matched case-insensitively, like the name', () {
    expect(item.matches('BIG BEEF'), isTrue);
  });

  test('an empty query is not a filter', () {
    expect(item.matches(''), isTrue);
    expect(item.matches('   '), isTrue);
  });

  test('something else still does not match', () {
    expect(item.matches('雞排'), isFalse);
  });

  test('a dish with no aliases behaves exactly as before', () {
    const plain = MenuItem(id: 'i2', name: '白飯');
    expect(plain.matches('白飯'), isTrue);
    expect(plain.matches('飯'), isTrue);
    expect(plain.matches('麵'), isFalse);
  });
}
