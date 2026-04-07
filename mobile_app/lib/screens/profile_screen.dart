import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import '../services/storage_service.dart';
import '../services/locale_service.dart';
import '../services/gps_service.dart';
import '../services/foreground_service.dart';
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
  
  List<Map<String, String>> _emergencyContacts = [];
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
    
    _emergencyContacts = List.from(storage.getEmergencyContacts());
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
    storage.saveEmergencyContacts(_emergencyContacts);
    storage.setDevMode(_isDevMode);
    storage.setUseStringPayload(_useStringPayload);
    storage.setForceSosLang(_forceSosLang);
    
    setState(() => _isDirty = false);
  }

  void _addContact() {
    setState(() {
      _emergencyContacts.add({'name': '', 'phone': ''});
      _isDirty = true;
    });
  }

  void _removeContact(int index) {
    setState(() {
      _emergencyContacts.removeAt(index);
      _isDirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleService>();
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
                    const SnackBar(content: Text("Konum başarıyla alındı.")),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSectionHeader(locale.t('emergency_contacts')),
                IconButton(
                  icon: const Icon(Icons.person_add_alt_1, color: Color(0xFF2E7D32)),
                  onPressed: _addContact,
                ),
              ],
            ),
            
            if (_emergencyContacts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  locale.isEnglish ? "No emergency contacts added." : "Acil durum kişisi eklenmedi.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white24, fontStyle: FontStyle.italic),
                ),
              ),

            ...List.generate(_emergencyContacts.length, (index) {
              return _buildContactCard(index, locale);
            }),
            
            const SizedBox(height: 32),
            _buildSectionHeader(locale.t('dev_mode')),
            SwitchListTile(
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

  Widget _buildContactCard(int index, LocaleService locale) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2B2B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline, color: Colors.white54, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: locale.t('contact_name'),
                    hintStyle: const TextStyle(color: Colors.white24),
                    border: InputBorder.none,
                  ),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  onChanged: (val) {
                    _emergencyContacts[index]['name'] = val;
                    _markDirty();
                  },
                  controller: TextEditingController(text: _emergencyContacts[index]['name'])..selection = TextSelection.collapsed(offset: _emergencyContacts[index]['name']?.length ?? 0),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFD32F2F), size: 20),
                onPressed: () => _removeContact(index),
              ),
            ],
          ),
          const Divider(color: Colors.white10),
          Row(
            children: [
              const Icon(Icons.phone_outlined, color: Colors.white54, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: locale.t('contact_phone'),
                    hintStyle: const TextStyle(color: Colors.white24),
                    border: InputBorder.none,
                  ),
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
                  onChanged: (val) {
                    _emergencyContacts[index]['phone'] = val;
                    _markDirty();
                  },
                  controller: TextEditingController(text: _emergencyContacts[index]['phone'])..selection = TextSelection.collapsed(offset: _emergencyContacts[index]['phone']?.length ?? 0),
                ),
              ),
            ],
          ),
        ],
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
