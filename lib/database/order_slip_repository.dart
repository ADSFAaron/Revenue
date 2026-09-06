import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';

import '../models/order_slip.dart';
import 'data_exception.dart';
import 'menu_import_repository.dart' show menuImportFunctionsRegion;

/// Must be at least `TIMEOUT_SECONDS` in functions/src/order_slip.ts.
const Duration orderSlipTimeout = Duration(minutes: 4);

/// Something the reader said while it was working, or the reading it ended
/// with.
sealed class SlipEvent {
  const SlipEvent();
}

/// One line of "what is happening right now".
class SlipProgress extends SlipEvent {
  const SlipProgress(this.message, {this.detail});

  /// Plain words, for the person waiting.
  final String message;

  /// The model, the status, the attempt — for whoever is testing.
  final String? detail;
}

/// The slip, read. Always the last event, and there is exactly one.
class SlipRead extends SlipEvent {
  const SlipRead(this.reading);

  final SlipReading reading;
}

class SlipReadException implements AppException {
  const SlipReadException(this.message, {this.details});

  @override
  final String message;

  /// The technical half, for the screen to put behind "Details" — the model,
  /// the status, how long it took. Separate from [message] because the two are
  /// read by different people at different moments.
  final String? details;

  @override
  String toString() => details == null ? message : '$message ($details)';
}

/// Turning a photograph of a paper order slip into basket lines.
///
/// A stream, like the menu reader, and it shipped as a `Future` first.
///
/// The reasoning for the `Future` was that this runs at a counter with a
/// customer waiting, so it was bounded at forty-five seconds and a wait that
/// short needs no narration. The premise was wrong, and the shop owner said
/// so: when service is busy the slips *pile up* and get entered afterwards, in
/// a quiet half hour, precisely because there was no time to type them in
/// while it was busy. So the budget went up — and above about half a minute, a
/// spinner with nothing under it is indistinguishable from a hang, which is
/// how a call that was going to succeed gets abandoned, taking the photograph
/// with it.
///
/// It writes nothing and it decides nothing. The reading goes to a review
/// screen, and only what a person confirms there reaches the basket.
class OrderSlipRepository {
  OrderSlipRepository({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(region: menuImportFunctionsRegion);

  final FirebaseFunctions _functions;

  /// The most photographs one slip may be. Mirrors `MAX_PHOTOS` in the
  /// function, which is what actually enforces it.
  static const int maxPhotos = 2;

  Stream<SlipEvent> read(List<SlipPhoto> photos) async* {
    if (photos.isEmpty) {
      throw const SlipReadException('Take a photo of the slip first.');
    }

    final callable = _functions.httpsCallable(
      'readOrderSlip',
      options: HttpsCallableOptions(timeout: orderSlipTimeout),
    );

    // Said here rather than by the function, because the upload is the part
    // the function cannot see: by the time it can report anything, the bytes
    // have already arrived.
    yield const SlipProgress('Sending the photo');

    try {
      final responses = callable.stream({
        'photos': [
          for (final photo in photos)
            {'mimeType': photo.mimeType, 'data': base64Encode(photo.bytes)},
        ],
      });

      await for (final response in responses) {
        switch (response) {
          case Chunk(:final partialData):
            final progress = _progress(_asMap(partialData));
            if (progress != null) yield progress;
          case Result(:final result):
            yield SlipRead(_reading(_asMap(result.data)));
        }
      }
    } on FirebaseFunctionsException catch (e) {
      throw _translate(e);
    }
  }

  /// Turns one progress frame into a line somebody can read.
  ///
  /// The wording lives here rather than in the function because it is the
  /// app's vocabulary, not the server's — and because the server should be
  /// free to add a stage without shipping an app update to describe it. An
  /// unknown stage is dropped rather than shown raw.
  static SlipProgress? _progress(Map<String, dynamic> frame) {
    final model = frame['model'] as String?;
    final status = (frame['status'] as num?)?.toInt();

    return switch (frame['stage']) {
      'received' => const SlipProgress('Sent'),
      'reading' => SlipProgress('Reading the slip', detail: model),
      // The one frame that exists to stop somebody leaving. A step that has
      // visibly failed, with the next one already starting, is a wait with a
      // reason; the same seconds with nothing on screen are a hang.
      'busy' => SlipProgress(
          'That reader was busy — trying another',
          detail: [?model, if (status != null) 'HTTP $status'].join(' · '),
        ),
      'parsing' => const SlipProgress('Matching it against the menu'),
      _ => null,
    };
  }

  static SlipReading _reading(Map<String, dynamic> data) => SlipReading(
        lines: ((data['lines'] as List?) ?? const [])
            .map((row) => SlipLine.fromMap(_asMap(row)))
            .where((line) => line.itemId.isNotEmpty && line.qty > 0)
            .toList(),
        unreadable:
            ((data['unreadable'] as List?) ?? const []).whereType<String>().toList(),
        unmatched: (data['unmatched'] as num?)?.toInt() ?? 0,
      );

  static Map<String, dynamic> _asMap(Object? value) => value is Map
      ? value.map((key, val) => MapEntry('$key', val))
      : const <String, dynamic>{};

  SlipReadException _translate(FirebaseFunctionsException e) {
    final details = [
      e.code,
      if (e.details is Map) '${(e.details as Map)['model'] ?? ''}',
    ].where((part) => part.isNotEmpty).join(' · ');

    return switch (e.code) {
      // Almost never what it sounds like. The caller is signed in — the app
      // would not have got this far otherwise — so `unauthenticated` out of a
      // callable is App Check refusing the request, and telling somebody to
      // sign in sends them round a loop that cannot help. This app has been
      // here before; see the same wording in auth_repository.
      'unauthenticated' => SlipReadException(
          'The app could not prove which app it is. This is usually a debug '
          'build whose App Check token is not registered — see '
          'tool/register_debug_token.sh. If this is a store build, sign in '
          'again and retry.',
          details: details,
        ),
      'permission-denied' => SlipReadException(
          e.message ?? 'You do not have access to this shop.',
          details: details,
        ),
      // The function says this when the shop has no menu, or a menu too long
      // to match against. Both have a specific sentence and neither is worth
      // flattening.
      'failed-precondition' => SlipReadException(
          e.message ?? 'This shop\'s menu cannot be matched against.',
          details: details,
        ),
      'invalid-argument' => SlipReadException(
          e.message ?? 'That photo could not be sent.',
          details: details,
        ),
      'resource-exhausted' => SlipReadException(
          e.message ?? 'The slip reader is busy. Ring this one up by hand.',
          details: details,
        ),
      'deadline-exceeded' => SlipReadException(
          e.message ??
              'Reading the slip took too long. Ring it up by hand — that is '
                  'faster than trying again.',
          details: details,
        ),
      'not-found' => SlipReadException(
          'The slip reader is not deployed. Run '
          '`firebase deploy --only functions`.',
          details: details,
        ),
      'unavailable' => SlipReadException(
          'Could not reach the slip reader. Check your network.',
          details: details,
        ),
      _ => SlipReadException(
          e.message ?? 'The slip reader failed (${e.code}).',
          details: details,
        ),
    };
  }
}

/// A photograph on its way to the reader.
class SlipPhoto {
  const SlipPhoto({required this.bytes, required this.mimeType});

  final Uint8List bytes;

  /// JPEG, PNG or WebP — the function rejects anything else.
  final String mimeType;
}
