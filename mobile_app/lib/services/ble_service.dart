import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'foreground_service.dart';

enum BleConnectionStatus {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

enum BleSystemEvent {
  earthquake,
  anomaly,
  powerLost,
  rhythmicTapping,
  heartbeatLost,
  heartbeatRestored,
}

class BleService extends ChangeNotifier {
  static const String uartServiceUuid = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  static const String rxCharUuid = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";
  static const String txCharUuid = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";

  BluetoothDevice? _connectedDevice;
  BluetoothDevice? _lastConnectedDevice; 
  BluetoothCharacteristic? _rxCharacteristic;
  BluetoothCharacteristic? _txCharacteristic;

  BleConnectionStatus _status = BleConnectionStatus.disconnected;
  List<ScanResult> _scanResults = [];
  String? _errorMessage;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;

  bool _isHeartbeatAlive = true;
  Timer? _heartbeatTimer;

  final StreamController<String> _incomingMessagesController = StreamController<String>.broadcast();
  final StreamController<dynamic> _ackController = StreamController<dynamic>.broadcast();
  final StreamController<BleSystemEvent> _systemEventController = StreamController<BleSystemEvent>.broadcast();
  
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  StreamSubscription<List<int>>? _onValueReceivedSubscription;

  BleConnectionStatus get status => _status;
  bool get isHeartbeatAlive => _isHeartbeatAlive;
  List<ScanResult> get scanResults => _scanResults;
  String? get errorMessage => _errorMessage;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  BluetoothAdapterState get adapterState => _adapterState;
  Stream<String> get hqMessages => _incomingMessagesController.stream;
  Stream<dynamic> get ackStream => _ackController.stream;
  Stream<BleSystemEvent> get systemEventStream => _systemEventController.stream;

  BleService() {
    _initAdapterState();
    _initListeners();
  }

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _isHeartbeatAlive = true;
    _heartbeatTimer = Timer(const Duration(seconds: 180), () {
      if (_status == BleConnectionStatus.connected) {
        _isHeartbeatAlive = false;
        _systemEventController.add(BleSystemEvent.heartbeatLost);
        notifyListeners();
      }
    });
  }

  void _resetHeartbeat() {
    if (!_isHeartbeatAlive) {
      _isHeartbeatAlive = true;
      _systemEventController.add(BleSystemEvent.heartbeatRestored);
    }
    _startHeartbeatTimer();
    notifyListeners();
  }

  Future<void> _initAdapterState() async {
    _adapterState = await FlutterBluePlus.adapterState.first;
    notifyListeners();
  }

  void _initListeners() {
    _adapterSubscription = FlutterBluePlus.adapterState.listen((state) {
      _adapterState = state;
      if (state == BluetoothAdapterState.off) _handleUnexpectedDisconnect("Bluetooth OFF");
      notifyListeners();
    });
    FlutterBluePlus.scanResults.listen((results) {
      _scanResults = results.where((r) => r.device.platformName.isNotEmpty).toList();
      notifyListeners();
    });
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 4)}) async {
    if (_adapterState != BluetoothAdapterState.on) return;
    _status = BleConnectionStatus.scanning;
    notifyListeners();
    await FlutterBluePlus.startScan(timeout: timeout);
  }

  Future<BluetoothDevice?> findDevice(String remoteId, {Duration timeout = const Duration(seconds: 10)}) async {
    _status = BleConnectionStatus.scanning;
    notifyListeners();
    final Completer<BluetoothDevice?> completer = Completer();
    StreamSubscription? sub = FlutterBluePlus.scanResults.listen((results) {
      for (var r in results) {
        if (r.device.remoteId.toString() == remoteId) {
          FlutterBluePlus.stopScan();
          if (!completer.isCompleted) completer.complete(r.device);
        }
      }
    });
    await FlutterBluePlus.startScan(timeout: timeout);
    Future.delayed(timeout).then((_) { if (!completer.isCompleted) completer.complete(null); });
    final dev = await completer.future;
    sub.cancel();
    return dev;
  }

  Future<bool> connect(BluetoothDevice device) async {
    _status = BleConnectionStatus.connecting;
    notifyListeners();
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      _connectedDevice = device;
      _lastConnectedDevice = device;

      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString().toUpperCase().contains("6E400001")) {
          for (var char in service.characteristics) {
            if (char.uuid.toString().toUpperCase().contains("6E400002")) _rxCharacteristic = char;
            if (char.uuid.toString().toUpperCase().contains("6E400003")) _txCharacteristic = char;
          }
        }
      }

      if (_rxCharacteristic != null && _txCharacteristic != null) {
        _status = BleConnectionStatus.connected;
        _startHeartbeatTimer();
        // CRITICAL: Await notification setup before returning success
        await _setupNotification(); 
        await ForegroundService.start();
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _status = BleConnectionStatus.error;
      notifyListeners();
      return false;
    }
  }

  void _handleUnexpectedDisconnect(String reason) {
    _connectedDevice = null;
    _rxCharacteristic = null;
    _txCharacteristic = null;
    _status = BleConnectionStatus.disconnected;
    _heartbeatTimer?.cancel();
    _onValueReceivedSubscription?.cancel();
    ForegroundService.stop();
    notifyListeners();
  }

  Future<void> _setupNotification() async {
    if (_txCharacteristic == null) return;
    
    // Rule: Cancel previous subscription if exists
    _onValueReceivedSubscription?.cancel();
    
    // Rule: Start listening BEFORE enabling notifications to catch the very first packet
    _onValueReceivedSubscription = _txCharacteristic!.onValueReceived.listen((value) {
      if (value.isNotEmpty) {
        _resetHeartbeat();
        if (kDebugMode) print('📥 BLE RAW DATA: $value');

        bool processedAsEvent = false;
        for (int byte in value) {
          switch (byte) {
            case 0x06: _ackController.add(0x06); break;
            case 0x0E: processedAsEvent = true; break;
            case 0x0A: 
              if (kDebugMode) print('🔥 EARTHQUAKE DETECTED IN RAW BYTES!');
              _systemEventController.add(BleSystemEvent.earthquake); 
              processedAsEvent = true;
              break;
            case 0x0B: _systemEventController.add(BleSystemEvent.anomaly); processedAsEvent = true; break;
            case 0x0C: _systemEventController.add(BleSystemEvent.powerLost); processedAsEvent = true; break;
            case 0x0D: _systemEventController.add(BleSystemEvent.rhythmicTapping); processedAsEvent = true; break;
          }
        }

        if (processedAsEvent && value.length == 1) return;

        try {
          String decoded = utf8.decode(value);
          if (decoded.startsWith("ACK|")) {
            _ackController.add(decoded);
          } else if (decoded.startsWith("HQ|")) {
            _incomingMessagesController.add(decoded.replaceFirst("HQ|", ""));
          } else {
            _incomingMessagesController.add(decoded);
          }
        } catch (e) { }
      }
    });

    await _txCharacteristic!.setNotifyValue(true);
    if (kDebugMode) print('✅ BLE: Notifications enabled and listener attached.');
  }

  Future<void> disconnect() async {
    _lastConnectedDevice = null;
    if (_connectedDevice != null) {
      _heartbeatTimer?.cancel();
      _onValueReceivedSubscription?.cancel();
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
      _status = BleConnectionStatus.disconnected;
      notifyListeners();
    }
  }

  Future<bool> writeBinary(Uint8List data) async {
    if (_status == BleConnectionStatus.connected && _rxCharacteristic != null) {
      try {
        await _rxCharacteristic!.write(data, withoutResponse: false);
        return true;
      } catch (e) { return false; }
    }
    return false;
  }

  @override
  void dispose() {
    _onValueReceivedSubscription?.cancel();
    _incomingMessagesController.close();
    _ackController.close();
    _systemEventController.close();
    super.dispose();
  }
}
