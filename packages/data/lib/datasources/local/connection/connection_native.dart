import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Native connection: file-backed SQLite via dart:ffi.
/// Used on Android, iOS, Windows, macOS, Linux.
QueryExecutor openAppDbConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'vip_local.db'));
    return NativeDatabase.createInBackground(file);
  });
}
