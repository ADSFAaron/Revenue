import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Whether the app is reading live data or the offline cache.
///
/// Persistence is on (see `configureFirestore`), which is what keeps a shop
/// working through a dropped connection — but it also means a lost connection
/// now looks like nothing at all. Yesterday's takings sit on screen with no
/// hint they are stale, which for a page whose whole purpose is today's number
/// is worse than an error.
///
/// One dedicated listener rather than metadata threaded through every
/// repository, for a reason that is easy to miss: `snapshots()` defaults to
/// `includeMetadataChanges: false`, so when the client reconnects and the
/// document has not changed, **no further snapshot arrives** — a flag driven
/// off the existing streams would latch to "offline" and stay there. This one
/// asks for metadata changes explicitly.
///
/// It watches the signed-in user's own document: it always exists, it is one
/// document, it is already readable under the rules, and it is needed before
/// any store is known.
class ConnectionStatus extends ValueNotifier<bool> {
  ConnectionStatus() : super(false);

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  String? _uid;

  /// True when the last snapshot came from the cache rather than the server.
  bool get isOffline => value;

  void watch(String uid) {
    if (_uid == uid && _sub != null) return;
    _uid = uid;
    _sub?.cancel();
    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) => value = snapshot.metadata.isFromCache,
          // A listener that errors says nothing about connectivity — the
          // screens have their own error handling for that.
          onError: (_) {},
        );
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _uid = null;
    value = false;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final connectionStatus = ConnectionStatus();
