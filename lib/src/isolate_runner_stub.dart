/// Non-io fallback (Flutter Web): isolates are unavailable, so run the
/// computation inline on the calling isolate.
Future<R> runIsolated<R>(Future<R> Function() computation) => computation();
