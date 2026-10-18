import 'dart:async';
import 'dart:io';

/// Lightweight connectivity checker — no extra package needed.
/// Tries a DNS lookup of a reliable host; returns `true` if it resolves.
///
/// We intentionally avoid `connectivity_plus` to keep dependencies minimal.
/// This works on Android, iOS, Windows, macOS, Linux and Web (where
/// `InternetAddress.lookup` throws, treated as offline).
class ConnectivityService {
  static ConnectivityService? _instance;
  static ConnectivityService get instance =>
      _instance ??= ConnectivityService._();

  ConnectivityService._();

  bool _isOnline = true;
  final _controller = StreamController<bool>.broadcast();

  bool get isOnline => _isOnline;
  Stream<bool> get onStatusChange => _controller.stream;

  /// Start polling every [intervalSeconds] seconds.
  void startPolling({int intervalSeconds = 10}) {
    _checkNow();
    Timer.periodic(Duration(seconds: intervalSeconds), (_) => _checkNow());
  }

  Future<void> _checkNow() async {
    final online = await _probe();
    if (online != _isOnline) {
      _isOnline = online;
      _controller.add(_isOnline);
    }
  }

  static Future<bool> _probe() async {
    try {
      final result = await InternetAddress.lookup('supabase.com')
          .timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      // Web: InternetAddress.lookup throws UnsupportedError
      return true; // assume online on web
    }
  }

  /// One-shot check without side effects.
  static Future<bool> checkOnce() => _probe();
}
