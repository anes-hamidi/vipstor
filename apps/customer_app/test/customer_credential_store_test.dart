import 'package:customer_app/services/customer_credential_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CustomerCredentialStore', () {
    test('saves, reads synchronously and clears remembered credentials',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final store = CustomerCredentialStore(prefs);

      await store.save(phone: ' 0550123456 ', password: 'secret123');

      final saved = await store.read();
      expect(saved, isNotNull);
      expect(saved!.phone, '0550123456');
      expect(saved.password, 'secret123');

      final sync = store.readSync();
      expect(sync, isNotNull);
      expect(sync!.phone, '0550123456');
      expect(sync.password, 'secret123');

      await store.clear();
      expect(await store.read(), isNull);
      expect(store.readSync(), isNull);
    });

    test('returns null when nothing has been remembered', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = CustomerCredentialStore(prefs);

      expect(await store.read(), isNull);
      expect(store.readSync(), isNull);
    });

    test('readSync stays null until SharedPreferences is available', () {
      final store = CustomerCredentialStore();

      expect(store.readSync(), isNull);
    });
  });
}
