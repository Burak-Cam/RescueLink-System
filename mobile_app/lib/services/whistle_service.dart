import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class WhistleService extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  double _originalVolume = 0.5;

  bool get isPlaying => _isPlaying;

  WhistleService() {
    _player.setReleaseMode(ReleaseMode.loop);
    
    _player.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: true,
        contentType: AndroidContentType.music, // Media kanalına çekildi
        usageType: AndroidUsageType.media,     // Daha kolay kontrol için
        audioFocus: AndroidAudioFocus.gainTransient,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback, 
        options: const {
          AVAudioSessionOptions.duckOthers,
        },
      ),
    ));
  }

  Future<void> toggleWhistle({bool isCriticalBattery = false}) async {
    if (_isPlaying) {
      stopWhistle();
    } else {
      await _startWhistleBurst();
    }
  }

  Future<void> _startWhistleBurst() async {
    _isPlaying = true;
    notifyListeners();

    WakelockPlus.enable();

    try {
      // Rule: System-wide volume boost
      _originalVolume = await VolumeController().getVolume();
      VolumeController().setVolume(1.0); // %100 Medya Sesi
      await _player.setVolume(1.0);      // %100 Player Sesi
    } catch (e) {
      if (kDebugMode) print("Volume Control Error: $e");
    }
    
    try {
      await _player.play(AssetSource('whistle.mp3'), mode: PlayerMode.lowLatency);
    } catch (e) {
      if (kDebugMode) print("Asset Playback Failed: $e");
    }
  }

  Future<void> stopWhistle() async {
    try {
      await _player.stop();
      VolumeController().setVolume(_originalVolume);
    } catch (e) {
      // Ignore stop errors
    }
    
    WakelockPlus.disable();
    _isPlaying = false;
    notifyListeners();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _player.dispose();
    super.dispose();
  }
}
