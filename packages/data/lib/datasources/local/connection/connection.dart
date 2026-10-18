/// Conditional import: selects the right database connection factory
/// without importing dart:ffi on web builds.
library;
export 'connection_native.dart'
    if (dart.library.html) 'connection_web.dart';
