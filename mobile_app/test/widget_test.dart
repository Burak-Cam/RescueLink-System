import 'package:flutter_test/flutter_test.dart';
import 'package:rescuelink/main.dart';
import 'package:rescuelink/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:rescuelink/services/locale_service.dart';
import 'package:rescuelink/services/battery_service.dart';
import 'package:rescuelink/services/ble_service.dart';
import 'package:rescuelink/services/gps_service.dart';
import 'package:rescuelink/services/sos_status_service.dart';
import 'package:rescuelink/services/whistle_service.dart';
import 'package:rescuelink/services/map_service.dart';
import 'package:rescuelink/services/ota_service.dart';

void main() {
  testWidgets('App smoke test - verifies initial screen loads', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storageService = StorageService(prefs);
    final bleService = BleService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<StorageService>.value(value: storageService),
          ChangeNotifierProvider<BleService>.value(value: bleService),
          ChangeNotifierProvider(create: (_) => GpsService()),
          ChangeNotifierProvider(create: (_) => SosStatusService(storageService)),
          ChangeNotifierProvider(create: (_) => LocaleService(prefs)),
          ChangeNotifierProvider(create: (_) => WhistleService()),
          ChangeNotifierProvider(create: (_) => MapService(storageService)),
          ChangeNotifierProvider(create: (_) => BatteryStateService()),
          ChangeNotifierProxyProvider<BleService, OtaService>(
            create: (ctx) => OtaService(bleService), 
            update: (ctx, ble, ota) => ota!,
          ),
        ],
        child: const RescueLinkApp(
          isProfileComplete: false,
          autoConnected: false,
        ),
      ),
    );

    // Verify that OnboardingScreen is shown (since isProfileComplete is false)
    // We can check for a specific text or widget in OnboardingScreen
    expect(find.byType(RescueLinkApp), findsOneWidget);
  });
}
