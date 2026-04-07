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
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.alarm,
        audioFocus: AndroidAudioFocus.gainTransient,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playAndRecord,
        options: const {
          AVAudioSessionOptions.defaultToSpeaker,
          AVAudioSessionOptions.duckOthers,
        },
      ),
    ));
  }

  Future<void> toggleWhistle({bool isCriticalBattery = false}) async {
    if (_isPlaying) {
      _stopWhistle();
    } else {
      await _startWhistleBurst(isCriticalBattery);
    }
  }

  Future<void> _startWhistleBurst(bool isCriticalBattery) async {
    _isPlaying = true;
    notifyListeners();

    // Rule: Unstoppable Siren (CPU Wake-Lock)
    WakelockPlus.enable();

    // Rule: Save original volume
    try {
      _originalVolume = await VolumeController().getVolume();
      // Rule: Limit max volume to 80% if in Critical Battery Mode to save speaker power
      double targetVolume = isCriticalBattery ? 0.8 : 1.0;
      VolumeController().setVolume(targetVolume);
      await _player.setVolume(targetVolume);
    } catch (e) {
      if (kDebugMode) print("Volume Control Error: $e");
    }
    
    try {
      // Rule: Play local whistle.mp3 ONLY, loops infinitely
      await _player.play(AssetSource('whistle.mp3'), mode: PlayerMode.lowLatency);
    } catch (e) {
      if (kDebugMode) print("Asset Playback Failed: $e");
    }
  }

  Future<void> _stopWhistle() async {
    try {
      await _player.stop();
      
      // Rule: Restore original volume
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
