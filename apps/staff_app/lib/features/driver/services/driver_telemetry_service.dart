import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DriverTelemetryState {
  final int batteryLevel;
  final BatteryState batteryState;
  final bool isWakelockEnabled;
  final bool isBackgroundServiceActive;
  final Position? currentPosition;
  final String? gpsError;

  const DriverTelemetryState({
    this.batteryLevel = 100,
    this.batteryState = BatteryState.unknown,
    this.isWakelockEnabled = false,
    this.isBackgroundServiceActive = false,
    this.currentPosition,
    this.gpsError,
  });

  bool get isLowBattery => batteryLevel < 20 && batteryState != BatteryState.charging;

  DriverTelemetryState copyWith({
    int? batteryLevel,
    BatteryState? batteryState,
    bool? isWakelockEnabled,
    bool? isBackgroundServiceActive,
    Position? currentPosition,
    String? gpsError,
  }) {
    return DriverTelemetryState(
      batteryLevel: batteryLevel ?? this.batteryLevel,
      batteryState: batteryState ?? this.batteryState,
      isWakelockEnabled: isWakelockEnabled ?? this.isWakelockEnabled,
      isBackgroundServiceActive: isBackgroundServiceActive ?? this.isBackgroundServiceActive,
      currentPosition: currentPosition ?? this.currentPosition,
      gpsError: gpsError ?? this.gpsError,
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
  DateTime? _lastSyncTime;

  void setDriverId(String? id) {
    if (_driverId != id) {
      _driverId = id;
      if (_driverId != null && _state.currentPosition != null) {
        _syncLocationToSupabase(_state.currentPosition!);
      }
    }
  }

  Future<void> _syncLocationToSupabase(Position pos) async {
    if (_driverId == null) return;
    try {
      await Supabase.instance.client.from('driver_locations').upsert({
        'driver_id': _driverId,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'heading': pos.heading,
        'speed': pos.speed,
        'battery_level': _state.batteryLevel,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
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
            distanceFilter: 10,
          ),
        ).listen((newPos) {
          _state = _state.copyWith(currentPosition: newPos);
          notifyListeners();

          // Throttle updates: at least every 5 seconds or whenever moved > 10m
          final now = DateTime.now();
          if (_lastSyncTime == null || now.difference(_lastSyncTime!).inSeconds >= 5) {
            _lastSyncTime = now;
            _syncLocationToSupabase(newPos);
          }
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
