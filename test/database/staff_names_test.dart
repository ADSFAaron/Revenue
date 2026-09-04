import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/database/repositories.dart';
import 'package:Revenue/models/audit_log.dart';

/// What an order or an audit entry says about who did it, once the uid on it
/// is turned back into a person.
///
/// The case worth pinning is the one that does not resolve. Account deletion
/// removes the person's user document and leaves their orders behind — those
/// are the shop's books, not theirs — so a uid pointing at nobody is the
/// expected end state of an ordinary resignation, and it has to read as a
/// sentence rather than as a blank, a raw uid, or a crash.
void main() {
  const names = StaffNames({'uid-1': 'Ming', 'uid-2': 'Mei'});

  group('StaffNames', () {
    test('a uid it knows reads as that person', () {
      expect(names.labelFor('uid-1'), 'Ming');
    });

    test('a uid belonging to a deleted account reads as former staff', () {
      expect(names.labelFor('uid-gone'), 'Former staff');
    });

    test('no uid at all is a different thing from a departed one', () {
      // Orders taken before `createdBy` existed, and offline orders queued
      // before that path stamped one.
      expect(names.labelFor(null), 'Not recorded');
      expect(names.labelFor(''), 'Not recorded');
    });

    test('knows() separates the two so a caller can fall back', () {
      expect(names.knows('uid-1'), isTrue);
      expect(names.knows('uid-gone'), isFalse);
      expect(names.knows(null), isFalse);
    });

    test('an empty directory never throws, it just knows nobody', () {
      expect(const StaffNames.empty().labelFor('uid-1'), 'Former staff');
    });
  });

  group('AuditLog.summaryBy', () {
    const entry = AuditLog(
      id: 'a1',
      action: AuditAction.voidOrder,
      byUid: 'uid-1',
      byName: 'Ming',
    );

    test('prefers the name the store has now, so a rename carries', () {
      expect(entry.summaryBy('Ming Chen'), startsWith('Ming Chen '));
    });

    test('falls back to the name recorded at the time', () {
      // The only case where the copy on the document beats a lookup: the
      // account is gone, so there is nothing left to look up, and "Former
      // staff voided an order" throws away the one record of who it was.
      expect(entry.summaryBy(null), startsWith('Ming '));
    });

    test('and to something readable when neither exists', () {
      const anonymous = AuditLog(id: 'a2', action: AuditAction.voidOrder);
      expect(anonymous.summaryBy(null), startsWith('Someone '));
    });
  });
}
