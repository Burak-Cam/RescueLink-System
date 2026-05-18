import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'ble_service.dart';

class OtaService extends ChangeNotifier {
  final BleService _bleService;
  
  bool _isFlashing = false;
  double _progress = 0.0;
  String? _error;
  
  StreamSubscription? _systemEventSub;
  Completer<BleSystemEvent>? _ackCompleter;

  OtaService(this._bleService) {
    _systemEventSub = _bleService.systemEventStream.listen((event) {
      if (_isFlashing && _ackCompleter != null && !_ackCompleter!.isCompleted) {
        if (event == BleSystemEvent.otaReady || 
            event == BleSystemEvent.otaChunkAck || 
            event == BleSystemEvent.otaError || 
            event == BleSystemEvent.otaSuccess) {
          _ackCompleter!.complete(event);
        }
      }
    });
  }

  bool get isFlashing => _isFlashing;
  double get progress => _progress;
  String? get error => _error;

  Future<void> startBleOta() async {
    if (_isFlashing) return;
    
    _isFlashing = true;
    _progress = 0.0;
    _error = null;
    notifyListeners();

    try {
      if (kDebugMode) print("🔵 [OTA] Fetching latest release info from GitHub...");
      
      final releaseResponse = await http.get(
        Uri.parse("https://api.github.com/repos/Burak-Cam/RescueLink-System/releases/latest"),
        headers: {
          // GitHub API rate limits might apply. Consider adding an auth token if you hit limits frequently.
          "Accept": "application/vnd.github.v3+json",
        }
      );

      if (releaseResponse.statusCode != 200) {
        throw Exception("Failed to fetch release info: HTTP ${releaseResponse.statusCode}");
      }

      final releaseData = json.decode(releaseResponse.body);
      final assets = releaseData['assets'] as List;
      
      String? downloadUrl;
      for (var asset in assets) {
        if (asset['name'] == 'firmware.bin') {
          downloadUrl = asset['browser_download_url'];
          break;
        }
      }

      if (downloadUrl == null) {
        throw Exception("firmware.bin not found in latest release assets");
      }

      if (kDebugMode) print("🔵 [OTA] Downloading firmware from $downloadUrl");
      
      final request = http.Request('GET', Uri.parse(downloadUrl));
      request.headers['Accept'] = 'application/octet-stream';
      final response = await http.Client().send(request);
      
      if (response.statusCode != 200 && response.statusCode != 302 && response.statusCode != 301) {
         throw Exception("Failed to download firmware: HTTP ${response.statusCode}");
      }
      
      // Read response stream into bytes
      final List<int> bytesList = [];
      await for (var chunk in response.stream) {
        bytesList.addAll(chunk);
      }
      final bytes = Uint8List.fromList(bytesList);

      if (bytes.isEmpty) throw Exception("Firmware file is empty");
      
      if (kDebugMode) print("🔵 [OTA] Download complete. File size: ${bytes.length} bytes");

      // 1. Initialize OTA process with total size
      await _bleService.writeText("OTA_BLE|${bytes.length}", isHighPriority: true);
      
      // Wait for otaReady (0x20)
      BleSystemEvent ack = await _waitForAck(timeoutSeconds: 10);
      if (ack != BleSystemEvent.otaReady) {
        throw Exception("Device not ready for OTA. Received: $ack");
      }

      // 2. Send chunks
      const int chunkSize = 256;
      for (int i = 0; i < bytes.length; i += chunkSize) {
        final chunk = bytes.sublist(i, min(i + chunkSize, bytes.length));
        
        await _bleService.writeBinary(chunk, isHighPriority: true);
        
        // Wait for otaChunkAck (0x21) or otaError (0x22)
        ack = await _waitForAck(timeoutSeconds: 5);
        if (ack == BleSystemEvent.otaError) {
          throw Exception("Device reported error while receiving chunk at offset $i");
        } else if (ack != BleSystemEvent.otaChunkAck) {
          throw Exception("Unexpected ACK during chunk transfer: $ack");
        }
        
        _progress = (i + chunk.length) / bytes.length;
        notifyListeners();
      }

      // 3. Finalize OTA
      if (kDebugMode) print("🔵 [OTA] All chunks sent. Sending end signal.");
      await _bleService.writeText("OTA_BLE|END", isHighPriority: true);
      
      // Wait for otaSuccess (0x23)
      ack = await _waitForAck(timeoutSeconds: 15); // Flash operations might take a bit longer
      if (ack == BleSystemEvent.otaError) {
        throw Exception("Device reported error during final flashing stage.");
      } else if (ack != BleSystemEvent.otaSuccess) {
        throw Exception("Unexpected ACK during finalization: $ack");
      }

      if (kDebugMode) print("🟢 [OTA] Update successful!");
      
    } catch (e) {
      if (kDebugMode) print("🔴 [OTA] Error: $e");
      _error = e.toString();
    } finally {
      _isFlashing = false;
      notifyListeners();
    }
  }

  Future<BleSystemEvent> _waitForAck({required int timeoutSeconds}) async {
    _ackCompleter = Completer<BleSystemEvent>();
    try {
      return await _ackCompleter!.future.timeout(Duration(seconds: timeoutSeconds));
    } catch (e) {
      if (kDebugMode) print("🔴 [OTA] ACK Timeout after $timeoutSeconds seconds.");
      return BleSystemEvent.otaError; // Treat timeout as error
    } finally {
      _ackCompleter = null;
    }
  }

  @override
  void dispose() {
    _systemEventSub?.cancel();
    super.dispose();
  }
}