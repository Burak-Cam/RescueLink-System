import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';
import '../services/battery_service.dart';
import '../services/ble_service.dart';
import '../services/storage_service.dart';
import '../services/gps_service.dart';
import '../services/sos_status_service.dart';
import '../services/locale_service.dart';
import '../services/whistle_service.dart';
import '../services/map_service.dart';
import '../services/ota_service.dart';
import '../theme/app_theme.dart';
import 'auto_connect_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _healthStatusKey = "Healthy";
  int _personCount = 1;
  final List<String> _incomingMessages = [];
  bool _showHistory = false;
  bool _isComaMode = false;
  
  // Active emergency tracking for UI locks
  bool _isFireActive = false;
  bool _isGasActive = false;
  bool _hasEarthquakeOccurred = false;
  String _activeSosType = ""; 

  // Environmental Data
  double _temp = 0.0;
  double _hum = 0.0;
  double _press = 0.0;
  double _iaq = 0.0;

  final PageController _pageController = PageController();

  bool _hasPromptedMap = false;

  StreamSubscription? _telemetrySub;
  StreamSubscription? _messagesSub;
  StreamSubscription? _ackSub;
  StreamSubscription? _systemEventSub;
  StreamSubscription? _otaUpdateSub;

  @override
  void initState() {
    super.initState();
    _loadComaModeState();
    _listenForMessages();
    _listenForAcks();
    _listenForSystemEvents();
    _listenForTelemetry();
    _listenForOtaUpdates();
    _checkCityAndPromptMap();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<BleService>().addListener(_onBleStateChanged);
    });
  }

  void _onBleStateChanged() {
    if (!mounted) return;
    final ble = context.read<BleService>();
    final sosStatus = context.read<SosStatusService>();
    if (ble.status == BleConnectionStatus.connected && sosStatus.state == SosProcessState.queuedOffline) {
      if (kDebugMode) print("🌐 [OFFLINE QUEUE] Connection restored! Firing queued SOS...");
      _sendSos(type: _activeSosType, fromQueue: true);
    }
  }

  void _listenForTelemetry() {
    final ble = context.read<BleService>();
    _telemetrySub = ble.telemetryStream.listen((data) {
      if (mounted) {
        setState(() {
          _temp = data['temp'] ?? _temp;
          _hum = data['hum'] ?? _hum;
          _press = data['press'] ?? _press;
          _iaq = data['iaq'] ?? _iaq;
        });
      }
    });
  }

  Future<void> _loadComaModeState() async {
    final storage = context.read<StorageService>();
    final savedMode = storage.getComaMode();
    if (savedMode != null) {
      setState(() { _isComaMode = savedMode; });
    }
  }

  @override
  void dispose() {
    context.read<BleService>().removeListener(_onBleStateChanged);
    _telemetrySub?.cancel();
    _messagesSub?.cancel();
    _ackSub?.cancel();
    _systemEventSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _checkCityAndPromptMap() async {
    final gps = context.read<GpsService>();
    final map = context.read<MapService>();
    final locale = context.read<LocaleService>();
    
    final connectivity = await Connectivity().checkConnectivity();
    final hasInternet = connectivity.any((r) => r != ConnectivityResult.none);
    
    if (!hasInternet) return;

    if (gps.currentPosition != null) {
      if (!map.hasMapForCity("LocalCache") && !_hasPromptedMap) {
        _hasPromptedMap = true;
        if (mounted) _showMapPrompt(gps.currentPosition!.latitude, gps.currentPosition!.longitude, locale);
      }
    } else {
      gps.addListener(_onGpsUpdate);
    }
  }

  void _onGpsUpdate() {
    if (!mounted) return;
    final gps = context.read<GpsService>();
    if (gps.currentPosition != null && !_hasPromptedMap) {
      gps.removeListener(_onGpsUpdate);
      _checkCityAndPromptMap();
    }
  }

  void _showMapPrompt(double lat, double lon, LocaleService locale) {
    final map = context.read<MapService>();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2B2B2B),
        title: Text(locale.isEnglish ? "Download Offline Map" : "Çevrimdışı Harita İndir"),
        content: Text(locale.isEnglish 
          ? "Would you like to download a 2km high-detail map radius around your current location for offline emergency use?" 
          : "Acil durumlarda internetsiz kullanabilmek için bulunduğunuz konumun 2KM etrafındaki detaylı haritayı indirmek ister misiniz?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(locale.t('ignore'), style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              map.downloadLocalMapCache(lat, lon);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(locale.isEnglish ? "Micro-Map download started..." : "Mikro-Harita indirmesi başladı...")),
              );
            },
            child: Text(locale.t('download')),
          ),
        ],
      ),
    );
  }

  void _listenForMessages() {
    final ble = context.read<BleService>();
    final locale = context.read<LocaleService>();
    ble.hqMessages.listen((message) {
      if (mounted) {
        setState(() {
          _incomingMessages.insert(0, "${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')} - $message");
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(locale.t('hq_broadcast_received')),
            backgroundColor: const Color(0xFF2E7D32),
          ),
        );
      }
    });
  }

  void _listenForAcks() {
    final ble = context.read<BleService>();
    final sosStatus = context.read<SosStatusService>();

    ble.ackStream.listen((ack) async {
      if (mounted) {
        if (ack == 0x06 || (ack is String && ack.contains("DELIVERED_TO_HQ"))) {
          await sosStatus.setStatus(SosProcessState.deliveredToHq);
        } else if (ack is String && ack.contains("SENT_TO_NODE")) {
          await sosStatus.setStatus(SosProcessState.sentToNode);
        }
      }
    });
  }

  void _listenForOtaUpdates() {
    final ble = context.read<BleService>();
    final locale = context.read<LocaleService>();
    _otaUpdateSub = ble.otaUpdateEventStream.listen((event) {
      if (mounted) {
        _showOtaPrompt(locale, event.version);
      }
    });
  }

  void _listenForSystemEvents() {
    final ble = context.read<BleService>();
    final gps = context.read<GpsService>();
    final sosStatus = context.read<SosStatusService>();
    final locale = context.read<LocaleService>();
    final whistle = context.read<WhistleService>();
    final battery = context.read<BatteryStateService>();

    ble.systemEventStream.listen((event) {
      if (!mounted) return;
      if (kDebugMode) print('🎯 EVENT YAKALANDI: $event');

      switch (event) {
        case BleSystemEvent.heartbeatLost:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(locale.isEnglish ? "Hardware Unreachable - Protection Disabled" : "Donanım Erişilemez - Koruma Devre Dışı"),
              backgroundColor: const Color(0xFFD32F2F),
              duration: const Duration(seconds: 5),
            ),
          );
          break;
        case BleSystemEvent.heartbeatRestored:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(locale.isEnglish ? "Hardware Synchronized" : "Donanım Senkronize Edildi"),
              backgroundColor: const Color(0xFF2E7D32),
            ),
          );
          break;
        case BleSystemEvent.earthquake:
          _hasEarthquakeOccurred = true;
          if (_pageController.hasClients) {
            _pageController.animateToPage(0, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
          }
          gps.forceEmergencyWake();
          sosStatus.triggerAiEmergency(type: "EARTHQUAKE");
          break;
        case BleSystemEvent.anomaly:
          _showAnomalyPrompt(locale);
          break;
        case BleSystemEvent.fire:
          setState(() { _isFireActive = true; });
          if (_pageController.hasClients) {
            _pageController.animateToPage(1, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
          }
          _showDeadMansSwitchDialog(locale, "FIRE");
          break;
        case BleSystemEvent.badAir:
          setState(() { _isGasActive = true; });
          if (_pageController.hasClients) {
            _pageController.animateToPage(1, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
          }
          _showDeadMansSwitchDialog(locale, "GAS");
          break;
        case BleSystemEvent.highHumidity:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(locale.isEnglish ? "Info: High humidity / Flood risk detected." : "Bilgi: Yüksek nem / Su baskını riski."),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 5),
            ),
          );
          break;
        case BleSystemEvent.gasLeak:
          setState(() { _isGasActive = true; });
          if (_pageController.hasClients) {
            _pageController.animateToPage(1, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
          }
          _showDeadMansSwitchDialog(locale, "GAS_LEAK");
          break;
        case BleSystemEvent.criticalTemperature:
          setState(() { _isFireActive = true; });
          if (_pageController.hasClients) {
            _pageController.animateToPage(1, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
          }
          _showDeadMansSwitchDialog(locale, "CRITICAL_TEMP");
          break;
        case BleSystemEvent.rhythmicTapping:
          final storage = context.read<StorageService>();
          if (_hasEarthquakeOccurred || storage.isDevMode()) {
            HapticFeedback.heavyImpact();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(locale.t('tapping_msg')),
                backgroundColor: const Color(0xFF2E7D32),
                duration: const Duration(seconds: 4),
              ),
            );
            _sendSos(type: "TAPPING");
          } else {
            if (kDebugMode) print("Tapping ignored: No earthquake occurred.");
          }
          break;
        default:
          break;
      }
    });
  }

  void _showAnomalyPrompt(LocaleService locale) {
    final ble = context.read<BleService>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2B2B2B),
        title: Text(locale.isEnglish ? "Did you feel shaking?" : "Sarsıntı hissettiniz mi?", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: Text(locale.isEnglish ? "The AI detected an anomaly. Was it an earthquake or just noise?" : "Yapay zeka bir anomali saptadı. Bu bir deprem miydi, yoksa sadece gürültü/hata mı?"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ble.writeText("LABEL|noise");
            },
            child: Text(locale.isEnglish ? "No (Noise/Error)" : "Hayır (Gürültü/Hata)", style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ble.writeText("LABEL|deprem");
            },
            child: Text(locale.isEnglish ? "Yes (Earthquake)" : "Evet (Deprem)"),
          ),
        ],
      ),
    );
  }

  void _showOtaPrompt(LocaleService locale, String version) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2B2B2B),
        title: Text(locale.isEnglish ? "Firmware Update Available" : "Yeni Güncelleme Var!", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: Text(locale.isEnglish ? "A new version ($version) for the Edge Node is available. How would you like to update?" : "Edge Node için yeni bir sürüm ($version) mevcut. Nasıl güncellemek istersiniz?"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<BleService>().writeText("OTA|hayir");
            },
            child: Text(locale.isEnglish ? "Cancel" : "İptal", style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
            onPressed: () {
              Navigator.pop(context);
              _startBleOtaProcess(locale);
            },
            child: Text(locale.isEnglish ? "Update via BLE (Offline)" : "BLE ile Güncelle (Offline)"),
          ),
        ],
      ),
    );
  }

  void _startBleOtaProcess(LocaleService locale) async {
    final otaService = context.read<OtaService>();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Consumer<OtaService>(
        builder: (context, ota, child) {
          return AlertDialog(
            backgroundColor: const Color(0xFF2B2B2B),
            title: Text(locale.isEnglish ? "Flashing Firmware..." : "Firmware Yükleniyor...", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (ota.error != null)
                  Text(ota.error!, style: const TextStyle(color: Color(0xFFD32F2F)))
                else ...[
                  LinearProgressIndicator(
                    value: ota.progress,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2E7D32)),
                  ),
                  const SizedBox(height: 16),
                  Text("${(ota.progress * 100).toStringAsFixed(1)}%", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 8),
                  Text(
                    locale.isEnglish ? "Please keep the app open and near the device." : "Lütfen uygulamayı açık tutun ve cihaza yakın durun.",
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ]
              ],
            ),
            actions: [
              if (!ota.isFlashing)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(locale.isEnglish ? "Close" : "Kapat", style: const TextStyle(color: Colors.white)),
                ),
            ],
          );
        },
      ),
    );

    // In a real scenario, fetch this URL from your API/GitHub releases. 
    // For now, using a placeholder/hardcoded URL to match the design.
    await otaService.startBleOta();
  }

  void _showDeadMansSwitchDialog(LocaleService locale, String type) {
    final ble = context.read<BleService>();
    final sosStatus = context.read<SosStatusService>();
    final gps = context.read<GpsService>();
    final whistle = context.read<WhistleService>();
    
    Timer? switchTimer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2B2B2B),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFD32F2F), size: 28),
            const SizedBox(width: 8),
            Expanded(child: Text(locale.isEnglish ? "ARE YOU CONSCIOUS?" : "BİLİNCİNİZ AÇIK MI?", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16))),
          ],
        ),
        content: Text(locale.isEnglish 
          ? "Critical environmental danger detected ($type). If you do not respond in 60 seconds, an auto-SOS will be dispatched." 
          : "Kritik çevresel tehlike algılandı ($type). 60 saniye içinde yanıt vermezseniz otomatik SOS gönderilecektir."),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () { 
                switchTimer?.cancel();
                whistle.stopWhistle(); 
                ble.sendSilenceCommand(); 
                setState(() { 
                  _isFireActive = false; 
                  _isGasActive = false; 
                  _activeSosType = ""; 
                });
                Navigator.pop(context); 
              }, 
              child: Text(
                locale.isEnglish ? "SILENCE (I'm Conscious)" : "SUSTUR (Bilincim Açık)",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );

    switchTimer = Timer(const Duration(seconds: 60), () {
      if (mounted) {
        Navigator.pop(context); 
        gps.forceEmergencyWake();
        sosStatus.triggerAiEmergency();
        _sendSos(type: type);
      }
    });
  }

  Future<void> _sendSos({String type = "EARTHQUAKE", bool fromQueue = false}) async {
    final ble = context.read<BleService>();
    final storage = context.read<StorageService>();
    final gps = context.read<GpsService>();
    final sosStatus = context.read<SosStatusService>();
    final locale = context.read<LocaleService>();

    setState(() { _activeSosType = type; });

    // 1. Anti-Spam: Aynı mesajsa sessizce çık (GPS uyarısı gösterme)
    if (!storage.isDevMode() && storage.getLastSosTimestamp() != null && !fromQueue) {
      if (!sosStatus.hasPayloadChanged(_healthStatusKey, _personCount)) {
        return; 
      }
    }

    // 2. GPS Kontrolü (Sadece yeni/farklı mesaj gönderiliyorsa)
    if (!gps.hasFix && !gps.isManual && !fromQueue) {
      bool proceed = await _showGpsWarning(locale);
      if (!proceed) return;
    }

    // NEW LOGIC FOR OFFLINE QUEUING:
    if (ble.status != BleConnectionStatus.connected && !fromQueue) {
      gps.forceEmergencyWake();
      await sosStatus.setStatus(SosProcessState.queuedOffline);
      return;
    }

    // 3. Gönderim Durumunu Başlat (Bu aşamadan sonra buton kilitlenir)
    gps.forceEmergencyWake();
    sosStatus.startSending();

    final country = storage.getCountry();
    final forced = storage.getForceSosLang();
    bool useTr = forced == "TR" || (forced == null && (country == 'Türkiye' || country == 'Turkey'));

    final trMap = {'Healthy': 'SAĞLIKLI', 'Lightly Injured': 'HAFİF YARALI', 'Severely Injured': 'AĞIR YARALI'};
    final enMap = {'Healthy': 'HEALTHY', 'Lightly Injured': 'LIGHTLY INJURED', 'Severely Injured': 'SEVERELY INJURED'};
    String healthText = useTr ? (trMap[_healthStatusKey] ?? _healthStatusKey) : (enMap[_healthStatusKey] ?? _healthStatusKey);
    String tappingText = useTr ? "RİTMİK VURUŞ ALGILANDI" : "RHYTHMIC TAPPING DETECTED";

    String coords = "0.0,0.0";
    if (gps.currentPosition != null) {
      coords = "${gps.currentPosition!.latitude.toStringAsFixed(5)},${gps.currentPosition!.longitude.toStringAsFixed(5)}";
    }

    String historyString;
    if (type == "EARTHQUAKE") {
      historyString = "SOS|$type|${storage.getFirstName()} ${storage.getLastName()}|$coords|$healthText|$_personCount";
    } else if (type == "TAPPING") {
      historyString = "SOS|$type|${storage.getFirstName()} ${storage.getLastName()}|$coords|$tappingText";
    } else {
      String dangerText = useTr ? "$type TEHLİKESİ BİLDİRİLDİ" : "$type DANGER REPORTED";
      historyString = "SOS|$type|${storage.getFirstName()} ${storage.getLastName()}|$coords|$dangerText";
    }

    Uint8List payload;
    if (storage.isDevMode() && storage.useStringPayload()) {
      payload = utf8.encode(historyString) as Uint8List;
    } else {
      final byteData = ByteData(12);
      
      // 0. Byte: Header
      byteData.setUint8(0, 0x01); 
      
      // 1. Byte: Afet Tipi
      int typeValue = 0;
      if (type == "EARTHQUAKE") typeValue = 1;
      else if (type == "FIRE") typeValue = 2;
      else if (type == "GAS") typeValue = 3;
      else if (type == "TAPPING") typeValue = 4;
      byteData.setUint8(1, typeValue);
      
      // 2-9. Bytes: GPS (Little-Endian)
      if (gps.currentPosition != null) {
        byteData.setFloat32(2, gps.currentPosition!.latitude, Endian.little);
        byteData.setFloat32(6, gps.currentPosition!.longitude, Endian.little);
      } else {
        byteData.setFloat32(2, 0.0, Endian.little);
        byteData.setFloat32(6, 0.0, Endian.little);
      }
      
      // 10-11. Bytes: Sağlık ve Kişi Sayısı (HER DURUMDA GÖNDERİLMELİ)
      int healthValue = 0;
      if (_healthStatusKey == "Lightly Injured") healthValue = 1;
      if (_healthStatusKey == "Severely Injured") healthValue = 2;
      byteData.setUint8(10, healthValue);
      byteData.setUint8(11, _personCount);
      
      payload = byteData.buffer.asUint8List();
    }

    final success = await ble.writeBinary(payload, isHighPriority: true);
    if (mounted) {
      if (success) {
        await storage.saveLastSosPayload(_healthStatusKey, _personCount);
        await storage.saveSosToHistory(historyString);
        await sosStatus.setStatus(SosProcessState.sentToNode);
        setState(() {}); // <-- UPDATE UI FOR HISTORY
      } else {
        // Cihaz fiziksel olarak kapandıysa ancak BLE hala 'bağlı' sanıyorsa write işlemi başarısız olur.
        // Bu durumda paketi çöpe atmak yerine Çevrimdışı Kuyruğa (Offline Queue) devrediyoruz.
        await sosStatus.setStatus(SosProcessState.queuedOffline);
        if (!fromQueue) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(locale.isEnglish ? "Connection error. SOS queued for auto-retry." : "Bağlantı hatası. SOS kuyruğa alındı."), 
              backgroundColor: const Color(0xFFFF9800),
            )
          );
        }
      }
    }
  }

  Future<bool> _showGpsWarning(LocaleService locale) async {
    return await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2B2B2B),
        title: Text(locale.t('no_gps_fix_title'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: Text(locale.t('no_gps_fix_desc')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(locale.t('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(locale.t('send_anyway'))),
        ],
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();
    final storage = context.watch<StorageService>();
    final gps = context.watch<GpsService>();
    final sosStatus = context.watch<SosStatusService>();
    final locale = context.watch<LocaleService>();
    final whistle = context.watch<WhistleService>();
    final battery = context.watch<BatteryStateService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(locale.t('app_name').toUpperCase()),
        leading: IconButton(
          icon: const Icon(Icons.person),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen())),
        ),
        actions: [
          if (battery.isCritical) const Padding(padding: EdgeInsets.only(right: 8.0), child: Icon(Icons.battery_alert, color: Color(0xFFD32F2F), size: 20)),
          _buildGpsStatusIndicator(gps, locale),
          TextButton(onPressed: () => locale.toggleLocale(), child: Text(locale.isEnglish ? "TR" : "EN", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          IconButton(
            icon: const Icon(Icons.link_off, color: Color(0xFFD32F2F)),
            onPressed: () async {
              await ble.disconnect();
              await storage.clearMac();
              if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AutoConnectScreen()));
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildErrorBanners(ble, gps, locale),
          // Page Indicator
          Container(
            color: const Color(0xFF1A1A1A),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildTabIndicator(0, locale.isEnglish ? "EARTHQUAKE" : "DEPREM", Icons.waves),
                _buildTabIndicator(1, locale.isEnglish ? "FIRE / GAS" : "YANGIN / GAZ", Icons.local_fire_department),
              ],
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) => setState(() {}),
              children: [
                _buildEarthquakeScene(ble, storage, gps, sosStatus, locale, whistle, battery),
                _buildFireGasScene(ble, storage, gps, sosStatus, locale, whistle, battery),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabIndicator(int pageIndex, String title, IconData icon) {
    bool isActive = _pageController.hasClients ? (_pageController.page?.round() ?? 0) == pageIndex : pageIndex == 0;
    Color activeColor = pageIndex == 0 ? const Color(0xFFFFC107) : const Color(0xFFD32F2F);
    
    return GestureDetector(
      onTap: () {
        if (_pageController.hasClients) {
          _pageController.animateToPage(pageIndex, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
        }
      },
      child: Column(
        children: [
          Icon(icon, color: isActive ? activeColor : Colors.white38, size: 24),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(color: isActive ? activeColor : Colors.white38, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 4),
          Container(height: 3, width: 40, color: isActive ? activeColor : Colors.transparent),
        ],
      ),
    );
  }

  Widget _buildEarthquakeScene(BleService ble, StorageService storage, GpsService gps, SosStatusService sosStatus, LocaleService locale, WhistleService whistle, BatteryStateService battery) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildProfileCard(storage, gps, locale),
          const SizedBox(height: 12),
          _buildComaModeToggle(ble, locale),
          const SizedBox(height: 16),
          _buildStatusCard(sosStatus, locale),
          const SizedBox(height: 16),
          if (sosStatus.state != SosProcessState.idle && (_activeSosType == "EARTHQUAKE" || _activeSosType == "")) _buildTruthfulProgressBar(sosStatus, locale),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildSosButton(ble, sosStatus, locale, type: "EARTHQUAKE")),
              const SizedBox(width: 12),
              _buildWhistleButton(whistle, battery, locale),
            ],
          ),
          const SizedBox(height: 24),
          _buildHqAndHistoryToggle(locale),
          const SizedBox(height: 12),
          _showHistory ? _buildSosHistory(storage, locale) : _buildHqChannel(locale),
        ],
      ),
    );
  }

  Widget _buildComaModeToggle(BleService ble, LocaleService locale) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _isComaMode ? const Color(0xFF2E7D32).withValues(alpha: 0.2) : const Color(0xFF2B2B2B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _isComaMode ? const Color(0xFF2E7D32) : Colors.white10),
      ),
      child: Row(
        children: [
          Icon(Icons.power_settings_new, color: _isComaMode ? const Color(0xFF2E7D32) : Colors.white54, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(locale.isEnglish ? "DISASTER MODE (POWER SAVING)" : "AFET MODU (GÜÇ TASARRUFU)", style: TextStyle(color: _isComaMode ? const Color(0xFF2E7D32) : Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                if (_isComaMode)
                  Text(locale.isEnglish ? "Low power. Only listening for taps." : "Düşük güç. Sadece vuruşlar dinleniyor.", style: const TextStyle(color: Colors.white70, fontSize: 10)),
              ],
            ),
          ),
          Switch(
            value: _isComaMode,
            activeColor: const Color(0xFF2E7D32),
            onChanged: (val) {
              setState(() { _isComaMode = val; });
              final storage = context.read<StorageService>();
              storage.setComaMode(val);
              if (val) {
                ble.enableComaMode();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(locale.isEnglish ? "Coma Mode Enabled" : "Afet Modu Aktif"), backgroundColor: const Color(0xFF2E7D32)));
              } else {
                ble.disableComaMode();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(locale.isEnglish ? "Normal Mode Restored" : "Normal Moda Dönüldü")));
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFireGasScene(BleService ble, StorageService storage, GpsService gps, SosStatusService sosStatus, LocaleService locale, WhistleService whistle, BatteryStateService battery) {
    bool hasActiveAlert = _isFireActive || _isGasActive;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: hasActiveAlert ? const Color(0x33D32F2F) : const Color(0xFF2B2B2B), 
              borderRadius: BorderRadius.circular(16), 
              border: Border.all(color: hasActiveAlert ? const Color(0xFFD32F2F) : Colors.white10)
            ),
            child: Column(
              children: [
                Icon(
                  hasActiveAlert ? Icons.local_fire_department : Icons.security, 
                  color: hasActiveAlert ? const Color(0xFFD32F2F) : const Color(0xFF2E7D32), 
                  size: 48
                ),
                const SizedBox(height: 12),
                Text(
                  hasActiveAlert 
                    ? (locale.isEnglish ? "FIRE & GAS ALERT" : "YANGIN & GAZ ALARMI")
                    : (locale.isEnglish ? "ENVIRONMENT SAFE" : "ORTAM GÜVENLİ"), 
                  style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w900, 
                    color: hasActiveAlert ? Colors.white : const Color(0xFF2E7D32), 
                    letterSpacing: 2
                  )
                ),
                const SizedBox(height: 8),
                Text(
                  hasActiveAlert
                    ? (locale.isEnglish ? "Stay low to the ground. Check doors for heat before opening. Evacuate immediately." : "Yere yakın durun. Kapıları açmadan önce sıcaklığını kontrol edin. Derhal tahliye olun.")
                    : (locale.isEnglish ? "BME680 sensors report normal temperature and air quality." : "Sensörler normal sıcaklık ve hava kalitesi raporluyor."), 
                  textAlign: TextAlign.center, 
                  style: const TextStyle(color: Colors.white70, fontSize: 13)
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Environmental Dashboard
          if (!hasActiveAlert) _buildEnvironmentalDashboard(locale),
          const SizedBox(height: 16),
          if (sosStatus.state != SosProcessState.idle && (_activeSosType == "FIRE" || _activeSosType == "GAS" || _activeSosType == "UNCERTAIN")) _buildTruthfulProgressBar(sosStatus, locale),
          const SizedBox(height: 16),
          _buildSosButton(ble, sosStatus, locale, type: "FIRE", color: const Color(0xFFD32F2F), label: locale.isEnglish ? "FIRE SOS" : "YANGIN SOS"),
          const SizedBox(height: 12),
          _buildSosButton(ble, sosStatus, locale, type: "GAS", color: const Color(0xFFFF9800), label: locale.isEnglish ? "GAS LEAK SOS" : "GAZ KAÇAĞI SOS"),
          const SizedBox(height: 24),
          _buildHqAndHistoryToggle(locale),
          const SizedBox(height: 12),
          _showHistory ? _buildSosHistory(storage, locale, filterTypes: ["FIRE", "GAS"]) : _buildHqChannel(locale),
        ],
      ),
    );
  }

  Widget _buildEnvironmentalDashboard(LocaleService locale) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_outlined, color: Colors.white38, size: 16),
              const SizedBox(width: 8),
              Text(locale.isEnglish ? "LIVE SENSOR TELEMETRY" : "CANLI SENSÖR VERİLERİ", style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildTelemetryItem(Icons.thermostat, "${_temp.toStringAsFixed(1)}°C", locale.isEnglish ? "TEMP" : "SICAKLIK", _temp > 45 ? Colors.red : Colors.orange),
              _buildTelemetryItem(Icons.water_drop, "${_hum.toStringAsFixed(0)}%", locale.isEnglish ? "HUM" : "NEM", Colors.blue),
              _buildTelemetryItem(Icons.compress, "${_press.toStringAsFixed(0)} hPa", locale.isEnglish ? "PRESS" : "BASINÇ", Colors.green),
              _buildTelemetryItem(Icons.air, _iaq.toStringAsFixed(0), locale.isEnglish ? "IAQ" : "HAVA", _iaq > 150 ? Colors.red : Colors.teal),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryItem(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color.withOpacity(0.7), size: 20),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, fontFamily: 'monospace')),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildTruthfulProgressBar(SosStatusService sosStatus, LocaleService locale) {
    bool isQueued = sosStatus.state == SosProcessState.queuedOffline;
    bool isSending = sosStatus.state == SosProcessState.sending || isQueued;
    bool isDeliveredToNode = sosStatus.state == SosProcessState.sentToNode || sosStatus.state == SosProcessState.deliveredToHq;
    bool isHqConfirmed = sosStatus.hqConfirmed;
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Row(
        children: [
          _buildTruthStep(locale.t('step_sending'), isSending || isDeliveredToNode, pulse: isSending),
          _buildTruthConnector(isDeliveredToNode),
          _buildTruthStep(locale.t('step_node'), isDeliveredToNode, pulse: isDeliveredToNode && !isHqConfirmed),
          _buildTruthConnector(isHqConfirmed),
          _buildTruthStep(locale.t('step_hq'), isHqConfirmed, pulse: false, color: const Color(0xFF2E7D32)),
        ],
      ),
    );
  }

  Widget _buildTruthStep(String label, bool active, {bool pulse = false, Color? color}) {
    return Column(
      children: [
        Icon(active ? Icons.check_circle : Icons.radio_button_unchecked, color: active ? (color ?? const Color(0xFF2E7D32)) : Colors.white24, size: 24),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: active ? Colors.white : Colors.white24)),
      ],
    );
  }

  Widget _buildTruthConnector(bool active) {
    return Expanded(child: Container(height: 3, margin: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(color: active ? const Color(0xFF2E7D32) : Colors.white10, borderRadius: BorderRadius.circular(2))));
  }

  Widget _buildErrorBanners(BleService ble, GpsService gps, LocaleService locale) {
    List<Widget> banners = [];
    if (ble.adapterState == BluetoothAdapterState.off) banners.add(_buildBanner(locale.t('err_ble_off'), Icons.bluetooth_disabled));
    if (gps.status == GpsStatus.disabled) {
      banners.add(_buildBanner(locale.t('err_gps_off'), Icons.location_off, onAction: () => gps.openLocationSettings(), actionLabel: locale.t('open_settings')));
    } else if (gps.status == GpsStatus.deniedForever) {
      banners.add(_buildBanner(locale.t('err_gps_forever'), Icons.gpp_bad, onAction: () => gps.openSettings(), actionLabel: locale.t('open_settings')));
    }
    return Column(children: banners);
  }

  Widget _buildBanner(String message, IconData icon, {VoidCallback? onAction, String? actionLabel}) {
    return Container(
      color: const Color(0xFFD32F2F),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
          if (onAction != null) TextButton(onPressed: onAction, child: Text(actionLabel!.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, decoration: TextDecoration.underline))),
        ],
      ),
    );
  }

  Widget _buildWhistleButton(WhistleService whistle, BatteryStateService battery, LocaleService locale) {
    return Container(
      height: 80, width: 80,
      decoration: BoxDecoration(
        color: whistle.isPlaying ? const Color(0xFFFFC107) : const Color(0xFF2B2B2B),
        borderRadius: BorderRadius.circular(15), border: Border.all(color: whistle.isPlaying ? const Color(0xFFFFC107) : Colors.white12),
      ),
      child: IconButton(
        icon: Icon(whistle.isPlaying ? Icons.emergency : Icons.volume_up, color: whistle.isPlaying ? Colors.black : Colors.white, size: 40),
        onPressed: () => whistle.toggleWhistle(isCriticalBattery: battery.isCritical),
      ),
    );
  }

  Widget _buildSosButton(BleService ble, SosStatusService sosStatus, LocaleService locale, {String type = "EARTHQUAKE", Color color = AppTheme.primaryRed, String? label}) {
    bool isConnected = ble.status == BleConnectionStatus.connected;
    bool isCooldown = sosStatus.isLockedFor(type);
    bool isSending = sosStatus.state == SosProcessState.sending || sosStatus.state == SosProcessState.queuedOffline;
    
    bool isDisabled = isCooldown || isSending;
    String buttonText = label ?? locale.t('sos_button').toUpperCase();
    
    String lockedText = locale.t('locked').toUpperCase();
    if ((type == "EARTHQUAKE" || type == "TAPPING") && isCooldown && sosStatus.isInsideBlockWindow) {
      lockedText = "${locale.t('locked')} (${(sosStatus.blockRemainingSeconds ~/ 60).toString().padLeft(2, '0')}:${(sosStatus.blockRemainingSeconds % 60).toString().padLeft(2, '0')})";
    }

    return ElevatedButton.icon(
      icon: Icon(isCooldown ? Icons.lock : Icons.warning_amber_rounded, size: 32),
      label: Text(
        isCooldown ? lockedText : buttonText,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: isDisabled ? Colors.grey.shade900 : color,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
        elevation: isDisabled ? 0 : 12, minimumSize: const Size(double.infinity, 80),
      ),
      onPressed: isDisabled ? null : () => _sendSos(type: type),
    );
  }

  Widget _buildStatusCard(SosStatusService sosStatus, LocaleService locale) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: Text(locale.t('health_status').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 12))),
                Flexible(
                  child: DropdownButton<String>(
                    isExpanded: true, value: _healthStatusKey, dropdownColor: const Color(0xFF2B2B2B),
                    underline: Container(height: 2, color: const Color(0xFFD32F2F)),
                    items: [
                      DropdownMenuItem(value: "Healthy", child: Text(locale.t('healthy'), style: const TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: "Lightly Injured", child: Text(locale.t('light_injury'), style: const TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: "Severely Injured", child: Text(locale.t('heavy_injury'), style: const TextStyle(fontSize: 12))),
                    ],
                    onChanged: (val) { setState(() { _healthStatusKey = val!; }); },
                  ),
                ),
              ],
            ),
            const Divider(height: 40, color: Colors.white10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: Text(locale.t('how_many').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 12))),
                Row(
                  children: [
                    _buildCountBtn(Icons.remove, () { if (_personCount > 1) setState(() { _personCount--; }); }),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text("$_personCount", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900))),
                    _buildCountBtn(Icons.add, () { setState(() { _personCount++; }); }),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountBtn(IconData icon, VoidCallback onPressed) {
    return Container(
      width: 36, height: 36,
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
      child: IconButton(icon: Icon(icon, color: Colors.white, size: 16), padding: EdgeInsets.zero, onPressed: onPressed),
    );
  }

  Widget _buildGpsStatusIndicator(GpsService gps, LocaleService locale) {
    Color color; IconData icon;
    if (gps.status == GpsStatus.fixed) {
      if (gps.isTrackingActive) {
        color = const Color(0xFF2E7D32); // Green: Fixed and Active
      } else {
        color = const Color(0xFFFFC107); // Yellow: Fixed but Sleeping
      }
      icon = Icons.gps_fixed;
    } else if (gps.status == GpsStatus.searching) {
      color = const Color(0xFFFFC107); // Yellow: Searching
      icon = Icons.gps_not_fixed;
    } else {
      color = const Color(0xFFD32F2F); // Red: Off/Denied
      icon = Icons.gps_off;
    }
    return Row(children: [Icon(icon, color: color, size: 20), const SizedBox(width: 8)]);
  }

  Widget _buildProfileCard(StorageService storage, GpsService gps, LocaleService locale) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFF2B2B2B), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text("${storage.getFirstName()} ${storage.getLastName()}".toUpperCase(), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white))),
              const Icon(Icons.person, color: Colors.white38, size: 20),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.my_location, color: Color(0xFFD32F2F), size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(gps.currentPosition != null ? "${gps.currentPosition!.latitude.toStringAsFixed(5)}, ${gps.currentPosition!.longitude.toStringAsFixed(5)}" : locale.t('searching_gps'), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, fontFamily: 'monospace'))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHqAndHistoryToggle(LocaleService locale) {
    return Row(children: [_buildToggleButton(locale.t('hq_channel').toUpperCase(), !_showHistory, () => setState(() => _showHistory = false)), const SizedBox(width: 12), _buildToggleButton(locale.t('history').toUpperCase(), _showHistory, () => setState(() => _showHistory = true))]);
  }

  Widget _buildToggleButton(String label, bool active, VoidCallback onTap) {
    return Expanded(child: InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: active ? const Color(0xFFFFC107) : Colors.transparent, borderRadius: BorderRadius.circular(8), border: Border.all(color: active ? const Color(0xFFFFC107) : Colors.white24)), child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: active ? Colors.black : Colors.white54)))));
  }

  Widget _buildSosHistory(StorageService storage, LocaleService locale, {List<String>? filterTypes}) {
    List<String> history = storage.getSosHistory();
    
    // Filter history based on scene
    List<String> filteredHistory = history.where((item) {
      final parts = item.split('|');
      // New format: TIMESTAMP|SOS|TYPE|... (length >= 3)
      // Legacy format: SOS|TYPE|... (length >= 2)
      
      String? entryType;
      if (parts.length >= 3 && parts[1] == "SOS") {
        entryType = parts[2];
      } else if (parts.length >= 2 && parts[0] == "SOS") {
        entryType = parts[1];
      }

      if (filterTypes != null && filterTypes.isNotEmpty) {
        return filterTypes.contains(entryType);
      } else {
        // Default to Earthquake & Tapping for the first scene
        return entryType == "EARTHQUAKE" || entryType == "TAPPING";
      }
    }).toList();

    // Limit to 10 items to prevent UI bloat
    if (filteredHistory.length > 10) filteredHistory = filteredHistory.take(10).toList();

    return Container(
      decoration: BoxDecoration(color: const Color(0xFF2B2B2B), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
      child: filteredHistory.isEmpty 
        ? Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(locale.t('no_message'), style: const TextStyle(color: Colors.white24, fontStyle: FontStyle.italic)))) 
        : ListView.builder(
            shrinkWrap: true, 
            physics: const NeverScrollableScrollPhysics(), 
            padding: const EdgeInsets.all(12), 
            itemCount: filteredHistory.length, 
            itemBuilder: (context, index) {
              final parts = filteredHistory[index].split('|'); 
              
              DateTime? time;
              String? type;
              String details = "";

              if (parts.length >= 3 && parts[1] == "SOS") {
                // New Format: TIMESTAMP|SOS|TYPE|NAME|COORDS|HEALTH|COUNT
                time = DateTime.tryParse(parts[0]);
                type = parts[2];
                details = parts.sublist(3).join(' | ');
              } else if (parts.length >= 2 && parts[0] == "SOS") {
                // Legacy Format: SOS|TYPE|NAME|COORDS|HEALTH|COUNT
                type = parts[1];
                details = parts.sublist(2).join(' | ');
              }

              time ??= DateTime.now();
              type ??= "SOS";
              
              Color typeColor = (type == "FIRE" || type == "GAS") ? const Color(0xFFD32F2F) : const Color(0xFFFFC107);
              String formattedDate = "${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
              
              return Container(
                margin: const EdgeInsets.only(bottom: 8), 
                padding: const EdgeInsets.all(12), 
                decoration: BoxDecoration(
                  color: Colors.black, 
                  borderRadius: BorderRadius.circular(8), 
                  border: Border.all(color: typeColor.withOpacity(0.3))
                ), 
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, 
                  children: [
                    Text(
                      "$formattedDate - $type SENT", 
                      style: TextStyle(color: typeColor, fontWeight: FontWeight.w900, fontSize: 11)
                    ), 
                    const SizedBox(height: 4), 
                    Text(
                      details, 
                      style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace')
                    )
                  ]
                )
              );
            }
          ),
    );
  }

  Widget _buildHqChannel(LocaleService locale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [const Icon(Icons.cell_tower, color: Color(0xFFFFC107), size: 18), const SizedBox(width: 8), Text(locale.t('hq_channel').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, color: Color(0xFFFFC107), fontSize: 12))]),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(color: const Color(0xFF2B2B2B), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
          child: _incomingMessages.isEmpty ? Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(locale.t('no_message'), style: const TextStyle(color: Colors.white24, fontStyle: FontStyle.italic)))) : ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.all(12), itemCount: _incomingMessages.length, itemBuilder: (context, index) {
            return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.withOpacity(0.3))), child: Text(_incomingMessages[index], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12)));
          }),
        ),
      ],
    );
  }
}
