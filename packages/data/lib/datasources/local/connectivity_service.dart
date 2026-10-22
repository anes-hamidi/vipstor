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
  bool _started = false;
  bool _checking = false;
  Timer? _timer;
  final _controller = StreamController<bool>.broadcast();

  bool get isOnline => _isOnline;
  Stream<bool> get onStatusChange => _controller.stream;

  /// Start polling every [intervalSeconds] seconds.
  ///
  /// Safe to call multiple times: an existing timer is reused instead of
  /// stacking duplicate pollers (which used to happen whenever the app
  /// re-initialised the providers).
  void startPolling({int intervalSeconds = 10}) {
    if (_started) {
      // Still make sure we have a fresh value for late subscribers.
      unawaited(refreshNow());
      return;
    }
    _started = true;
    unawaited(refreshNow());
    _timer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => unawaited(refreshNow()),
    );
  }

  /// Stop polling and release the timer. The service can be restarted later.
  void stopPolling() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  /// Force an immediate connectivity probe.
  ///
  /// Overlapping probes are collapsed: several providers asking for a refresh
  /// at the same time will share a single DNS lookup.
  Future<void> refreshNow() async {
    if (_checking) return;
    _checking = true;
    try {
      final online = await _probe();
      if (online != _isOnline) {
        _isOnline = online;
        if (!_controller.isClosed) _controller.add(_isOnline);
      }
    } finally {
      _checking = false;
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
      // Web: InternetAddress.lookup throws UnsupportedError.
      // Assume online so we still attempt the request; failures fall back to
      // the cached data path.
      return true;
    }
  }

  /// One-shot check without side effects.
  static Future<bool> checkOnce() => _probe();
}
