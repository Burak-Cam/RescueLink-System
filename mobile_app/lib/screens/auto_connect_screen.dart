import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ble_service.dart';
import '../services/storage_service.dart';
import '../services/locale_service.dart';
import 'home_screen.dart';

class AutoConnectScreen extends StatefulWidget {
  const AutoConnectScreen({super.key});

  @override
  _AutoConnectScreenState createState() => _AutoConnectScreenState();
}

class _AutoConnectScreenState extends State<AutoConnectScreen> {
  bool _isAutoConnecting = true;
  StreamSubscription? _adapterSubscription;

  @override
  void initState() {
    super.initState();
    // Rule: Fix Race Condition - Wait for Adapter to be ON before scanning
    _adapterSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        _adapterSubscription?.cancel();
        _startLogic();
      }
    });
  }

  void _startLogic() {
    if (!mounted) return;
    context.read<BleService>().startScan();
    _initConnection();
  }

  Future<void> _initConnection() async {
    final storage = context.read<StorageService>();
    final ble = context.read<BleService>();
    final savedMac = storage.getSavedMac();

    if (savedMac != null && savedMac.isNotEmpty) {
      setState(() => _isAutoConnecting = true);
      
      // Rule: Use findDevice which waits for specific device
      final target = await ble.findDevice(savedMac);

      if (target != null) {
        final success = await ble.connect(target);
        if (success && mounted) {
          _navigateToHome();
          return;
        }
      }
    }
    
    if (mounted) {
      setState(() => _isAutoConnecting = false);
      ble.startScan();
    }
  }

  void _navigateToHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();
    final locale = context.watch<LocaleService>();

    if (_isAutoConnecting && ble.status == BleConnectionStatus.connecting) {
      return _buildAutoConnectOverlay(locale.t('establishing_tunnel'));
    }

    if (_isAutoConnecting && ble.status == BleConnectionStatus.scanning) {
      return _buildAutoConnectOverlay(locale.t('searching_gateway'));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(locale.t('app_name').toUpperCase()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: ble.status == BleConnectionStatus.scanning ? null : () => ble.startScan(),
          )
        ],
      ),
      body: Column(
        children: [
          _buildStatusHeader(ble, locale),
          if (ble.errorMessage != null)
            Container(
              color: const Color(0xFFD32F2F),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Text(
                ble.errorMessage!,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: ble.scanResults.isEmpty 
              ? _buildEmptyState(ble, locale)
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: ble.scanResults.length,
                  itemBuilder: (context, index) {
                    final result = ble.scanResults[index];
                    return _buildDeviceCard(context, result, ble, locale);
                  },
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoConnectOverlay(String message) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB71C1C), Colors.black],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_tethering, size: 100, color: Colors.white),
            const SizedBox(height: 40),
            const SizedBox(
              width: 60,
              height: 60,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 6),
            ),
            const SizedBox(height: 30),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeader(BleService ble, LocaleService locale) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      color: ble.status == BleConnectionStatus.scanning ? const Color(0xFFFFC107) : Colors.grey.shade900,
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: ble.status == BleConnectionStatus.scanning 
              ? const CircularProgressIndicator(strokeWidth: 2, color: Colors.black)
              : Icon(Icons.bluetooth, size: 16, color: ble.adapterState == BluetoothAdapterState.on ? Colors.white70 : const Color(0xFFD32F2F)),
          ),
          const SizedBox(width: 12),
          Text(
            ble.status == BleConnectionStatus.scanning 
              ? locale.t('scan_devices').toUpperCase()
              : (ble.adapterState == BluetoothAdapterState.on ? locale.t('select_device').toUpperCase() : locale.t('err_ble_off').toUpperCase()),
            style: TextStyle(
              fontWeight: FontWeight.bold, 
              fontSize: 12, 
              letterSpacing: 1, 
              color: ble.status == BleConnectionStatus.scanning ? Colors.black : Colors.white
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BleService ble, LocaleService locale) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bluetooth_searching, size: 64, color: Colors.grey.shade800),
          const SizedBox(height: 16),
          Text(
            ble.status == BleConnectionStatus.scanning ? locale.t('scan_devices') : locale.t('select_device'),
            style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(BuildContext context, ScanResult result, BleService ble, LocaleService locale) {
    final device = result.device;
    String name = device.platformName.isNotEmpty ? device.platformName : result.advertisementData.advName;
    if (name.isEmpty) name = locale.isEnglish ? "UNKNOWN NODE" : "BİLİNMEYEN NOD";

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: const Icon(Icons.router, color: Color(0xFFD32F2F)),
        ),
        title: Text(name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        subtitle: Text(device.remoteId.toString(), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        trailing: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD32F2F),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          onPressed: ble.status == BleConnectionStatus.connecting 
            ? null 
            : () async {
                final storage = context.read<StorageService>();
                final success = await ble.connect(device);
                if (success && mounted) {
                  storage.saveMac(device.remoteId.toString());
                  _navigateToHome();
                }
              },
          child: Text(locale.t('connect').toUpperCase()),
        ),
      ),
    );
  }
}
