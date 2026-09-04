import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import 'repositories.dart';

/// Works out when the signed-in shell may be shown, and when a failure is worth
/// reporting.
///
/// Separated from the widget because the bug this exists to prevent was
/// entirely a question of timing, and timing is the one thing a widget holding
/// a `late final Future` cannot be asked about.
///
/// What went wrong: registration signs the account in *before* it writes the
/// user document. The gate resolved its session once, at the moment the account
/// signed in, retried five times over a second and a half, failed, and then
/// held that failure for the life of the widget. Finishing registration landed
/// on "this account has no profile document yet" and stayed there until the app
/// was killed.
///
/// Two things fix it, and both are here:
///
///  * The user's own document is watched, so the write that creates it is what
///    triggers another look. There is no window left to get wrong, and no retry
///    count to tune.
///  * A failure is held quietly for [patience] before it is shown. For a
///    seconds-old account "no profile" is the ordinary state rather than a
///    fault, and if the document lands during that window the reader never
///    learns there was a question.
class SessionResolver extends ChangeNotifier {
  SessionResolver({
    required Stream<AppUser?> changes,
    required this.load,
    this.patience = const Duration(seconds: 5),
  }) {
    _watch = changes.listen((_) => _resolve(), onError: _fail);
    _resolve();
    _startPatience();
  }

  /// How a session is read. Injected so the timing above can be tested without
  /// a Firebase project behind it.
  final Future<Session> Function() load;
  final Duration patience;

  late final StreamSubscription<AppUser?> _watch;
  Timer? _timer;

  Session? _session;
  Object? _failure;
  bool _patienceSpent = false;

  /// Only the newest attempt may write a result. Two can overlap — the document
  /// lands while an earlier read is still in flight — and the older one
  /// finishing last would put its own answer back.
  int _attempt = 0;

  Session? get session => _session;

  /// The failure to put on screen, or null while there is nothing to say.
  ///
  /// Null both when things are fine and when they are not yet known to be
  /// otherwise; [session] is what distinguishes those.
  Object? get reportableFailure =>
      _patienceSpent && _session == null ? _failure : null;

  void _startPatience() {
    _timer?.cancel();
    _timer = Timer(patience, () {
      _patienceSpent = true;
      notifyListeners();
    });
  }

  Future<void> _resolve() async {
    final mine = ++_attempt;
    try {
      final session = await load();
      if (mine != _attempt || _disposed) return;
      _session = session;
      _failure = null;
      notifyListeners();
    } catch (error) {
      if (mine != _attempt || _disposed) return;
      _failure = error;
      notifyListeners();
    }
  }

  void _fail(Object error) {
    if (_disposed) return;
    _failure = error;
    notifyListeners();
  }

  /// Asks again, and gives the answer the same grace it got the first time.
  void retry() {
    _failure = null;
    _patienceSpent = false;
    notifyListeners();
    _startPatience();
    _resolve();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _watch.cancel();
    _timer?.cancel();
    super.dispose();
  }
}
