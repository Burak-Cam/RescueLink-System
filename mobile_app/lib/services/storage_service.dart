import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _savedMacKey = 'saved_mac';
  static const String _firstNameKey = 'firstName';
  static const String _lastNameKey = 'lastName';
  static const String _countryKey = 'country';
  static const String _locationKey = 'savedLocation';
  static const String _sosHistoryKey = 'sos_history';
  static const String _lastSosTimestampKey = 'last_sos_timestamp';
  static const String _emergencyContactsKey = 'emergency_contacts';
  static const String _devModeKey = 'dev_mode';
  static const String _profileCompleteKey = 'profile_complete';
  static const String _useStringPayloadKey = 'use_string_payload';
  static const String _forceSosLangKey = 'force_sos_lang';
  static const String _lastHealthKey = 'last_health';
  static const String _lastCountKey = 'last_count';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  // Anti-Spam Persistence
  String getLastHealth() => _prefs.getString(_lastHealthKey) ?? "";
  int getLastCount() => _prefs.getInt(_lastCountKey) ?? 0;
  
  Future<void> saveLastSosPayload(String health, int count) async {
    await _prefs.setString(_lastHealthKey, health);
    await _prefs.setInt(_lastCountKey, count);
  }

  // App State
  bool isProfileComplete() {
    final complete = _prefs.getBool(_profileCompleteKey) ?? false;
    final hasCountry = getCountry().isNotEmpty;
    return complete && hasCountry;
  }
  Future<void> setProfileComplete(bool val) async => await _prefs.setBool(_profileCompleteKey, val);

  // MAC Persistence
  String? getSavedMac() => _prefs.getString(_savedMacKey);
  Future<void> saveMac(String mac) async => await _prefs.setString(_savedMacKey, mac);
  Future<void> clearMac() async => await _prefs.remove(_savedMacKey);

  // SOS Cooldown Persistence
  DateTime? getLastSosTimestamp() {
    final ts = _prefs.getString(_lastSosTimestampKey);
    return ts != null ? DateTime.parse(ts) : null;
  }
  Future<void> saveLastSosTimestamp(DateTime ts) async => await _prefs.setString(_lastSosTimestampKey, ts.toIso8601String());
  Future<void> clearLastSosTimestamp() async => await _prefs.remove(_lastSosTimestampKey);

  // SOS History
  List<String> getSosHistory() => _prefs.getStringList(_sosHistoryKey) ?? [];
  Future<void> saveSosToHistory(String payload) async {
    final history = getSosHistory();
    history.insert(0, "${DateTime.now().toIso8601String()}|$payload");
    if (history.length > 50) history.removeLast();
    await _prefs.setStringList(_sosHistoryKey, history);
  }

  // User Profile Persistence
  String getFirstName() => _prefs.getString(_firstNameKey) ?? "";
  String getLastName() => _prefs.getString(_lastNameKey) ?? "";
  String getCountry() => _prefs.getString(_countryKey) ?? "";
  String getLocation() => _prefs.getString(_locationKey) ?? "";

  Future<void> saveProfile({
    required String first, 
    required String last, 
    required String country,
    required String location,
  }) async {
    await _prefs.setString(_firstNameKey, first);
    await _prefs.setString(_lastNameKey, last);
    await _prefs.setString(_countryKey, country);
    await _prefs.setString(_locationKey, location);
  }

  // Emergency Contacts
  List<Map<String, String>> getEmergencyContacts() {
    final List<String>? encoded = _prefs.getStringList(_emergencyContactsKey);
    if (encoded == null) return [];
    return encoded.map((item) {
      final parts = item.split('|');
      return {'name': parts[0], 'phone': parts[1]};
    }).toList();
  }

  Future<void> saveEmergencyContacts(List<Map<String, String>> contacts) async {
    final List<String> encoded = contacts.map((c) => "${c['name']}|${c['phone']}").toList();
    await _prefs.setStringList(_emergencyContactsKey, encoded);
  }

  // Developer Mode
  bool isDevMode() => _prefs.getBool(_devModeKey) ?? false;
  Future<void> setDevMode(bool val) async => await _prefs.setBool(_devModeKey, val);

  // Payload Format (Dev Mode Only)
  bool useStringPayload() => _prefs.getBool(_useStringPayloadKey) ?? false;
  Future<void> setUseStringPayload(bool val) async => await _prefs.setBool(_useStringPayloadKey, val);

  static const String _downloadedCityKey = 'downloaded_city';

  // Map Persistence
  String? getDownloadedCity() => _prefs.getString(_downloadedCityKey);
  Future<void> saveDownloadedCity(String city) async => await _prefs.setString(_downloadedCityKey, city);
  Future<void> clearDownloadedCity() async => await _prefs.remove(_downloadedCityKey);

  // Force SOS Language (Dev Mode Only): null (auto), 'TR', 'EN'
  String? getForceSosLang() => _prefs.getString(_forceSosLangKey);
  Future<void> setForceSosLang(String? val) async {
    if (val == null) {
      await _prefs.remove(_forceSosLangKey);
    } else {
      await _prefs.setString(_forceSosLangKey, val);
    }
  }
}
