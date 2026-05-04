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
  fire,
  powerLost,
  rhythmicTapping,
  badAir,
  highHumidity,
  uncertain,
  heartbeatLost,
  heartbeatRestored,
}

class _BleTask {
  final Uint8List data;
  final bool isHighPriority;
  final Completer<bool> completer;

  _BleTask({required this.data, required this.isHighPriority, required this.completer});
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

  // Priority Queue Logic
  final List<_BleTask> _taskQueue = [];
  bool _isProcessingQueue = false;

  final StreamController<String> _incomingMessagesController = StreamController<String>.broadcast();
  final StreamController<dynamic> _ackController = StreamController<dynamic>.broadcast();
  final StreamController<BleSystemEvent> _systemEventController = StreamController<BleSystemEvent>.broadcast();
  final StreamController<Map<String, double>> _telemetryController = StreamController<Map<String, double>>.broadcast();
  
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
  Stream<Map<String, double>> get telemetryStream => _telemetryController.stream;

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
        // String telemetry paketi olma ihtimaline karşı önce string kontrolü yapalım
        try {
          String decoded = utf8.decode(value);
          if (decoded.startsWith("TEL|")) {
            final parts = decoded.split('|');
            if (parts.length >= 5) {
              final data = {
                'temp': double.tryParse(parts[1]) ?? 0.0,
                'hum': double.tryParse(parts[2]) ?? 0.0,
                'press': double.tryParse(parts[3]) ?? 0.0,
                'iaq': double.tryParse(parts[4]) ?? 0.0,
              };
              _telemetryController.add(data);
            }
            return; // Eğer telemetri ise byte olaylarını (event) taramaya gerek yok
          } else if (decoded.startsWith("ACK|")) {
            _ackController.add(decoded);
            ForegroundService.showSystemNotification('SOS Onaylandı', 'Mesajınız AFAD Karargahına ulaştı.');
            return;
          } else if (decoded.startsWith("HQ|")) {
            String msg = decoded.replaceFirst("HQ|", "");
            _incomingMessagesController.add(msg);
            ForegroundService.showSystemNotification('Karargah (HQ)', msg);
            return;
          }
        } catch (e) {
          // Eğer UTF8 çevirisi başarısız olursa, bu saf bir binary pakettir. Yolumuza devam edelim.
        }

        for (int byte in value) {
          switch (byte) {
            case 0x06: _ackController.add(0x06); break;
            case 0x0A: 
              if (kDebugMode) print('🔥 EARTHQUAKE DETECTED IN RAW BYTES!');
              _systemEventController.add(BleSystemEvent.earthquake); 
              processedAsEvent = true;
              break;
            case 0x0B: _systemEventController.add(BleSystemEvent.anomaly); processedAsEvent = true; break;
            case 0x0C: _systemEventController.add(BleSystemEvent.fire); processedAsEvent = true; break;
            case 0x0D: _systemEventController.add(BleSystemEvent.rhythmicTapping); processedAsEvent = true; break;
            case 0x0E: _systemEventController.add(BleSystemEvent.badAir); processedAsEvent = true; break;
            case 0x0F: _systemEventController.add(BleSystemEvent.highHumidity); processedAsEvent = true; break;
            case 0x10: _systemEventController.add(BleSystemEvent.uncertain); processedAsEvent = true; break;
            case 0x11: _systemEventController.add(BleSystemEvent.powerLost); processedAsEvent = true; break;
            case 0x12: processedAsEvent = true; break; // Heartbeat
          }
        }

        if (processedAsEvent && value.length == 1) return;

        // Eğer string olarak yakalanamadıysa ve event değilse, ham text olarak ekle (eski tip HQ mesajları vb)
        try {
          String decoded = utf8.decode(value);
          _incomingMessagesController.add(decoded);
        } catch (e) {}
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

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    while (_taskQueue.isNotEmpty) {
      // Find the first high-priority task, or if none, take the first task.
      int nextTaskIndex = _taskQueue.indexWhere((task) => task.isHighPriority);
      if (nextTaskIndex == -1) nextTaskIndex = 0; // No high priority tasks, take the oldest normal task

      _BleTask currentTask = _taskQueue.removeAt(nextTaskIndex);

      if (_status == BleConnectionStatus.connected && _rxCharacteristic != null) {
        try {
          bool withoutResp = _rxCharacteristic!.properties.writeWithoutResponse;
          await _rxCharacteristic!.write(currentTask.data, withoutResponse: withoutResp);
          currentTask.completer.complete(true);
        } catch (e) {
          if (kDebugMode) print("BLE Write Failed: $e");
          currentTask.completer.complete(false);
        }
      } else {
        currentTask.completer.complete(false);
      }

      // Add a small delay between packets to prevent BLE congestion (crucial for ESP32 stability)
      await Future.delayed(const Duration(milliseconds: 50));
    }

    _isProcessingQueue = false;
  }

  Future<bool> writeBinary(Uint8List data, {bool isHighPriority = false}) async {
    if (_status != BleConnectionStatus.connected || _rxCharacteristic == null) {
      return false;
    }
    
    final completer = Completer<bool>();
    _taskQueue.add(_BleTask(data: data, isHighPriority: isHighPriority, completer: completer));
    
    // Asynchronously start processing without waiting for it to finish immediately here
    _processQueue();
    
    return await completer.future;
  }

  Future<bool> sendSilenceCommand() async {
    return await writeBinary(Uint8List.fromList([0x99]), isHighPriority: true);
  }

  Future<bool> enableComaMode() async {
    return await writeBinary(Uint8List.fromList([0x55]), isHighPriority: true);
  }

  Future<bool> disableComaMode() async {
    return await writeBinary(Uint8List.fromList([0x56]), isHighPriority: true);
  }

  @override
  void dispose() {
    _onValueReceivedSubscription?.cancel();
    _incomingMessagesController.close();
    _ackController.close();
    _systemEventController.close();
    _telemetryController.close();
    super.dispose();
  }
}
