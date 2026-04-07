import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
import 'package:mbtiles/mbtiles.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

class MapService extends ChangeNotifier {
  static const String _mbtilesAssetName = 'assets/map/offline_base.mbtiles';
  static const String _mbtilesFileName = 'offline_base.mbtiles';
  
  // Public Open-Source MBTiles Sample (Istanbul/Turkey region or similar)
  // This URL provides a small sample MBTiles file for testing offline maps.
  static const String _fallbackDownloadUrl = 'https://raw.githubusercontent.com/maplibre/maplibre-gl-js/main/test/unit/assets/sample_map.mbtiles';

  final StorageService _storage;
  MbTilesTileProvider? _tileProvider;
  bool _isInitialized = false;
  String? _errorMessage;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  MbTilesTileProvider? get tileProvider => _tileProvider;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;
  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;

  bool hasMapForCity(String city) {
    return _tileProvider != null;
  }

  MapService(this._storage) {
    _init();
  }

  Future<void> _init() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final path = join(directory.path, _mbtilesFileName);

      if (await File(path).exists()) {
        _loadMbTiles(path);
      } else {
        try {
          final data = await rootBundle.load(_mbtilesAssetName);
          final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
          await File(path).writeAsBytes(bytes, flush: true);
          _loadMbTiles(path);
        } catch (e) {
          _isInitialized = true;
          notifyListeners();
        }
      }
    } catch (e) {
      _errorMessage = e.toString();
      _isInitialized = true;
      notifyListeners();
    }
  }

  void _loadMbTiles(String path) {
    try {
      _tileProvider?.dispose();
      _tileProvider = MbTilesTileProvider(mbtiles: MbTiles(mbtilesPath: path));
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> downloadMap(String city) async {
    if (_isDownloading) return;

    _isDownloading = true;
    _downloadProgress = 0.0;
    _errorMessage = null;
    notifyListeners();

    try {
      final directory = await getApplicationDocumentsDirectory();
      final path = join(directory.path, _mbtilesFileName);

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(_fallbackDownloadUrl));
      final response = await client.send(request);

      if (response.statusCode == 200) {
        final List<int> bytes = [];
        final int totalContentLength = response.contentLength ?? 0;
        int receivedLength = 0;

        await for (var chunk in response.stream) {
          bytes.addAll(chunk);
          receivedLength += chunk.length;
          if (totalContentLength > 0) {
            _downloadProgress = receivedLength / totalContentLength;
            notifyListeners();
          }
        }

        final file = File(path);
        await file.writeAsBytes(bytes);
        _loadMbTiles(path);
      } else {
        throw Exception("Server Error: ${response.statusCode}");
      }
    } catch (e) {
      _errorMessage = "Download failed: $e";
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _tileProvider?.dispose();
    super.dispose();
  }
}
