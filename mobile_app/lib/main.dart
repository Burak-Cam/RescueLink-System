import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:battery_plus/battery_plus.dart';
import 'services/ble_service.dart';
import 'services/storage_service.dart';
import 'services/gps_service.dart';
import 'services/sos_status_service.dart';
import 'services/locale_service.dart';
import 'services/whistle_service.dart';
import 'services/sms_queue_service.dart';
import 'services/map_service.dart';
import 'services/foreground_service.dart';
import 'theme/app_theme.dart';
import 'screens/auto_connect_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';

// Rule: New Battery State Service for Critical Survival Mode
class BatteryStateService extends ChangeNotifier {
  final Battery _battery = Battery();
  bool _isCritical = false;
  int _batteryLevel = 100;

  bool get isCritical => _isCritical;
  int get batteryLevel => _batteryLevel;

  BatteryStateService() {
    _init();
  }

  Future<void> _init() async {
    _batteryLevel = await _battery.batteryLevel;
    _checkCritical();

    _battery.onBatteryStateChanged.listen((state) async {
      _batteryLevel = await _battery.batteryLevel;
      _checkCritical();
    });
  }

  void _checkCritical() {
    bool newCriticalState = _batteryLevel <= 15;
    if (_isCritical != newCriticalState) {
      _isCritical = newCriticalState;
      notifyListeners();
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Rule: Initialize Foreground Service
  ForegroundService.init();
  
  final prefs = await SharedPreferences.getInstance();
  final storageService = StorageService(prefs);
  final bleService = BleService();

  // Rule: Zero-Touch Auto-Connect Logic
  bool autoConnected = false;
  if (storageService.isProfileComplete()) {
    final lastMac = storageService.getSavedMac();
    if (lastMac != null && lastMac.isNotEmpty) {
      final device = await bleService.findDevice(lastMac);
      if (device != null) {
        autoConnected = await bleService.connect(device);
      }
    }
  }

  runApp(
    MultiProvider(
      providers: [
        Provider<StorageService>.value(value: storageService),
        ChangeNotifierProvider<BleService>.value(value: bleService),
        ChangeNotifierProvider(create: (_) => GpsService()),
        ChangeNotifierProvider(create: (_) => SosStatusService(storageService)),
        ChangeNotifierProvider(create: (_) => LocaleService(prefs)),
        ChangeNotifierProvider(create: (_) => WhistleService()),
        ChangeNotifierProvider(create: (_) => SmsQueueService(storageService)),
        ChangeNotifierProvider(create: (_) => MapService(storageService)),
        ChangeNotifierProvider(create: (_) => BatteryStateService()),
      ],
      child: RescueLinkApp(
        isProfileComplete: storageService.isProfileComplete(),
        autoConnected: autoConnected,
      ),
    ),
  );
}

class RescueLinkApp extends StatelessWidget {
  final bool isProfileComplete;
  final bool autoConnected;
  const RescueLinkApp({
    super.key, 
    required this.isProfileComplete,
    required this.autoConnected,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer2<LocaleService, BatteryStateService>(
      builder: (context, localeService, batteryState, child) {
        
        // Pass critical state down to GPS service to kill periodic wakes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.read<GpsService>().setCriticalBatteryMode(batteryState.isCritical);
        });

        Widget initialScreen;
        if (!isProfileComplete) {
          initialScreen = const OnboardingScreen();
        } else if (autoConnected) {
          initialScreen = const HomeScreen();
        } else {
          initialScreen = const AutoConnectScreen();
        }

        // Rule: Pure AMOLED black for Critical Mode to turn off pixels
        ThemeData currentTheme = AppTheme.urgentTheme;
        if (batteryState.isCritical) {
           currentTheme = currentTheme.copyWith(
             scaffoldBackgroundColor: Colors.black,
             appBarTheme: currentTheme.appBarTheme.copyWith(backgroundColor: Colors.black),
             cardTheme: currentTheme.cardTheme.copyWith(color: const Color(0xFF0A0A0A)),
           );
        }

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'RescueLink',
          theme: currentTheme,
          home: initialScreen,
        );
      },
    );
  }
}
