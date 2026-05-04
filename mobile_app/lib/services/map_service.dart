import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'storage_service.dart';

class TileCoord {
  final int z;
  final int x;
  final int y;
  TileCoord(this.z, this.x, this.y);
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TileCoord &&
          runtimeType == other.runtimeType &&
          z == other.z &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => z.hashCode ^ x.hashCode ^ y.hashCode;
}

class MapService extends ChangeNotifier {
  final StorageService _storage;
  bool _isInitialized = false;
  String? _errorMessage;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatusText = "";
  Directory? _offlineMapDir;

  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;
  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  String get downloadStatusText => _downloadStatusText;

  MapService(this._storage) {
    _init();
  }

  Future<void> _init() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      _offlineMapDir = Directory(path.join(directory.path, 'offline_maps'));
      if (!await _offlineMapDir!.exists()) {
        await _offlineMapDir!.create(recursive: true);
      }
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      _errorMessage = "Harita dizini oluşturulamadı: $e";
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Belirli bir şehrin haritası inmiş mi diye kabaca kontrol eder (şu an klasör boş mu diye bakıyoruz)
  bool hasMapForCity(String city) {
    if (_offlineMapDir == null) return false;
    try {
      return _offlineMapDir!.listSync(recursive: true).isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // --- Slippy Map XYZ Math ---
  int _lon2tilex(double lon, int z) {
    return ((lon + 180.0) / 360.0 * math.pow(2.0, z)).floor();
  }

  int _lat2tiley(double lat, int z) {
    return ((1.0 - math.log(math.tan(lat * math.pi / 180.0) + 1.0 / math.cos(lat * math.pi / 180.0)) / math.pi) / 2.0 * math.pow(2.0, z)).floor();
  }

  /// Verilen merkez koordinat ve yarıçap için indirilmesi gereken tüm XYZ karelerini hesaplar
  Set<TileCoord> _calculateTilesForRadius(double centerLat, double centerLon, double radiusKm, List<int> zoomLevels) {
    Set<TileCoord> tiles = {};
    
    // Yarıçapı derece cinsine kaba bir şekilde çeviriyoruz
    // 1 derece enlem ~111km
    double latDelta = radiusKm / 111.0;
    // Boylam deltası enleme göre değişir
    double lonDelta = radiusKm / (111.0 * math.cos(centerLat * math.pi / 180.0));

    double minLat = centerLat - latDelta;
    double maxLat = centerLat + latDelta;
    double minLon = centerLon - lonDelta;
    double maxLon = centerLon + lonDelta;

    for (int z in zoomLevels) {
      int minX = _lon2tilex(minLon, z);
      int maxX = _lon2tilex(maxLon, z);
      int minY = _lat2tiley(maxLat, z); // maxLat y-ekseninde daha küçüktür (kuzey)
      int maxY = _lat2tiley(minLat, z);

      for (int x = minX; x <= maxX; x++) {
        for (int y = minY; y <= maxY; y++) {
          tiles.add(TileCoord(z, x, y));
        }
      }
    }
    return tiles;
  }

  /// Arka planda 2KM'lik mikro-harita verisini indirir
  Future<void> downloadLocalMapCache(double lat, double lon) async {
    if (_isDownloading || _offlineMapDir == null) return;

    _isDownloading = true;
    _downloadProgress = 0.0;
    _errorMessage = null;
    notifyListeners();

    try {
      // Afet senaryosu için yürüme mesafesi (2km) yeterlidir. 
      // Z=15 (Sokaklar), Z=16 (Binalar), Z=17 (Detay)
      final targetTiles = _calculateTilesForRadius(lat, lon, 2.0, [15, 16, 17]);
      int totalTiles = targetTiles.length;
      int downloadedCount = 0;

      _downloadStatusText = "Hesaplandı: $totalTiles kare indirilecek...";
      notifyListeners();
      
      if (kDebugMode) print("🗺️ [MapService] İndirilecek harita karesi sayısı: $totalTiles");

      final client = http.Client();
      
      // Eşzamanlı (Concurrent) indirme limiti. Cihazı kitlememek için 5-10 iyidir.
      const int concurrency = 5;
      final List<TileCoord> tileList = targetTiles.toList();
      
      for (int i = 0; i < totalTiles; i += concurrency) {
        if (!_isDownloading) break; // Kullanıcı iptal ettiyse

        final chunk = tileList.sublist(i, math.min(i + concurrency, totalTiles));
        
        await Future.wait(chunk.map((tile) async {
          final tileFile = File(path.join(_offlineMapDir!.path, '${tile.z}', '${tile.x}', '${tile.y}.png'));
          
          if (!await tileFile.exists()) {
            final url = 'https://tile.openstreetmap.org/${tile.z}/${tile.x}/${tile.y}.png';
            try {
              final response = await client.get(Uri.parse(url), headers: {
                'User-Agent': 'RescueLink_Disaster_App/1.0' // OSM kuralları gereği UA ekliyoruz
              });
              
              if (response.statusCode == 200) {
                await tileFile.create(recursive: true);
                await tileFile.writeAsBytes(response.bodyBytes);
              }
            } catch (e) {
              if (kDebugMode) print("Tile download error Z:${tile.z} X:${tile.x} Y:${tile.y} -> $e");
            }
          }
        }));

        downloadedCount += chunk.length;
        _downloadProgress = downloadedCount / totalTiles;
        _downloadStatusText = "İndiriliyor: %${(_downloadProgress * 100).toStringAsFixed(1)} ($downloadedCount/$totalTiles)";
        notifyListeners();
      }
      
      client.close();
      _downloadStatusText = "İndirme Tamamlandı!";
    } catch (e) {
      _errorMessage = "Harita indirme hatası: $e";
      _downloadStatusText = "Hata Oluştu!";
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  /// FlutterMap için yerel bir ImageProvider döndürür. İnternet yokken UI buradan resmi okuyabilir.
  Future<File?> getLocalTileFile(int z, int x, int y) async {
    if (_offlineMapDir == null) return null;
    final file = File(path.join(_offlineMapDir!.path, '$z', '$x', '$y.png'));
    if (await file.exists()) {
      return file;
    }
    return null;
  }
}

class OfflineTileProvider extends TileProvider {
  final MapService mapService;
  
  OfflineTileProvider(this.mapService);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _OfflineImageProvider(mapService, coordinates.z, coordinates.x, coordinates.y, options.urlTemplate!);
  }
}

class _OfflineImageProvider extends ImageProvider<_OfflineImageProvider> {
  final MapService mapService;
  final int z, x, y;
  final String urlTemplate;

  _OfflineImageProvider(this.mapService, this.z, this.x, this.y, this.urlTemplate);

  @override
  Future<_OfflineImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_OfflineImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(_OfflineImageProvider key, ImageDecoderCallback decode) {
    final chunkEvents = StreamController<ImageChunkEvent>();

    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, chunkEvents, decode),
      chunkEvents: chunkEvents.stream,
      scale: 1.0,
      informationCollector: () => <DiagnosticsNode>[],
    );
  }

  Future<ui.Codec> _loadAsync(
    _OfflineImageProvider key,
    StreamController<ImageChunkEvent> chunkEvents,
    ImageDecoderCallback decode,
  ) async {
    try {
      final file = await mapService.getLocalTileFile(z, x, y);
      if (file != null && await file.exists()) {
        final bytes = await file.readAsBytes();
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        return decode(buffer);
      }
      
      final url = 'https://tile.openstreetmap.org/$z/$x/$y.png';
      final response = await http.get(Uri.parse(url), headers: {'User-Agent': 'RescueLink_Disaster_App/1.0'});
      if (response.statusCode == 200) {
        final buffer = await ui.ImmutableBuffer.fromUint8List(response.bodyBytes);
        return decode(buffer);
      }
      throw Exception('Tile not found');
    } catch (e) {
      final empty = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 1, 115, 82, 71, 66, 0, 174, 206, 28, 233, 0, 0, 0, 11, 73, 68, 65, 84, 8, 153, 99, 96, 0, 2, 0, 0, 5, 0, 1, 175, 212, 106, 176, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]);
      final buffer = await ui.ImmutableBuffer.fromUint8List(empty);
      return decode(buffer);
    } finally {
      chunkEvents.close();
    }
  }
}
