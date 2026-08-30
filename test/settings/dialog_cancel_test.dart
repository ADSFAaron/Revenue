import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the shape every settings dialog uses, down the **Cancel** path.
///
/// Cancel used to crash all of them. The cause was a controller created inside
/// the method that showed the dialog and disposed on the line after the await:
///
/// ```dart
/// final controller = TextEditingController(text: ...);
/// final saved = await showDialog<bool>(...);
/// controller.dispose();          // ← too early
/// ```
///
/// `showDialog`'s future completes when the route is *popped*, which is the
/// start of the exit transition, not the end of it. The dialog stays mounted
/// while that plays, and its `TextField` keeps reading the controller — so the
/// dispose lands in the middle and the next frame throws
/// *"A TextEditingController was used after being disposed"*.
///
/// The fix is to give the controller an owner whose lifetime is longer than the
/// dialog's: the screen's `State`. These tests pin that down, and they pump all
/// the way through the exit transition, because a test that stops at
/// `Navigator.pop` never enters the window where the bug lived.
void main() {
  testWidgets('cancelling twice in a row leaves nothing broken',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _SettingsLikeScreen()));

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'cancel #${i + 1} threw');
      expect(find.byType(AlertDialog), findsNothing);
    }
  });

  testWidgets('cancelling and leaving the screen mid-transition',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _SettingsLikeScreen()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    // One frame only: the dialog is still on its way out. Tearing the screen
    // down here is what a quick Cancel-then-Back does.
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('saving still returns the edited value', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _SettingsLikeScreen()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Noodle Shop');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('saved: Noodle Shop'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reopening resets the field instead of keeping the last edit',
      (tester) async {
    // The cost of a shared controller: it remembers. Every dialog that opens
    // has to set `.text` on the way in, or the last edit bleeds into the next.
    await tester.pumpWidget(const MaterialApp(home: _SettingsLikeScreen()));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'typed then abandoned');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('typed then abandoned'), findsNothing);
    expect(find.text('initial'), findsOneWidget);
  });
}

/// The same shape as `_editStoreNameDialog`, `_editTaxDialog`,
/// `_editDisplayName` and the rest: a `State` that owns the controller, resets
/// its text on the way in, and disposes it only when the screen goes away.
class _SettingsLikeScreen extends StatefulWidget {
  const _SettingsLikeScreen();

  @override
  State<_SettingsLikeScreen> createState() => _SettingsLikeScreenState();
}

class _SettingsLikeScreenState extends State<_SettingsLikeScreen> {
  final controller = TextEditingController();
  String? saved;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    controller.text = 'initial';

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    // Deliberately no dispose here. That is the whole point.
    if (result == null || result.isEmpty) return;
    if (mounted) setState(() => saved = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(onPressed: _open, child: const Text('open')),
          if (saved != null) Text('saved: $saved'),
        ],
      ),
    );
  }
}
