import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/database/repositories.dart';
import 'package:Revenue/database/session_resolver.dart';
import 'package:Revenue/models/app_user.dart';
import 'package:Revenue/models/store.dart';

const _patience = Duration(milliseconds: 60);

AppUser userWith(String uid) => AppUser(
      uid: uid,
      email: 'owner@example.com',
      displayName: 'Owner',
      storeId: 'store-1',
      role: UserRole.owner,
    );

Session sessionFor(AppUser user) =>
    Session(user: user, store: Store(id: user.storeId, name: 'Shop'));

void main() {
  test('a session that resolves at once is never a failure', () async {
    final changes = StreamController<AppUser?>();
    final resolver = SessionResolver(
      changes: changes.stream,
      load: () async => sessionFor(userWith('u1')),
      patience: _patience,
    );

    await Future<void>.delayed(Duration.zero);
    expect(resolver.session, isNotNull);
    expect(resolver.reportableFailure, isNull);

    await changes.close();
    resolver.dispose();
  });

  test('the document landing late is what makes it look again', () async {
    // The bug this replaced, exactly. Registration signs the account in before
    // it writes the user document, so the first read legitimately finds
    // nothing. The old gate resolved once, failed, and held that failure until
    // the app was killed.
    final changes = StreamController<AppUser?>();
    var provisioned = false;
    var reads = 0;

    final resolver = SessionResolver(
      changes: changes.stream,
      load: () async {
        reads++;
        if (!provisioned) {
          throw const SessionException('has no profile document yet');
        }
        return sessionFor(userWith('u1'));
      },
      patience: _patience,
    );

    await Future<void>.delayed(Duration.zero);
    expect(resolver.session, isNull);
    expect(reads, 1);

    // Registration writes the document. The watch is the only signal.
    provisioned = true;
    changes.add(userWith('u1'));
    await Future<void>.delayed(Duration.zero);

    expect(resolver.session, isNotNull);
    expect(resolver.reportableFailure, isNull);

    await changes.close();
    resolver.dispose();
  });

  test('a failure inside the grace period is never shown', () async {
    final changes = StreamController<AppUser?>();
    final resolver = SessionResolver(
      changes: changes.stream,
      load: () async => throw const SessionException('not yet'),
      patience: _patience,
    );

    await Future<void>.delayed(Duration.zero);
    // Failed, but a seconds-old account has not done anything wrong yet.
    expect(resolver.reportableFailure, isNull);

    await Future<void>.delayed(_patience * 2);
    expect(resolver.reportableFailure, isNotNull);

    await changes.close();
    resolver.dispose();
  });

  test('a document that lands after the message clears it', () async {
    // The screen is not a dead end: it corrects itself if the account is
    // provisioned while somebody is reading it.
    final changes = StreamController<AppUser?>();
    var provisioned = false;

    final resolver = SessionResolver(
      changes: changes.stream,
      load: () async {
        if (!provisioned) throw const SessionException('not yet');
        return sessionFor(userWith('u1'));
      },
      patience: _patience,
    );

    await Future<void>.delayed(_patience * 2);
    expect(resolver.reportableFailure, isNotNull);

    provisioned = true;
    changes.add(userWith('u1'));
    await Future<void>.delayed(Duration.zero);

    expect(resolver.session, isNotNull);
    expect(resolver.reportableFailure, isNull);

    await changes.close();
    resolver.dispose();
  });

  test('retry gives the answer the same grace it gave the first one', () async {
    final changes = StreamController<AppUser?>();
    var provisioned = false;
    final resolver = SessionResolver(
      changes: changes.stream,
      load: () async {
        if (!provisioned) throw const SessionException('not yet');
        return sessionFor(userWith('u1'));
      },
      patience: _patience,
    );

    await Future<void>.delayed(_patience * 2);
    expect(resolver.reportableFailure, isNotNull);

    provisioned = true;
    resolver.retry();
    // Silent again the moment it is asked, rather than showing the old message
    // underneath a fresh attempt.
    expect(resolver.reportableFailure, isNull);

    await Future<void>.delayed(Duration.zero);
    expect(resolver.session, isNotNull);

    await changes.close();
    resolver.dispose();
  });

  test('a slow early read cannot overwrite a later good one', () async {
    // Two reads overlap when the document lands while the first is still in
    // flight. The older one finishing last must not put its own answer back.
    final changes = StreamController<AppUser?>();
    final gate = Completer<void>();
    var first = true;

    final resolver = SessionResolver(
      changes: changes.stream,
      load: () async {
        if (first) {
          first = false;
          await gate.future;
          throw const SessionException('stale');
        }
        return sessionFor(userWith('u1'));
      },
      patience: _patience,
    );

    changes.add(userWith('u1'));
    await Future<void>.delayed(Duration.zero);
    expect(resolver.session, isNotNull);

    // Now let the first, older read fail.
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(resolver.session, isNotNull, reason: 'the stale answer won');

    await changes.close();
    resolver.dispose();
  });
}
