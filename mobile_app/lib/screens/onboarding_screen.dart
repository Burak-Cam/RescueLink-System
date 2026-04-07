import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/storage_service.dart';
import '../services/locale_service.dart';
import '../services/gps_service.dart';
import 'auto_connect_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  _OnboardingScreenState createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  String? _selectedCountry;

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleService>();
    final storage = context.read<StorageService>();
    final gps = context.watch<GpsService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(locale.t('registration').toUpperCase()),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            Icon(Icons.person_add_outlined, size: 80, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 24),
            Text(
              locale.t('welcome'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 32),
            _buildTextField(_firstNameController, locale.t('name')),
            _buildTextField(_lastNameController, locale.t('surname')),
            
            // Rule: Mandatory Country Selection
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
                    });
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),
            
            // Rule: No more manual address text field. Prominent Auto-GPS button.
            ElevatedButton.icon(
              icon: const Icon(Icons.gps_fixed, size: 28),
              label: Text(locale.isEnglish ? "AUTO-GET MY LOCATION" : "KONUMUMU OTOMATİK AL"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                if (gps.hasFix) {
                  setState(() {
                    _addressController.text = "${gps.currentPosition!.latitude.toStringAsFixed(5)}, ${gps.currentPosition!.longitude.toStringAsFixed(5)}";
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
                padding: const EdgeInsets.only(top: 12.0),
                child: Text(
                  "KAYITLI KOORDİNAT: ${_addressController.text}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFFFC107), fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace'),
                ),
              ),

            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: () async {
                if (_firstNameController.text.isEmpty || _lastNameController.text.isEmpty || _selectedCountry == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(locale.t('select_country'))),
                  );
                  return;
                }
                
                if (_addressController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Lütfen konumunuzu otomatik alın.")),
                  );
                  return;
                }

                await storage.saveProfile(
                  first: _firstNameController.text,
                  last: _lastNameController.text,
                  country: _selectedCountry!,
                  location: _addressController.text,
                );
                await storage.setProfileComplete(true);
                
                if (mounted) {
                  Navigator.pushReplacement(
                    context, 
                    MaterialPageRoute(builder: (context) => const AutoConnectScreen())
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20),
              ),
              child: Text(locale.t('save_continue').toUpperCase()),
            ),
          ],
        ),
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
          labelStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: const Color(0xFF1A1A1A),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white10)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFFFC107))),
        ),
      ),
    );
  }
}
