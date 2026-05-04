import 'package:flutter/material.dart';
import 'package:battery_plus/battery_plus.dart';

class BatteryStateService extends ChangeNotifier {
  final Battery _battery = Battery();
  bool _isCritical = false;
  int _batteryLevel = 100;

  bool get isCritical => _isCritical;
  int get batteryLevel => _batteryLevel;

  BatteryStateService() {
    _init();
  }

  Future<void> _init() async {
    _batteryLevel = await _battery.batteryLevel;
    _checkCritical();

    _battery.onBatteryStateChanged.listen((state) async {
      _batteryLevel = await _battery.batteryLevel;
      _checkCritical();
    });
  }

  void _checkCritical() {
    bool newCriticalState = _batteryLevel <= 15;
    if (_isCritical != newCriticalState) {
      _isCritical = newCriticalState;
      notifyListeners();
    }
  }
}
