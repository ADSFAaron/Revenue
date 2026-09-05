import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';

import '../models/order_slip.dart';
import 'data_exception.dart';
import 'menu_import_repository.dart' show menuImportFunctionsRegion;

/// Must be at least `TIMEOUT_SECONDS` in functions/src/order_slip.ts.
const Duration orderSlipTimeout = Duration(seconds: 90);

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
/// **A `Future`, not a stream, unlike the menu reader.** That one routinely
/// runs past a minute and needed to say what it was doing or people backed out
/// of a call that was about to succeed. This one is bounded at forty-five
/// seconds on the server and usually answers in ten, because it is used at a
/// counter with somebody waiting — and a progress checklist for a wait that
/// short is more to read than the wait is to sit through.
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

  Future<SlipReading> read(List<SlipPhoto> photos) async {
    if (photos.isEmpty) {
      throw const SlipReadException('Take a photo of the slip first.');
    }

    final callable = _functions.httpsCallable(
      'readOrderSlip',
      options: HttpsCallableOptions(timeout: orderSlipTimeout),
    );

    try {
      final result = await callable.call<Object?>({
        'photos': [
          for (final photo in photos)
            {'mimeType': photo.mimeType, 'data': base64Encode(photo.bytes)},
        ],
      });
      return _reading(_asMap(result.data));
    } on FirebaseFunctionsException catch (e) {
      throw _translate(e);
    }
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
      'unauthenticated' => SlipReadException(
          'Sign in before reading a slip.',
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
