import 'package:flutter/material.dart';

import 'feedback.dart';

/// Asks somebody to type a phrase back before an irreversible action.
///
/// Returns what they typed, or null if they backed out. The confirm button
/// stays disabled until it matches [phrase], so a mistyped name is answered on
/// the spot instead of by a round trip — which is what happened, and the round
/// trip came back "Your session expired" because App Check had rejected the
/// call long before anything looked at the name. From the counter that reads as
/// nothing having checked at all.
///
/// The real guard is still the server's: functions/src/account.ts compares the
/// name against the store document, and it has to, because a client can be
/// made to say anything. This is the half that belongs in front of a person.
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

  /// What the reader is asked to type.
  final String phrase;

  final String fieldLabel;
  final String confirmLabel;

  @override
  State<ConfirmByTypingDialog> createState() => _ConfirmByTypingDialogState();
}

class _ConfirmByTypingDialogState extends State<ConfirmByTypingDialog> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTyped);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTyped)
      ..dispose();
    super.dispose();
  }

  void _onTyped() => setState(() {});

  /// Trimmed on both sides: a name copied off a sign carries a trailing space
  /// more often than it carries a typo, and the server trims too.
  bool get _matches => _controller.text.trim() == widget.phrase.trim();

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
            onSubmitted: (value) {
              if (_matches) Navigator.pop(context, value);
            },
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
          onPressed: _matches
              ? () => Navigator.pop(context, _controller.text)
              : null,
        ),
      ],
    );
  }
}
