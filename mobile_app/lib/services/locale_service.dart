import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleService extends ChangeNotifier {
  static const String _localeKey = 'app_locale';
  
  bool _isEnglish = false;
  final SharedPreferences _prefs;

  LocaleService(this._prefs) {
    _isEnglish = _prefs.getBool(_localeKey) ?? false;
  }

  bool get isEnglish => _isEnglish;

  void toggleLocale() {
    _isEnglish = !_isEnglish;
    _prefs.setBool(_localeKey, _isEnglish);
    notifyListeners();
  }

  String t(String key, {Map<String, String>? args}) {
    String text = _lang[_isEnglish ? 'EN' : 'TR']![key] ?? key;
    if (args != null) {
      args.forEach((k, v) {
        text = text.replaceAll('{$k}', v);
      });
    }
    return text;
  }

  static const Map<String, Map<String, String>> _lang = {
    'TR': {
      'app_name': 'RescueLink',
      'welcome': 'RescueLink\'e Hoş Geldiniz',
      'registration': 'KAYIT',
      'name': 'Adınız',
      'surname': 'Soyadınız',
      'home_address': 'Açık Adresiniz',
      'location_q': 'Şu an kayıtlı ev adresinizde misiniz?',
      'yes_gps': 'Evet (Konumumu Kullan)',
      'no_manual': 'Hayır (Manuel Gireceğim)',
      'manual_address': 'Açık Adresinizi Girin',
      'save_continue': 'KAYDET VE DEVAM ET',
      'connecting': 'KURTARMA AĞINA BAĞLANILIYOR...',
      'sos_button': 'YARDIM ÇAĞRISI GÖNDER',
      'health_status': 'SAĞLIK DURUMUNUZ:',
      'healthy': 'SAĞLIKLI',
      'light_injury': 'HAFİF YARALI',
      'heavy_injury': 'AĞIR YARALI',
      'how_many': 'KAÇ KİŞİSİNİZ?',
      'forget_device': 'Cihazı Unut',
      'hq_channel': 'KARARGAH İLETİŞİM KANALI',
      'no_message': 'Henüz bir mesaj yok.',
      'scan_devices': 'ÇEVREDEKİ CİHAZLAR TARANIYOR...',
      'select_device': 'LÜTFEN BİR CİHAZ SEÇİN',
      'connect': 'BAĞLAN',
      'rescan': 'TEKRAR TARA',
      'profile': 'PROFİL',
      'emergency_contacts': 'ACİL DURUM KİŞİLERİ',
      'add_contact': 'Kişi Ekle',
      'contact_name': 'Kişi Adı',
      'contact_phone': 'Telefon Numarası',
      'save': 'KAYDET',
      'whistle': 'DÜDÜK',
      'sms_queued': 'SMS Kuyruğa Alındı',
      'sms_sent': 'SMS Gönderildi',
      'update_location': 'KONUMU GÜNCELLE',
      'locked': 'KİLİTLİ',
      'cooldown_msg': 'AĞ BEKLEME SÜRESİ AKTİF',
      'map_prompt_title': 'Harita İndir',
      'map_prompt_desc': 'Şu an {city} bölgesindesiniz. Çevrimdışı kullanım için {city} haritasını indirmek ister misiniz?',
      'download': 'İndir',
      'ignore': 'Yoksay',
      'hq_broadcast_received': 'KARARGAH YAYINI ALINDI',
      'err_ble_off': 'Bluetooth kapalı. Lütfen açın.',
      'err_gps_off': 'Konum servisleri kapalı.',
      'err_gps_denied': 'Konum izni reddedildi.',
      'err_gps_forever': 'Konum izni kalıcı olarak reddedildi. Ayarlardan açın.',
      'err_connection_lost': 'Bağlantı kesildi. Tekrar bağlanılıyor...',
      'open_settings': 'Ayarları Aç',
      'manual_fix': 'MANUEL KONUM',
      'establishing_tunnel': 'TÜNEL KURULUYOR...',
      'searching_gateway': 'GATEWAY ARANIYOR...',
      'sos_handed': 'SOS GATEWAY\'E İLETİLDİ',
      'send_failure': 'GÖNDERİM HATASI',
      'no_gps_fix_title': 'GPS BAĞLANTISI YOK',
      'no_gps_fix_desc': 'Hassas konumunuz henüz belirlenmedi. Bilinen son konum ile SOS gönderilsin mi?',
      'cancel': 'İPTAL',
      'send_anyway': 'YİNE DE GÖNDER',
      'dev_mode': 'Geliştirici Modu',
      'dev_mode_desc': 'Bekleme sürelerini devre dışı bırakır.',
      'battery_opt_title': 'Pil Optimizasyonu',
      'battery_opt_desc': 'RescueLink\'in arka planda çalışabilmesi için pil optimizasyonunu devre dışı bırakmanız önerilir. Bu, BLE bağlantısının kesilmesini önler.',
      'battery_opt_btn': 'DEVRE DIŞI BIRAK',
      'history': 'GEÇMİŞ',
      'step_sending': 'TELEFON',
      'step_node': 'CİHAZ',
      'step_hq': 'MERKEZ',
      'country': 'Ülke',
      'select_country': 'Lütfen bir ülke seçin',
      'anomaly_title': 'Sarsıntı Algılandı',
      'anomaly_desc': 'Bir sarsıntı oldu, bu bir deprem miydi?',
      'power_lost_msg': '⚠️ Donanım şebeke gücünü kaybetti, batarya moduna geçildi.',
      'tapping_msg': '🎯 Ritmik vuruşunuz algılandı! AFAD ağına iletiliyor...',
      'loc_acquired': 'Konum başarıyla alındı.',
      'yes': 'Evet',
      'no': 'Hayır'
    },
    'EN': {
      'app_name': 'RescueLink',
      'welcome': 'Welcome to RescueLink',
      'registration': 'REGISTRATION',
      'name': 'First Name',
      'surname': 'Last Name',
      'home_address': 'Full Address',
      'location_q': 'Are you currently at your home address?',
      'yes_gps': 'Yes (Use My Location)',
      'no_manual': 'No (I will enter manually)',
      'manual_address': 'Enter Your Full Address',
      'save_continue': 'SAVE & CONTINUE',
      'connecting': 'CONNECTING TO RESCUE NETWORK...',
      'sos_button': 'SEND SOS ALERT',
      'health_status': 'HEALTH STATUS:',
      'healthy': 'HEALTHY',
      'light_injury': 'LIGHTLY INJURED',
      'heavy_injury': 'SEVERELY INJURED',
      'how_many': 'HOW MANY PEOPLE ARE YOU?',
      'forget_device': 'Forget Device',
      'hq_channel': 'HQ COMMUNICATION CHANNEL',
      'no_message': 'No messages yet.',
      'scan_devices': 'SCANNING FOR DEVICES...',
      'select_device': 'PLEASE SELECT A DEVICE',
      'connect': 'CONNECT',
      'rescan': 'RESCAN',
      'profile': 'PROFILE',
      'emergency_contacts': 'EMERGENCY CONTACTS',
      'add_contact': 'Add Contact',
      'contact_name': 'Contact Name',
      'contact_phone': 'Phone Number',
      'save': 'SAVE',
      'whistle': 'WHISTLE',
      'sms_queued': 'SMS Queued',
      'sms_sent': 'SMS Sent',
      'update_location': 'UPDATE LOCATION',
      'locked': 'LOCKED',
      'cooldown_msg': 'NETWORK COOLDOWN ACTIVE',
      'map_prompt_title': 'Download Map',
      'map_prompt_desc': 'You are currently in {city}. Would you like to download the offline map for {city}?',
      'download': 'Download',
      'ignore': 'Ignore',
      'hq_broadcast_received': 'HQ BROADCAST RECEIVED',
      'err_ble_off': 'Bluetooth is OFF. Please enable it.',
      'err_gps_off': 'Location services are disabled.',
      'err_gps_denied': 'Location permission denied.',
      'err_gps_forever': 'Location permission permanently denied. Open settings.',
      'err_connection_lost': 'Connection lost. Reconnecting...',
      'open_settings': 'Open Settings',
      'manual_fix': 'MANUAL FIX',
      'establishing_tunnel': 'ESTABLISHING TUNNEL...',
      'searching_gateway': 'SEARCHING FOR DEVICE...',
      'searching_gps': 'SEARCHING FOR GPS...',
      'sos_handed': 'SOS HANDED TO GATEWAY',
      'send_failure': 'SEND FAILURE',
      'no_gps_fix_title': 'NO GPS FIX',
      'no_gps_fix_desc': 'Your precise location is not acquired. Send SOS with last known location?',
      'cancel': 'CANCEL',
      'send_anyway': 'SEND ANYWAY',
      'dev_mode': 'Developer Mode',
      'dev_mode_desc': 'Disables SOS cooldowns for testing.',
      'battery_opt_title': 'Battery Optimization',
      'battery_opt_desc': 'To keep the mesh connection active in the background, please disable battery optimization for RescueLink.',
      'battery_opt_btn': 'DISABLE OPTIMIZATION',
      'history': 'HISTORY',
      'step_sending': 'PHONE',
      'step_node': 'DEVICE',
      'step_hq': 'HQ',
      'country': 'Country',
      'select_country': 'Please select a country',
      'anomaly_title': 'Vibration Detected',
      'anomaly_desc': 'A vibration occurred, was this an earthquake?',
      'power_lost_msg': '⚠️ Hardware lost grid power, switched to battery mode.',
      'tapping_msg': '🎯 Rhythmic tapping detected! Forwarding to AFAD network...',
      'loc_acquired': 'Location acquired successfully.',
      'yes': 'Yes',
      'no': 'No'
    }
  };
}
