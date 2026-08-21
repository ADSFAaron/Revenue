/// Saving an [Excel] workbook, resolved per platform at compile time.
///
/// The web build must never see `dart:io` and the mobile build must never see
/// the browser download path, so the two implementations are selected here
/// rather than branched on at runtime.
library;

export 'save_outcome.dart';
export 'workbook_saver_stub.dart'
    if (dart.library.io) 'workbook_saver_io.dart'
    if (dart.library.js_interop) 'workbook_saver_web.dart';
