import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

enum GpsStatus {
  searching,
  fixed,
  denied,
  deniedForever,
  disabled,
}

class GpsService extends ChangeNotifier {
  Position? _currentPosition;
  GpsStatus _status = GpsStatus.searching;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<UserAccelerometerEvent>? _accelSubscription;
  Timer? _gpsSleepTimer;
  Timer? _periodicWakeTimer;
  bool _isManual = false;
  bool _isTrackingActive = false;

  Position? get currentPosition => _currentPosition;
  GpsStatus get status => _status;
  bool get isManual => _isManual;

  bool get hasFix => _currentPosition != null && (_status == GpsStatus.fixed || _isManual);

  GpsService() {
    _init();
  }

  void setManualLocation(double lat, double lon) {
    _isManual = true;
    _currentPosition = Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );
    notifyListeners();
  }

  void clearManual() {
    _isManual = false;
    notifyListeners();
  }

  Future<void> _init() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _status = GpsStatus.disabled;
      notifyListeners();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _status = GpsStatus.denied;
        notifyListeners();
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _status = GpsStatus.deniedForever;
      notifyListeners();
      return;
    }

    // Immediate last known position for quick startup
    _currentPosition = await Geolocator.getLastKnownPosition();
    if (_currentPosition != null) {
      _status = GpsStatus.fixed;
      notifyListeners();
    }

    _setupDynamicPolling();
  }

  bool _isCriticalBattery = false;

  void setCriticalBatteryMode(bool isCritical) {
    if (_isCriticalBattery != isCritical) {
      _isCriticalBattery = isCritical;
      if (kDebugMode) print("GPS: Critical Battery Mode set to $_isCriticalBattery");
      
      if (_isCriticalBattery) {
        // Cancel the periodic 30-min wake to save power
        _periodicWakeTimer?.cancel();
        _periodicWakeTimer = null;
      } else {
        // Restore the periodic wake
        _setupPeriodicWake();
      }
    }
  }

  void _setupDynamicPolling() {
    _setupPeriodicWake();

    // Rule: Listen to physical movement via accelerometer
    _accelSubscription = userAccelerometerEventStream().listen((event) {
      // Lowered threshold for significant movement to be more sensitive (1.5 m/s^2)
      if (event.x.abs() > 1.5 || event.y.abs() > 1.5 || event.z.abs() > 1.5) {
        if (!_isTrackingActive) {
           if (kDebugMode) print("GPS: Accelerometer movement detected! Waking GPS.");
           _wakeGpsFor(const Duration(seconds: 30));
        }
      }
    });

    // Do an initial wake
    if (kDebugMode) print("GPS: Initial wake triggered.");
    _wakeGpsFor(const Duration(seconds: 30));
  }

  void _setupPeriodicWake() {
    _periodicWakeTimer?.cancel();
    if (!_isCriticalBattery) {
      // Rule: Wake up for 10 seconds every 30 minutes for an accuracy check
      _periodicWakeTimer = Timer.periodic(const Duration(minutes: 30), (_) {
        if (kDebugMode) print("GPS: Periodic wake triggered.");
        _wakeGpsFor(const Duration(seconds: 10));
      });
    }
  }

  void _wakeGpsFor(Duration duration) {
    _gpsSleepTimer?.cancel();
    
    if (!_isTrackingActive) {
      _isTrackingActive = true;
      _startTracking();
    }

    _gpsSleepTimer = Timer(duration, () {
      _stopTracking();
    });
  }

  void _startTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      (Position position) {
        // Rule: Only accept new position if it is more accurate, OR if the previous one is null
        if (_currentPosition == null || position.accuracy <= _currentPosition!.accuracy) {
           _currentPosition = position;
        }
        _status = GpsStatus.fixed;
        notifyListeners();
      },
      onError: (e) {
        if (kDebugMode) print("GPS Error: $e");
        _status = GpsStatus.searching;
        notifyListeners();
      },
    );
  }

  void _stopTracking() {
    _positionSubscription?.cancel();
    _isTrackingActive = false;
    
    // Rule: Visual feedback that GPS is asleep to save battery
    if (_status == GpsStatus.fixed) {
      _status = GpsStatus.searching;
      notifyListeners();
    }
  }

  Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }

  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  Future<void> refresh() async {
    await _positionSubscription?.cancel();
    _status = GpsStatus.searching;
    notifyListeners();
    await _init();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _accelSubscription?.cancel();
    _periodicWakeTimer?.cancel();
    _gpsSleepTimer?.cancel();
    super.dispose();
  }
}
