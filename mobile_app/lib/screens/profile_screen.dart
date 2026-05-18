import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../services/storage_service.dart';
import '../services/locale_service.dart';
import '../services/gps_service.dart';
import '../services/foreground_service.dart';
import '../services/ble_service.dart';
import 'location_picker_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  String? _selectedCountry;

  bool _isDevMode = false;
  bool _useStringPayload = false;
  String? _forceSosLang;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    final storage = context.read<StorageService>();
    _firstNameController.text = storage.getFirstName();
    _lastNameController.text = storage.getLastName();
    _addressController.text = storage.getLocation();
    _selectedCountry = storage.getCountry();
    if (_selectedCountry?.isEmpty ?? true) _selectedCountry = null;

    _isDevMode = storage.isDevMode();
    _useStringPayload = storage.useStringPayload();
    _forceSosLang = storage.getForceSosLang();

    _firstNameController.addListener(_markDirty);
    _lastNameController.addListener(_markDirty);
    _addressController.addListener(_markDirty);
  }

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  void _saveProfile() {
    final storage = context.read<StorageService>();

    storage.saveProfile(
      first: _firstNameController.text,
      last: _lastNameController.text,
      country: _selectedCountry ?? "",
      location: _addressController.text,
    );
    storage.setDevMode(_isDevMode);
    storage.setUseStringPayload(_useStringPayload);
    storage.setForceSosLang(_forceSosLang);

    setState(() => _isDirty = false);
  }

  @override
  Widget build(BuildContext context) {    final locale = context.watch<LocaleService>();
    final gps = context.watch<GpsService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(locale.t('profile').toUpperCase()),
        actions: [
          if (_isDirty)
            IconButton(
              icon: const Icon(Icons.check, color: Color(0xFF2E7D32), size: 28),
              onPressed: _saveProfile,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader(locale.t('profile')),
            _buildTextField(_firstNameController, locale.t('name')),
            _buildTextField(_lastNameController, locale.t('surname')),
            
            // Rule: Country Selection in Profile
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCountry,
                  hint: Text(locale.t('select_country'), style: const TextStyle(color: Colors.white54, fontSize: 14)),
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1A1A1A),
                  items: ['Türkiye', 'Other'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedCountry = newValue;
                      _isDirty = true;
                    });
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),
            
            // Rule: No more manual address text field. Prominent Auto-GPS button.
            ElevatedButton.icon(
              icon: const Icon(Icons.gps_fixed, size: 24),
              label: Text(locale.isEnglish ? "AUTO-GET MY LOCATION" : "KONUMUMU OTOMATİK AL"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                if (gps.hasFix) {
                  setState(() {
                    _addressController.text = "${gps.currentPosition!.latitude.toStringAsFixed(5)}, ${gps.currentPosition!.longitude.toStringAsFixed(5)}";
                    _isDirty = true;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(locale.t('loc_acquired'))),
                  );
                } else {
                  gps.refresh();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(locale.t('searching_gps'))),
                  );
                }
              },
            ),
            
            if (_addressController.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  "KAYITLI KOORDİNAT: ${_addressController.text}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFFFC107), fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.map_outlined),
              label: Text(locale.t('update_location').toUpperCase()),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2B2B2B),
                side: const BorderSide(color: Colors.white12),
              ),
              onPressed: () async {
                final LatLng? picked = await Navigator.push<LatLng>(
                  context,
                  MaterialPageRoute(builder: (context) => const LocationPickerScreen()),
                );
                if (picked != null) {
                  setState(() {
                    _addressController.text = "${picked.latitude.toStringAsFixed(5)}, ${picked.longitude.toStringAsFixed(5)}";
                    _isDirty = true;
                  });
                }
              },
            ),
            
            const SizedBox(height: 32),
            _buildSectionHeader(locale.isEnglish ? "DEVICE SETTINGS" : "CİHAZ AYARLARI"),
            ElevatedButton.icon(
              icon: const Icon(Icons.wifi),
              label: Text(locale.isEnglish ? "SETUP WI-FI (FOR OTA & AI)" : "WI-FI KURULUMU (OTA & AI İÇİN)"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2B2B2B),
                side: const BorderSide(color: Colors.white12),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () {
                _showWifiDialog(context, locale);
              },
            ),

            const SizedBox(height: 32),
            _buildSectionHeader(locale.t('battery_opt_title')),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2B2B2B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  Text(
                    locale.t('battery_opt_desc'),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => ForegroundService.requestIgnoreBatteryOptimizations(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade900,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 45),
                    ),
                    child: Text(locale.t('battery_opt_btn')),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
            _buildSectionHeader(locale.t('dev_mode')),            SwitchListTile(
              title: Text(locale.t('dev_mode'), style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(locale.t('dev_mode_desc'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
              value: _isDevMode,
              activeColor: Colors.amber,
              onChanged: (val) {
                setState(() {
                  _isDevMode = val;
                  _isDirty = true;
                });
              },
            ),

            if (_isDevMode) ...[
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text("SOS Payload: String (Debug)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text("Send as plain text for Serial Monitor debugging.", style: TextStyle(color: Colors.white54, fontSize: 12)),
                value: _useStringPayload,
                activeColor: Colors.amber,
                onChanged: (val) {
                  setState(() {
                    _useStringPayload = val;
                    _isDirty = true;
                  });
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                title: const Text("Force SOS Language", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                trailing: DropdownButton<String?>(
                  value: _forceSosLang,
                  dropdownColor: const Color(0xFF2B2B2B),
                  items: const [
                    DropdownMenuItem(value: null, child: Text("Auto (City Based)", style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: "TR", child: Text("Turkish", style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: "EN", child: Text("English", style: TextStyle(fontSize: 12))),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _forceSosLang = val;
                      _isDirty = true;
                    });
                  },
                ),
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  void _showWifiDialog(BuildContext context, LocaleService locale) async {
    final ssidController = TextEditingController();
    final passController = TextEditingController();
    final ble = context.read<BleService>();

    // Try to auto-fetch current Wi-Fi SSID
    try {
      final info = NetworkInfo();
      String? wifiName = await info.getWifiName(); // e.g. "MyNetwork"
      if (wifiName != null) {
        // network_info_plus sometimes returns SSID with quotes on Android like '"MyNetwork"'
        wifiName = wifiName.replaceAll('"', '');
        ssidController.text = wifiName;
      }
    } catch (e) {
      debugPrint("Failed to get wifi name: $e");
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2B2B2B),
        title: Text(locale.isEnglish ? "Wi-Fi Setup" : "Wi-Fi Kurulumu", style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ssidController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: locale.isEnglish ? "Network Name (SSID)" : "Ağ Adı (SSID)",
                labelStyle: const TextStyle(color: Colors.white54),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: locale.isEnglish ? "Password" : "Şifre",
                labelStyle: const TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(locale.t('cancel'), style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              final ssid = ssidController.text.trim();
              final pass = passController.text.trim();
              if (ssid.isNotEmpty) {
                ble.writeText("WIFI|$ssid|$pass");
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(locale.isEnglish ? "Wi-Fi credentials sent to device." : "Wi-Fi bilgileri cihaza gönderildi.")),
                );
              }
              Navigator.pop(context);
            },
            child: Text(locale.isEnglish ? "Send" : "Gönder"),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Color(0xFFFFC107), fontSize: 14),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextField(
        controller: controller,
        style: const TextStyle(fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54, fontWeight: FontWeight.normal),
          filled: true,
          fillColor: const Color(0xFF1A1A1A),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white10)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFFFC107))),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _firstNameController.removeListener(_markDirty);
    _lastNameController.removeListener(_markDirty);
    _addressController.removeListener(_markDirty);
    _firstNameController.dispose();
    _lastNameController.dispose();
    _addressController.dispose();
    super.dispose();
  }
}
