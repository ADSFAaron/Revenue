/// Writing an arbitrary file out, resolved per platform at compile time.
///
/// Same shape and the same reason as [saveWorkbook], which predates it and is
/// now one caller of it: the web build must never see `dart:io` and the mobile
/// build must never see the browser download path.
library;

export 'save_outcome.dart';
export 'file_saver_stub.dart'
    if (dart.library.io) 'file_saver_io.dart'
    if (dart.library.js_interop) 'file_saver_web.dart';
