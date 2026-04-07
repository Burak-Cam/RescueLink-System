import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'storage_service.dart';

class SmsQueueService extends ChangeNotifier {
  final StorageService _storage;
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  
  String? _queuedMessage;
  bool _isSending = false;

  String? get queuedMessage => _queuedMessage;

  SmsQueueService(this._storage) {
    _subscription = _connectivity.onConnectivityChanged.listen(_handleConnectivityChange);
  }

  void queueSos(String message) {
    _queuedMessage = message;
    notifyListeners();
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final hasConnection = results.any((r) => r != ConnectivityResult.none);
    if (hasConnection && _queuedMessage != null && !_isSending) {
      _sendQueuedSms();
    }
  }

  Future<void> _sendQueuedSms() async {
    _isSending = true;
    final contacts = _storage.getEmergencyContacts();
    if (contacts.isEmpty || _queuedMessage == null) {
      _isSending = false;
      return;
    }

    final message = _queuedMessage!;
    
    for (var contact in contacts) {
      final phone = contact['phone'];
      if (phone != null && phone.isNotEmpty) {
        final uri = Uri.parse("sms:$phone?body=${Uri.encodeComponent(message)}");
        try {
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          }
        } catch (e) {
          if (kDebugMode) print("SMS Send Error: $e");
        }
      }
    }

    _queuedMessage = null;
    _isSending = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
