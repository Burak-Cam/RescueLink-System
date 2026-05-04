import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/foundation.dart';
import 'package:app_settings/app_settings.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(BleTaskHandler());
}

class BleTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    if (kDebugMode) print('BLE Foreground Service Started');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // This keeps the service alive and can be used for periodic checks if needed
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    if (kDebugMode) print('BLE Foreground Service Destroyed');
  }
}

class ForegroundService {
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ble_service_channel',
        channelName: 'BLE Mesh Service',
        channelDescription: 'Keeps the BLE mesh connection alive in the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
        eventAction: ForegroundTaskEventAction.repeat(5000),
      ),
    );
  }

  static Future<bool> start() async {
    if (await FlutterForegroundTask.isRunningService) {
      return true;
    }

    final result = await FlutterForegroundTask.startService(
      notificationTitle: 'RescueLink Mesh Active',
      notificationText: 'Listening for HQ messages...',
      callback: startCallback,
    );
    
    return result.toString().contains('success');
  }

  static Future<bool> stop() async {
    final result = await FlutterForegroundTask.stopService();
    return result.toString().contains('success');
  }

  static Future<void> showSystemNotification(String title, String text) async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    }
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await AppSettings.openAppSettings(type: AppSettingsType.batteryOptimization);
  }
}
