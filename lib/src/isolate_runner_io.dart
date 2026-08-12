import 'dart:isolate';

/// Runs [computation] on a short-lived isolate.
///
/// The closure must only capture sendable values (strings, bools, etc.).
Future<R> runIsolated<R>(Future<R> Function() computation) =>
    Isolate.run(computation);
