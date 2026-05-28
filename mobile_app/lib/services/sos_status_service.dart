import 'dart:async';
import 'package:flutter/foundation.dart';
import 'storage_service.dart';

enum SosProcessState {
  idle,
  queuedOffline,
  sending,
  sentToNode,
  deliveredToHq,
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
  bool _aiEmergencyOverride = false;
  Timer? _aiOverrideTimer;

  bool _fireAiUnlocked = false;
  Timer? _fireUnlockTimer;
  DateTime? _lastFireSosTime;

  bool _gasAiUnlocked = false;
  Timer? _gasUnlockTimer;
  DateTime? _lastGasSosTime;
  
  String _currentSendingType = "EARTHQUAKE";

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
  
  bool get isCooldownActive {
    if (_storage.isDevMode()) return false;
    if (_aiEmergencyOverride) return false;
    return true; // Varsayılan olarak hep kilitli
  }

  bool isLockedFor(String type) {
    if (_storage.isDevMode()) return false;
    
    if (type == "FIRE" || type == "CRITICAL_TEMP") {
      if (_lastFireSosTime != null && DateTime.now().difference(_lastFireSosTime!).inMinutes < 5) return true; // Cooldown
      return !_fireAiUnlocked; // Not unlocked by AI yet
    } else if (type == "GAS" || type == "GAS_LEAK") {
      if (_lastGasSosTime != null && DateTime.now().difference(_lastGasSosTime!).inMinutes < 5) return true; // Cooldown
      return !_gasAiUnlocked; // Not unlocked by AI yet
    }
    
    // Default Earthquake/Tapping
    if (_aiEmergencyOverride) return false;
    return true;
  }

  bool get isInsideBlockWindow {
    if (_lastSosTimestamp == null) return false;
    final diff = DateTime.now().difference(_lastSosTimestamp!);
    return diff.inSeconds < (blockMinutes * 60);
  }

  int get blockRemainingSeconds {
    if (_lastSosTimestamp == null) return 0;
    final diff = DateTime.now().difference(_lastSosTimestamp!);
    final remaining = (blockMinutes * 60) - diff.inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  void triggerAiEmergency({String type = "EARTHQUAKE", Duration duration = const Duration(minutes: 15)}) {
    if (kDebugMode) print('🚨 SOS_STATUS: AI Kilidi Kırdı! SOS Aktif ($type).');
    if (type == "FIRE" || type == "CRITICAL_TEMP") {
      _fireUnlockTimer?.cancel();
      _fireAiUnlocked = true;
      notifyListeners();
      _fireUnlockTimer = Timer(duration, () { _fireAiUnlocked = false; notifyListeners(); });
    } else if (type == "GAS" || type == "GAS_LEAK") {
      _gasUnlockTimer?.cancel();
      _gasAiUnlocked = true;
      notifyListeners();
      _gasUnlockTimer = Timer(duration, () { _gasAiUnlocked = false; notifyListeners(); });
    } else {
      _aiOverrideTimer?.cancel();
      _aiEmergencyOverride = true;
      notifyListeners();
      _aiOverrideTimer = Timer(duration, () { _aiEmergencyOverride = false; notifyListeners(); });
    }
  }

  Future<void> setStatus(SosProcessState newState, {String? error}) async {
    _state = newState;
    _errorMessage = error;

    if (newState == SosProcessState.deliveredToHq || newState == SosProcessState.sentToNode) {
      if (_currentSendingType == "FIRE" || _currentSendingType == "CRITICAL_TEMP") {
        _fireAiUnlocked = false;
        _fireUnlockTimer?.cancel();
        _lastFireSosTime = DateTime.now();
        if (newState == SosProcessState.deliveredToHq) _hqConfirmed = true;
      } else if (_currentSendingType == "GAS" || _currentSendingType == "GAS_LEAK") {
        _gasAiUnlocked = false;
        _gasUnlockTimer?.cancel();
        _lastGasSosTime = DateTime.now();
        if (newState == SosProcessState.deliveredToHq) _hqConfirmed = true;
      } else {
        _aiEmergencyOverride = false;
        _aiOverrideTimer?.cancel();
        _lastSosTimestamp = DateTime.now();
        await _storage.saveLastSosTimestamp(_lastSosTimestamp!);
        if (newState == SosProcessState.deliveredToHq) _hqConfirmed = true;
        _startCooldown();
      }
    } else if (newState == SosProcessState.idle) {
      _checkCooldown();
    }
    notifyListeners();
  }

  void resetCooldown() {
    _cooldownTimer?.cancel();
    _aiOverrideTimer?.cancel();
    _fireUnlockTimer?.cancel();
    _gasUnlockTimer?.cancel();
    _remainingSeconds = 0;
    _state = SosProcessState.idle;
    _lastSosTimestamp = null;
    _lastFireSosTime = null;
    _lastGasSosTime = null;
    _hqConfirmed = false;
    _errorMessage = null;
    _aiEmergencyOverride = false;
    _fireAiUnlocked = false;
    _gasAiUnlocked = false;
    _storage.clearLastSosTimestamp();
    notifyListeners();
  }

  void startSending({String type = "EARTHQUAKE"}) {
    _currentSendingType = type;
    _state = SosProcessState.sending;
    _hqConfirmed = false;
    _errorMessage = null;
    notifyListeners();
  }

  void _checkCooldown() {
    if (_storage.isDevMode()) return;
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

  void _startCooldown() { _checkCooldown(); }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        _remainingSeconds--;
        if (isInsideBlockWindow || _remainingSeconds % 10 == 0) {
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

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _aiOverrideTimer?.cancel();
    super.dispose();
  }
}
