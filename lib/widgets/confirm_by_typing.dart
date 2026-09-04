import 'package:flutter/material.dart';

import 'feedback.dart';

/// Asks somebody to type a phrase back before an irreversible action.
///
/// Returns what they typed, or null if they backed out. Comparing it with
/// [phrase] is the caller's job — for account deletion that check belongs on
/// the server, and a dialog that decides locally would only be theatre.
///
/// Its own widget, and that is the whole point of the file. This used to be a
/// `TextEditingController` created next to `showDialog` and disposed in its
/// `whenComplete`, and it crashed the app: that future completes the moment the
/// route is popped, while the dialog spends another couple of hundred
/// milliseconds animating out, so the controller was disposed with its own
/// TextField still mounted and still reading it. What reached the screen was a
/// red page reading `'_dependents.isEmpty': is not true`, on the last
/// confirmation of an action there is no undo for, and whether or not what had
/// been typed was even correct.
///
/// A State ties the controller to the element that uses it, which is the one
/// lifetime that is always right. lib/settings/user_passkeys.dart carries a
/// comment about hitting the same thing and working around it by hoisting the
/// controller up to the page; this is the version that does not need the page
/// to know.
Future<String?> confirmByTyping(
  BuildContext context, {
  required String title,
  required String phrase,
  required String fieldLabel,
  required String confirmLabel,
}) => showDialog<String>(
  context: context,
  builder: (context) => ConfirmByTypingDialog(
    title: title,
    phrase: phrase,
    fieldLabel: fieldLabel,
    confirmLabel: confirmLabel,
  ),
);

class ConfirmByTypingDialog extends StatefulWidget {
  const ConfirmByTypingDialog({
    required this.title,
    required this.phrase,
    required this.fieldLabel,
    required this.confirmLabel,
    super.key,
  });

  final String title;

  /// What the reader is asked to type. Shown, never checked here.
  final String phrase;

  final String fieldLabel;
  final String confirmLabel;

  @override
  State<ConfirmByTypingDialog> createState() => _ConfirmByTypingDialogState();
}

class _ConfirmByTypingDialogState extends State<ConfirmByTypingDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Enter “${widget.phrase}” exactly.'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(labelText: widget.fieldLabel),
            // The keyboard's own action, for somebody who has just typed the
            // name and has the button below hidden behind the keyboard.
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        DestructiveButton(
          label: widget.confirmLabel,
          onPressed: () => Navigator.pop(context, _controller.text),
        ),
      ],
    );
  }
}
