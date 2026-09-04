import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/widgets/dropdown_value.dart';

void main() {
  group('what a dropdown may be shown', () {
    test('a value that is on the list is kept', () {
      expect(dropdownValue('b', ['a', 'b', 'c']), 'b');
    });

    test('a value that is not is dropped', () {
      // A dish pointing at a deleted category, an order naming a delivery
      // platform the store no longer has.
      expect(dropdownValue('deleted', ['a', 'b']), isNull);
    });

    test('null is a real choice when null is on the list', () {
      // The importer's "No category" is an option, not an absence.
      expect(dropdownValue<String?>(null, <String?>[null, 'a']), isNull);
      expect(dropdownValue<String?>('a', <String?>[null, 'a']), 'a');
    });

    test('an out-of-range number is dropped', () {
      expect(dropdownValue(25, List.generate(24, (h) => h)), isNull);
      expect(dropdownValue(4, List.generate(24, (h) => h)), 4);
    });
  });

  testWidgets('the guard is what stops the screen dying', (tester) async {
    // Without it this throws "There should be exactly one item with
    // [DropdownButton]'s value" and the page is replaced by a red screen that
    // cannot be closed.
    const items = [
      DropdownMenuItem(value: 'a', child: Text('A')),
      DropdownMenuItem(value: 'b', child: Text('B')),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DropdownButtonFormField<String>(
          initialValue: dropdownValue('deleted-category', const ['a', 'b']),
          items: items,
          onChanged: (_) {},
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
