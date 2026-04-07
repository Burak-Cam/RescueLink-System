import 'dart:async';
import 'package:flutter/foundation.dart';
import 'storage_service.dart';

enum SosProcessState {
  idle,
  sending,      // Step 1: Sending from Device
  sentToNode,   // Step 2: Delivered to Node
  deliveredToHq, // Step 3: Delivered to Gateway
  error,
}

class SosStatusService extends ChangeNotifier {
  static const int cooldownHours = 6;
  static const int blockMinutes = 15;
  
  SosProcessState _state = SosProcessState.idle;
  DateTime? _lastSosTimestamp;
  Timer? _cooldownTimer;
  int _remainingSeconds = 0;
  bool _hqConfirmed = false;
  String? _errorMessage;

  final StorageService _storage;

  SosStatusService(this._storage) {
    _init();
  }

  void _init() {
    _lastSosTimestamp = _storage.getLastSosTimestamp();
    _checkCooldown();
  }

  SosProcessState get state => _state;
  int get remainingSeconds => _remainingSeconds;
  bool get hqConfirmed => _hqConfirmed;
  String? get errorMessage => _errorMessage;
  
  // Rule: SOS button is only visually locked during the 15-minute absolute block.
  // After 15 minutes, it is unlocked, but identical payloads are still blocked by _sendSos.
  bool get isCooldownActive {
    if (_storage.isDevMode()) return false;
    return isInsideBlockWindow;
  }

  bool get isInsideBlockWindow {
    if (_lastSosTimestamp == null) return false;
    final diff = DateTime.now().difference(_lastSosTimestamp!);
    return diff.inMinutes < blockMinutes;
  }

  int get blockRemainingSeconds {
    if (_lastSosTimestamp == null) return 0;
    final diff = DateTime.now().difference(_lastSosTimestamp!);
    final remaining = (blockMinutes * 60) - diff.inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  void setStatus(SosProcessState newState, {String? error}) {
    _state = newState;
    _errorMessage = error;

    if (newState == SosProcessState.deliveredToHq || newState == SosProcessState.sentToNode) {
      _lastSosTimestamp = DateTime.now();
      _storage.saveLastSosTimestamp(_lastSosTimestamp!);
      if (newState == SosProcessState.deliveredToHq) _hqConfirmed = true;
      _startCooldown();
    } else if (newState == SosProcessState.idle) {
      _checkCooldown();
    }
    notifyListeners();
  }

  void resetCooldown() {
    _cooldownTimer?.cancel();
    _remainingSeconds = 0;
    _state = SosProcessState.idle;
    _lastSosTimestamp = null;
    _hqConfirmed = false;
    _errorMessage = null;
    _storage.clearLastSosTimestamp();
    notifyListeners();
  }

  void startSending() {
    _state = SosProcessState.sending;
    _hqConfirmed = false;
    _errorMessage = null;
    notifyListeners();
  }

  void _checkCooldown() {
    if (_storage.isDevMode()) {
      _remainingSeconds = 0;
      _cooldownTimer?.cancel();
      return;
    }
    
    if (_lastSosTimestamp == null) return;

    final diff = DateTime.now().difference(_lastSosTimestamp!);
    final totalCooldown = const Duration(hours: cooldownHours);

    if (diff < totalCooldown) {
      _remainingSeconds = totalCooldown.inSeconds - diff.inSeconds;
      _startCooldownTimer();
    } else {
      _remainingSeconds = 0;
      _storage.clearLastSosTimestamp();
    }
  }

  void _startCooldown() {
    _checkCooldown();
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        _remainingSeconds--;
        if (_remainingSeconds < 60 || isInsideBlockWindow || _remainingSeconds % 10 == 0) {
          notifyListeners();
        }
      } else {
        if (_state == SosProcessState.deliveredToHq || _state == SosProcessState.sentToNode) {
           _state = SosProcessState.idle;
        }
        _storage.clearLastSosTimestamp();
        timer.cancel();
        notifyListeners();
      }
    });
  }

  bool hasPayloadChanged(String currentHealth, int currentCount) {
    return currentHealth != _storage.getLastHealth() || currentCount != _storage.getLastCount();
  }

  // Rule: Strict SOS Language based on Profile country
  bool isInTurkey() {
    final country = _storage.getCountry();
    return country == 'Türkiye' || country == 'Turkey';
  }

  String getLocalizedHealth(String key, Map<String, String> tr, Map<String, String> en) {
    return isInTurkey() ? (tr[key] ?? key) : (en[key] ?? key);
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }
}
