import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Throttling thresholds for driver GPS uploads.
/// - Minimum time between location uploads: 60 seconds
/// - Minimum distance change before upload: 50 meters
/// These reduce write amplification vs. the previous 5s / 10m policy.
class _TelemetryThrottle {
  static const Duration minUploadInterval = Duration(seconds: 60);
  static const double minDistanceMeters = 50.0;
}

class DriverTelemetryState {
  final int batteryLevel;
  final BatteryState batteryState;
  final bool isWakelockEnabled;
  final bool isBackgroundServiceActive;
  final Position? currentPosition;
  final String? gpsError;
  final bool isTripActive;
  final bool isClockedIn;

  const DriverTelemetryState({
    this.batteryLevel = 100,
    this.batteryState = BatteryState.unknown,
    this.isWakelockEnabled = false,
    this.isBackgroundServiceActive = false,
    this.currentPosition,
    this.gpsError,
    this.isTripActive = false,
    this.isClockedIn = false,
  });

  bool get isLowBattery => batteryLevel < 20 && batteryState != BatteryState.charging;

  DriverTelemetryState copyWith({
    int? batteryLevel,
    BatteryState? batteryState,
    bool? isWakelockEnabled,
    bool? isBackgroundServiceActive,
    Position? currentPosition,
    String? gpsError,
    bool? isTripActive,
    bool? isClockedIn,
  }) {
    return DriverTelemetryState(
      batteryLevel: batteryLevel ?? this.batteryLevel,
      batteryState: batteryState ?? this.batteryState,
      isWakelockEnabled: isWakelockEnabled ?? this.isWakelockEnabled,
      isBackgroundServiceActive: isBackgroundServiceActive ?? this.isBackgroundServiceActive,
      currentPosition: currentPosition ?? this.currentPosition,
      gpsError: gpsError ?? this.gpsError,
      isTripActive: isTripActive ?? this.isTripActive,
      isClockedIn: isClockedIn ?? this.isClockedIn,
    );
  }
}

class DriverTelemetryService extends ChangeNotifier {
  static final DriverTelemetryService _instance = DriverTelemetryService._internal();
  factory DriverTelemetryService() => _instance;

  DriverTelemetryService._internal() {
    _initBattery();
    _initGps();
  }

  final Battery _battery = Battery();
  DriverTelemetryState _state = const DriverTelemetryState();
  DriverTelemetryState get state => _state;

  StreamSubscription<BatteryState>? _batterySubscription;
  StreamSubscription<Position>? _positionSubscription;

  String? _driverId;
  DateTime? _lastLocationUpload;
  Position? _lastUploadedPosition;

  void setDriverId(String? id) {
    if (_driverId != id) {
      _driverId = id;
      if (_driverId != null && _state.currentPosition != null) {
        _syncLocationToSupabase(_state.currentPosition!);
      }
    }
  }

  /// Clock the driver in (shift start). Logs a clock_in event.
  Future<void> clockIn() async {
    if (_driverId == null) return;
    _state = _state.copyWith(isClockedIn: true);
    notifyListeners();
    await _logDriverLocationEvent('clock_in');
  }

  /// Clock the driver out (shift end). Logs a clock_out event.
  Future<void> clockOut() async {
    if (_driverId == null) return;
    _state = _state.copyWith(isClockedIn: false);
    notifyListeners();
    await _logDriverLocationEvent('clock_out');
  }

  /// Start a delivery trip. Logs a trip_start event.
  Future<void> startTrip() async {
    if (_driverId == null) return;
    _state = _state.copyWith(isTripActive: true);
    notifyListeners();
    await _logDriverLocationEvent('trip_start');
  }

  /// End a delivery trip. Logs a trip_end event.
  Future<void> endTrip() async {
    if (_driverId == null) return;
    _state = _state.copyWith(isTripActive: false);
    notifyListeners();
    await _logDriverLocationEvent('trip_end');
  }

  Future<void> _syncLocationToSupabase(Position pos) async {
    if (_driverId == null) return;

    // Throttle: respect minimum time interval
    final now = DateTime.now();
    if (_lastLocationUpload != null &&
        now.difference(_lastLocationUpload!) < _TelemetryThrottle.minUploadInterval) {
      return;
    }

    // Throttle: respect minimum distance delta
    if (_lastUploadedPosition != null) {
      final distance = Geolocator.distanceBetween(
        _lastUploadedPosition!.latitude,
        _lastUploadedPosition!.longitude,
        pos.latitude,
        pos.longitude,
      );
      if (distance < _TelemetryThrottle.minDistanceMeters) {
        return;
      }
    }

    try {
      await Supabase.instance.client.rpc('rpc_update_driver_location', params: {
        'p_driver_id': _driverId,
        'p_latitude': pos.latitude,
        'p_longitude': pos.longitude,
        'p_heading': pos.heading,
        'p_speed': pos.speed,
        'p_battery_level': _state.batteryLevel,
      });

      _lastLocationUpload = now;
      _lastUploadedPosition = pos;
    } catch (_) {
      // Swallow upload errors; telemetry is best-effort.
    }
  }

  /// Log a significant driver location event to driver_location_events.
  /// This is audited (via trigger) and retained for compliance.
  Future<void> _logDriverLocationEvent(String eventType) async {
    if (_driverId == null) return;
    final pos = _state.currentPosition;
    try {
      await Supabase.instance.client
          .rpc('rpc_log_driver_location_event', params: {
        'p_event_type': eventType,
        'p_latitude': pos?.latitude,
        'p_longitude': pos?.longitude,
      });
    } catch (_) {
      // Event logging is best-effort; must not break the driver flow.
    }
  }

  Future<void> _initBattery() async {
    try {
      final level = await _battery.batteryLevel;
      _state = _state.copyWith(batteryLevel: level);
      notifyListeners();

      _batterySubscription = _battery.onBatteryStateChanged.listen((batteryState) async {
        final currentLevel = await _battery.batteryLevel;
        _state = _state.copyWith(batteryLevel: currentLevel, batteryState: batteryState);
        notifyListeners();
        if (_state.currentPosition != null) {
          _syncLocationToSupabase(_state.currentPosition!);
        }
      });
    } catch (_) {}
  }

  Future<void> _initGps() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
        _state = _state.copyWith(currentPosition: pos);
        notifyListeners();
        _syncLocationToSupabase(pos);

        _positionSubscription = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 50, // only emit when moved 50m+
          ),
        ).listen((newPos) {
          _state = _state.copyWith(currentPosition: newPos);
          notifyListeners();

          // Throttled sync: respects min interval + min distance delta
          _syncLocationToSupabase(newPos);
        });
      }
    } catch (e) {
      _state = _state.copyWith(gpsError: e.toString());
      notifyListeners();
    }
  }

  Future<void> toggleWakelock(bool enable) async {
    try {
      await WakelockPlus.toggle(enable: enable);
      _state = _state.copyWith(isWakelockEnabled: enable);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggleBackgroundTracking(bool enable) async {
    try {
      final service = FlutterBackgroundService();
      if (enable) {
        final isRunning = await service.isRunning();
        if (!isRunning) {
          await service.startService();
        }
      } else {
        service.invoke("stopService");
      }
      _state = _state.copyWith(isBackgroundServiceActive: enable);
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _batterySubscription?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }
}
