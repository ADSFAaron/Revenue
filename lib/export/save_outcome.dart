/// What happened when an export was written out.
///
/// A browser download and a file on a phone's storage are genuinely different
/// results — one has a path worth showing, the other does not — so the screen
/// is told which it got rather than being left to guess from the platform.
class SaveOutcome {
  const SaveOutcome.downloaded()
      : path = null,
        downloaded = true;

  const SaveOutcome.written(this.path) : downloaded = false;

  /// Where the file landed, on platforms that have a file system.
  final String? path;

  /// True when the browser was handed the file instead.
  final bool downloaded;

  String get description =>
      downloaded ? 'Downloaded' : 'Saved to ${path ?? 'storage'}';
}
