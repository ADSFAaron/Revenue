import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/database/order_slip_repository.dart';


/// Photographing a paper slip into the basket.
///
/// The camera itself cannot be driven from a test process, and neither can the
/// model behind the callable — what runs on the far side is tested in
/// `functions/test/order_slip.test.js`, where the closed-set match that stops
/// the model inventing a dish lives. What is ours, and what is here, is the
/// two ends: turning the callable's stream into something a person can read
/// and act on, and what happens to the basket afterwards.
///
/// The stream matters more than it looks. This call can take minutes — slips
/// pile up during service and get entered afterwards — and above about half a
/// minute a spinner with nothing under it is indistinguishable from a hang,
/// which is how a call that was going to succeed gets abandoned, taking the
/// photograph with it. Every progress frame is therefore a thing somebody
/// decided not to give up on.
void main() {
  final photo = SlipPhoto(
    bytes: Uint8List.fromList([1, 2, 3]),
    mimeType: 'image/jpeg',
  );

  group('reading a slip', () {
    test('the photo goes up as base64, tagged with its type', () async {
      // Named rather than sniffed: the function rejects anything that is not
      // one of three types, and a wrong guess is a rejection nobody can act on.
      final functions = _FakeFunctions([
        Result(_result({'lines': const []})),
      ]);
      final reader = OrderSlipRepository(functions: functions);

      await reader.read([photo]).toList();

      final sent = functions.lastRequest!['photos'] as List;
      expect(sent, hasLength(1));
      expect((sent.single as Map)['mimeType'], 'image/jpeg');
      expect((sent.single as Map)['data'], base64Encode([1, 2, 3]));
      expect(functions.lastName, 'readOrderSlip');
    });

    test('with no photo it does not call anything at all', () async {
      final functions = _FakeFunctions([]);
      final reader = OrderSlipRepository(functions: functions);

      await expectLater(
        reader.read([]).toList(),
        throwsA(isA<SlipReadException>()),
      );
      expect(functions.lastName, isNull);
    });

    test('says it is sending before the function can say anything', () async {
      // The upload is the part the function cannot narrate: by the time it can
      // report anything, the bytes have already arrived.
      final functions = _FakeFunctions([
        Result(_result({'lines': const []})),
      ]);
      final reader = OrderSlipRepository(functions: functions);

      final events = await reader.read([photo]).toList();

      expect(events.first, isA<SlipProgress>());
      expect((events.first as SlipProgress).message, 'Sending the photo');
    });

    test('turns each stage into a line somebody can read', () async {
      final functions = _FakeFunctions([
        Chunk(const {'stage': 'received'}),
        Chunk(const {'stage': 'reading', 'model': 'flash'}),
        Chunk(const {'stage': 'parsing'}),
        Result(_result({
          'lines': [
            {'itemId': 'noodles', 'qty': 2},
          ],
        })),
      ]);
      final reader = OrderSlipRepository(functions: functions);

      final events = await reader.read([photo]).toList();
      final messages =
          events.whereType<SlipProgress>().map((p) => p.message).toList();

      expect(messages, [
        'Sending the photo',
        'Sent',
        'Reading the slip',
        'Matching it against the menu',
      ]);
    });

    test('a reader that gave up says so, with the next one already starting',
        () async {
      // The one frame that exists to stop somebody walking away. A step that
      // has visibly failed with the next already going is a wait with a
      // reason; the same seconds with nothing on screen are a hang.
      final functions = _FakeFunctions([
        Chunk(const {'stage': 'busy', 'model': 'pro', 'status': 503}),
        Result(_result({'lines': const []})),
      ]);
      final reader = OrderSlipRepository(functions: functions);

      final events = await reader.read([photo]).toList();
      final busy = events.whereType<SlipProgress>().last;

      expect(busy.message, 'That reader was busy — trying another');
      expect(busy.detail, contains('pro'));
      expect(busy.detail, contains('503'));
    });

    test('a stage this build has never heard of is dropped, not shown raw',
        () async {
      // So the server can add one without an app update inventing wording for
      // it — and without putting a machine word in front of a shop worker.
      final functions = _FakeFunctions([
        Chunk(const {'stage': 'reticulating_splines'}),
        Result(_result({'lines': const []})),
      ]);
      final reader = OrderSlipRepository(functions: functions);

      final messages = (await reader.read([photo]).toList())
          .whereType<SlipProgress>()
          .map((p) => p.message);

      expect(messages, ['Sending the photo']);
    });

    test('the reading comes out last, and exactly once', () async {
      final functions = _FakeFunctions([
        Chunk(const {'stage': 'reading'}),
        Result(_result({
          'lines': [
            {'itemId': 'noodles', 'qty': 2},
            {'itemId': 'rice', 'qty': 1, 'sure': false},
          ],
          'unreadable': ['squiggle'],
          'unmatched': 1,
        })),
      ]);
      final reader = OrderSlipRepository(functions: functions);

      final events = await reader.read([photo]).toList();

      expect(events.whereType<SlipRead>(), hasLength(1));
      expect(events.last, isA<SlipRead>());

      final reading = (events.last as SlipRead).reading;
      expect(reading.lines.map((l) => (l.itemId, l.qty)), [
        ('noodles', 2),
        ('rice', 1),
      ]);
      expect(reading.unreadable, ['squiggle']);
      expect(reading.unmatched, 1);
    });

    test('a line with no dish or no quantity never reaches the basket',
        () async {
      // The model produced it, so it is exactly the kind of thing that must
      // not be trusted through to a screen that adds money to an order.
      final functions = _FakeFunctions([
        Result(_result({
          'lines': [
            {'itemId': '', 'qty': 3},
            {'itemId': 'noodles', 'qty': 0},
            {'itemId': 'rice', 'qty': 2},
          ],
        })),
      ]);
      final reader = OrderSlipRepository(functions: functions);

      final events = await reader.read([photo]).toList();
      final reading = (events.last as SlipRead).reading;

      expect(reading.lines.map((l) => l.itemId), ['rice']);
    });

    test('a response that is not the shape it asked for is an empty reading, '
        'not a crash', () async {
      final functions = _FakeFunctions([
        Result(_result('nonsense')),
      ]);
      final reader = OrderSlipRepository(functions: functions);

      final events = await reader.read([photo]).toList();
      final reading = (events.last as SlipRead).reading;

      expect(reading.lines, isEmpty);
      expect(reading.isEmpty, isTrue);
    });
  });

  group('when the reader refuses', () {
    Future<SlipReadException> failureFrom(String code, {String? message}) async {
      final functions = _FakeFunctions(
        [],
        error: message == null
            ? _SilentFailure(code)
            : FirebaseFunctionsException(code: code, message: message),
      );
      final reader = OrderSlipRepository(functions: functions);
      try {
        await reader.read([photo]).toList();
      } on SlipReadException catch (e) {
        return e;
      }
      fail('the failure did not come out as a SlipReadException');
    }

    test('App Check is not "please sign in"', () async {
      // The caller is signed in — the app could not have got here otherwise —
      // so `unauthenticated` from a callable is App Check refusing the
      // request. Telling somebody to sign in sends them round a loop that
      // cannot help. This app has been here before.
      final failure = await failureFrom('unauthenticated');

      expect(failure.message, contains('App Check'));
      expect(failure.message, isNot(contains('sign in again and retry\n')));
      expect(failure.details, contains('unauthenticated'));
    });

    test('a reader that is not deployed says which command deploys it',
        () async {
      final failure = await failureFrom('not-found');

      expect(failure.message, contains('firebase deploy'));
    });

    test('a timeout tells the till to ring it up by hand', () async {
      // The honest advice at a counter with somebody waiting: retrying costs
      // another four minutes.
      final failure = await failureFrom('deadline-exceeded');

      expect(failure.message, contains('by hand'));
      expect(failure.details, contains('deadline-exceeded'));
    });

    test('the function\'s own sentence is kept when it has one', () async {
      // `failed-precondition` is what it says when the shop has no menu, or a
      // menu too long to match against. Both have a specific sentence and
      // neither is worth flattening.
      final failure = await failureFrom(
        'failed-precondition',
        message: 'This shop has no menu to match against.',
      );

      expect(failure.message, 'This shop has no menu to match against.');
    });

    test('an unknown code still comes out as a sentence', () async {
      final failure = await failureFrom('teapot');

      expect(failure.message, isNotEmpty);
      expect(failure.toString(), contains('teapot'));
    });
  });

}

HttpsCallableResult<dynamic> _result(Object? data) =>
    _FakeResult<dynamic>(data);

/// Stands in for the `readOrderSlip` callable.
///
/// It records what it was handed — the request shape is half of what this file
/// checks — and replays a scripted stream, which is the only way to exercise
/// the progress frames without a four-minute model call behind them.
class _FakeFunctions implements FirebaseFunctions {
  _FakeFunctions(this.events, {this.error});

  final List<StreamResponse<dynamic, dynamic>> events;
  final FirebaseFunctionsException? error;

  String? lastName;
  Map<String, dynamic>? lastRequest;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    lastName = name;
    return _FakeCallable(this);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '${invocation.memberName} is not modelled by the slip fake.',
      );
}

class _FakeCallable implements HttpsCallable {
  _FakeCallable(this.functions);

  final _FakeFunctions functions;

  @override
  Stream<StreamResponse<T, R>> stream<T, R>([Object? input]) async* {
    functions.lastRequest = (input as Map).cast<String, dynamic>();
    if (functions.error != null) throw functions.error!;
    for (final event in functions.events) {
      yield event as StreamResponse<T, R>;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '${invocation.memberName} is not modelled by the slip fake.',
      );
}

/// A failure the platform gave no message with.
///
/// `FirebaseFunctionsException` requires one, but `FirebaseException.message`
/// is nullable and `_translate` has a fallback sentence for every code — this
/// is what exercises those fallbacks rather than echoing a message back.
class _SilentFailure extends FirebaseFunctionsException {
  _SilentFailure(String code) : super(code: code, message: '');

  @override
  String? get message => null;
}

class _FakeResult<T> implements HttpsCallableResult<T> {
  _FakeResult(this.data);

  @override
  final T data;
}
