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

class BleService extends ChangeNotifier {
  static const String uartServiceUuid = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  static const String rxCharUuid = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"; // App to ESP32
  static const String txCharUuid = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"; // ESP32 to App

  BluetoothDevice? _connectedDevice;
  BluetoothDevice? _lastConnectedDevice; // Kept for auto-retries
  BluetoothCharacteristic? _rxCharacteristic;
  BluetoothCharacteristic? _txCharacteristic;

  BleConnectionStatus _status = BleConnectionStatus.disconnected;
  List<ScanResult> _scanResults = [];
  String? _errorMessage;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;

  final StreamController<String> _incomingMessagesController = StreamController<String>.broadcast();
  final StreamController<dynamic> _ackController = StreamController<dynamic>.broadcast();
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;

  // Getters
  BleConnectionStatus get status => _status;
  List<ScanResult> get scanResults => _scanResults;
  String? get errorMessage => _errorMessage;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  BluetoothAdapterState get adapterState => _adapterState;
  Stream<String> get hqMessages => _incomingMessagesController.stream;
  Stream<dynamic> get ackStream => _ackController.stream;

  BleService() {
    _initAdapterState();
    _initListeners();
  }

  Future<void> _initAdapterState() async {
    _adapterState = await FlutterBluePlus.adapterState.first;
    notifyListeners();
  }

  void _initListeners() {
    _adapterSubscription = FlutterBluePlus.adapterState.listen((state) {
      _adapterState = state;
      if (state == BluetoothAdapterState.off) {
        _handleUnexpectedDisconnect("Bluetooth is turned off");
      } else if (state == BluetoothAdapterState.on) {
        _errorMessage = null;
      }
      notifyListeners();
    });

    FlutterBluePlus.scanResults.listen((results) {
      _scanResults = results.where((r) => 
        r.device.platformName.isNotEmpty || 
        r.advertisementData.advName.isNotEmpty
      ).toList();
      notifyListeners();
    });

    FlutterBluePlus.isScanning.listen((isScanning) {
      if (!isScanning && _status == BleConnectionStatus.scanning) {
        _status = BleConnectionStatus.disconnected;
        notifyListeners();
      }
    });
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 4)}) async {
    if (_adapterState != BluetoothAdapterState.on) {
      _status = BleConnectionStatus.error;
      _errorMessage = "Bluetooth is disabled";
      notifyListeners();
      return;
    }

    _status = BleConnectionStatus.scanning;
    _errorMessage = null;
    notifyListeners();

    try {
      await FlutterBluePlus.startScan(timeout: timeout);
    } catch (e) {
      _status = BleConnectionStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  // Rule: Specific background scan for auto-connect
  Future<BluetoothDevice?> findDevice(String remoteId, {Duration timeout = const Duration(seconds: 10)}) async {
    if (_adapterState != BluetoothAdapterState.on) return null;
    
    _status = BleConnectionStatus.scanning;
    notifyListeners();

    final Completer<BluetoothDevice?> completer = Completer();
    StreamSubscription? subscription;

    try {
      subscription = FlutterBluePlus.scanResults.listen((results) {
        for (var r in results) {
          if (r.device.remoteId.toString() == remoteId) {
            FlutterBluePlus.stopScan();
            if (!completer.isCompleted) completer.complete(r.device);
            return;
          }
        }
      });

      await FlutterBluePlus.startScan(timeout: timeout);
      
      // Wait for timeout if not found
      Future.delayed(timeout).then((_) {
        if (!completer.isCompleted) completer.complete(null);
      });

      final device = await completer.future;
      return device;
    } catch (e) {
      if (kDebugMode) print("Find Device Error: $e");
    } finally {
      await subscription?.cancel();
      _status = BleConnectionStatus.disconnected;
      notifyListeners();
    }
    return null;
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  Future<bool> connect(BluetoothDevice device) async {
    if (_adapterState != BluetoothAdapterState.on) return false;

    _status = BleConnectionStatus.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      _connectionSubscription?.cancel();
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && _status == BleConnectionStatus.connected) {
          _handleUnexpectedDisconnect("Device disconnected unexpectedly");
        }
      });

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
        _setupNotification();
        await ForegroundService.start();
        notifyListeners();
        return true;
      } else {
        throw Exception("UART Services not found on device");
      }
    } catch (e) {
      await device.disconnect();
      _status = BleConnectionStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  void _handleUnexpectedDisconnect(String reason) {
    _connectedDevice = null;
    _rxCharacteristic = null;
    _txCharacteristic = null;
    _status = BleConnectionStatus.disconnected;
    _errorMessage = reason;
    ForegroundService.stop();
    notifyListeners();
  }

  void _setupNotification() async {
    if (_txCharacteristic == null) return;
    await _txCharacteristic!.setNotifyValue(true);
    _txCharacteristic!.lastValueStream.listen((value) {
      if (value.isNotEmpty) {
        // Rule: Check for ACK byte 0x06 from node
        if (value.length == 1 && value[0] == 0x06) {
          _ackController.add(0x06);
          return;
        }

        String decoded = utf8.decode(value);
        
        if (decoded.startsWith("ACK|")) {
          _ackController.add(decoded);
        } else if (decoded.startsWith("HQ|")) {
          _incomingMessagesController.add(decoded.replaceFirst("HQ|", ""));
        } else {
          _incomingMessagesController.add(decoded);
        }
      }
    });
  }

  Future<void> disconnect() async {
    _lastConnectedDevice = null;
    if (_connectedDevice != null) {
      _connectionSubscription?.cancel();
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
      _rxCharacteristic = null;
      _txCharacteristic = null;
      _status = BleConnectionStatus.disconnected;
      _errorMessage = null;
      await ForegroundService.stop();
      notifyListeners();
    }
  }

  Future<bool> writeMessage(String message) async {
    return await writeBinary(utf8.encode(message) as Uint8List);
  }

  Future<bool> writeBinary(Uint8List data) async {
    BluetoothDevice? targetDevice = _connectedDevice ?? _lastConnectedDevice;
    if (targetDevice == null) return false;

    // Background retry loop
    while (targetDevice != null && _lastConnectedDevice == targetDevice) {
      if (_status != BleConnectionStatus.connected) {
        try {
          await connect(targetDevice);
        } catch (e) {
          // Connection failed, will retry
        }
      }

      if (_status == BleConnectionStatus.connected && _rxCharacteristic != null) {
        try {
          await _rxCharacteristic!.write(data, withoutResponse: false);
          return true; // Successful write!
        } catch (e) {
          if (kDebugMode) print("Write Error: $e, retrying...");
        }
      }

      // Wait 3 seconds before next attempt
      await Future.delayed(const Duration(seconds: 3));
      targetDevice = _connectedDevice ?? _lastConnectedDevice;
    }
    return false;
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _adapterSubscription?.cancel();
    _incomingMessagesController.close();
    _ackController.close();
    super.dispose();
  }
}
