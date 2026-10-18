import 'package:drift/drift.dart';
import 'package:drift/web.dart';

/// Web connection: uses IndexedDB via drift's web database.
/// No dart:ffi — safe on Chrome.
QueryExecutor openAppDbConnection() {
  return WebDatabase('vip_local', logStatements: false);
}
