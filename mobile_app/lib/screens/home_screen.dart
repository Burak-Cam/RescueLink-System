import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:geocoding/geocoding.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';
import '../main.dart';
import '../services/ble_service.dart';
import '../services/storage_service.dart';
import '../services/gps_service.dart';
import '../services/sos_status_service.dart';
import '../services/locale_service.dart';
import '../services/whistle_service.dart';
import '../services/sms_queue_service.dart';
import '../services/map_service.dart';
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

  @override
  void initState() {
    super.initState();
    _listenForMessages();
    _listenForAcks();
    _listenForSystemEvents();
    _checkCityAndPromptMap();
  }

  Future<void> _checkCityAndPromptMap() async {
    final gps = context.read<GpsService>();
    final map = context.read<MapService>();
    final locale = context.read<LocaleService>();
    
    final connectivity = await Connectivity().checkConnectivity();
    final hasInternet = connectivity.any((r) => r != ConnectivityResult.none);
    
    if (!hasInternet) return;

    if (gps.currentPosition != null) {
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          gps.currentPosition!.latitude, 
          gps.currentPosition!.longitude
        );
        
        if (placemarks.isNotEmpty) {
          String city = placemarks.first.administrativeArea ?? placemarks.first.locality ?? "Unknown";
          if (!map.hasMapForCity(city)) {
            if (mounted) _showMapPrompt(city, locale);
          }
        }
      } catch (e) { }
    }
  }

  void _showMapPrompt(String city, LocaleService locale) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2B2B2B),
        title: Text(locale.t('map_prompt_title')),
        content: Text(locale.t('map_prompt_desc', args: {'city': city})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(locale.t('ignore'), style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("${city} map download started...")),
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

  void _listenForSystemEvents() {
    final ble = context.read<BleService>();
    final gps = context.read<GpsService>();
    final sosStatus = context.read<SosStatusService>();
    final locale = context.read<LocaleService>();

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
          gps.forceEmergencyWake();
          sosStatus.triggerAiEmergency();
          break;
        case BleSystemEvent.anomaly:
          _showAnomalyPrompt(locale);
          break;
        case BleSystemEvent.powerLost:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(locale.t('power_lost_msg')), duration: const Duration(seconds: 5)),
          );
          break;
        case BleSystemEvent.rhythmicTapping:
          HapticFeedback.heavyImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(locale.t('tapping_msg')),
              backgroundColor: const Color(0xFF2E7D32),
              duration: const Duration(seconds: 4),
            ),
          );
          break;
      }
    });
  }

  void _showAnomalyPrompt(LocaleService locale) {
    final sosStatus = context.read<SosStatusService>();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2B2B2B),
        title: Text(locale.t('anomaly_title'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: Text(locale.t('anomaly_desc')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(locale.t('no'), style: const TextStyle(color: Colors.white54))),
          ElevatedButton(onPressed: () { Navigator.pop(context); sosStatus.triggerAiEmergency(); }, child: Text(locale.t('yes'))),
        ],
      ),
    );
  }

  Future<void> _sendSos() async {
    final ble = context.read<BleService>();
    final storage = context.read<StorageService>();
    final gps = context.read<GpsService>();
    final sosStatus = context.read<SosStatusService>();
    final locale = context.read<LocaleService>();
    final smsQueue = context.read<SmsQueueService>();

    // 1. Anti-Spam: Aynı mesajsa sessizce çık (GPS uyarısı gösterme)
    if (!storage.isDevMode() && storage.getLastSosTimestamp() != null) {
      if (!sosStatus.hasPayloadChanged(_healthStatusKey, _personCount)) {
        return; 
      }
    }

    // 2. GPS Kontrolü (Sadece yeni/farklı mesaj gönderiliyorsa)
    if (!gps.hasFix && !gps.isManual) {
      bool proceed = await _showGpsWarning(locale);
      if (!proceed) return;
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

    String coords = "0.0,0.0";
    if (gps.currentPosition != null) {
      coords = "${gps.currentPosition!.latitude.toStringAsFixed(5)},${gps.currentPosition!.longitude.toStringAsFixed(5)}";
    }

    final String historyString = "SOS|${storage.getFirstName()} ${storage.getLastName()}|$coords|$healthText|$_personCount";
    smsQueue.queueSos(historyString);

    Uint8List payload;
    if (storage.isDevMode() && storage.useStringPayload()) {
      payload = utf8.encode(historyString) as Uint8List;
    } else {
      final bytes = BytesBuilder();
      bytes.addByte(0x01); 
      if (gps.currentPosition != null) {
        final byteData = ByteData(8);
        byteData.setFloat32(0, gps.currentPosition!.latitude);
        byteData.setFloat32(4, gps.currentPosition!.longitude);
        bytes.add(byteData.buffer.asUint8List());
      } else { bytes.add(Uint8List(8)); }
      int healthValue = 0;
      if (_healthStatusKey == "Lightly Injured") healthValue = 1;
      if (_healthStatusKey == "Severely Injured") healthValue = 2;
      bytes.addByte(healthValue);
      bytes.addByte(_personCount);
      payload = bytes.takeBytes();
    }

    final success = await ble.writeBinary(payload);
    if (mounted) {
      if (success) {
        await storage.saveLastSosPayload(_healthStatusKey, _personCount);
        await storage.saveSosToHistory(historyString);
        await sosStatus.setStatus(SosProcessState.sentToNode);
      } else {
        await sosStatus.setStatus(SosProcessState.idle);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(locale.t('send_failure')), backgroundColor: const Color(0xFFD32F2F)));
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
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildProfileCard(storage, gps, locale),
                  const SizedBox(height: 16),
                  _buildStatusCard(sosStatus, locale),
                  const SizedBox(height: 16),
                  if (sosStatus.state != SosProcessState.idle) _buildTruthfulProgressBar(sosStatus, locale),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _buildSosButton(ble, sosStatus, locale)),
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTruthfulProgressBar(SosStatusService sosStatus, LocaleService locale) {
    bool isSending = sosStatus.state == SosProcessState.sending;
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

  Widget _buildSosButton(BleService ble, SosStatusService sosStatus, LocaleService locale) {
    bool isConnected = ble.status == BleConnectionStatus.connected;
    bool isCooldown = sosStatus.isCooldownActive;
    bool isSending = sosStatus.state == SosProcessState.sending;
    bool isDisabled = !isConnected || isCooldown || isSending;
    return ElevatedButton.icon(
      icon: Icon(isCooldown ? Icons.lock : Icons.warning_amber_rounded, size: 32),
      label: Text(
        isCooldown 
          ? (sosStatus.isInsideBlockWindow 
              ? "${locale.t('locked')} (${(sosStatus.blockRemainingSeconds ~/ 60).toString().padLeft(2, '0')}:${(sosStatus.blockRemainingSeconds % 60).toString().padLeft(2, '0')})"
              : locale.t('locked').toUpperCase())
          : locale.t('sos_button').toUpperCase(),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: (isCooldown || isSending) ? Colors.grey.shade900 : AppTheme.primaryRed,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
        elevation: (isCooldown || isSending) ? 0 : 12, minimumSize: const Size(double.infinity, 80),
      ),
      onPressed: isDisabled ? null : _sendSos,
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

  Widget _buildSosHistory(StorageService storage, LocaleService locale) {
    final history = storage.getSosHistory();
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF2B2B2B), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
      child: history.isEmpty ? Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(locale.t('no_message'), style: const TextStyle(color: Colors.white24, fontStyle: FontStyle.italic)))) : ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.all(12), itemCount: history.length, itemBuilder: (context, index) {
        final parts = history[index].split('|'); final time = DateTime.parse(parts[0]);
        return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFD32F2F).withOpacity(0.3))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("${time.hour}:${time.minute.toString().padLeft(2, '0')} - SOS SENT", style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.w900, fontSize: 11)), const SizedBox(height: 4), Text(parts.sublist(1).join(' | '), style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'))]));
      }),
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
