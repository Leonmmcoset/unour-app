import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'preferences.dart';

class GameFeedback {
  final GamePreferences preferences;
  AudioPlayer? _audio;
  GameFeedback(this.preferences);
  Future<void> play(String sound, {bool vibrate = true}) async {
    if (preferences.haptics && vibrate) await HapticFeedback.lightImpact();
    if (preferences.sound) {
      try {
        await (_audio ??= AudioPlayer()).play(
          AssetSource('audio/$sound.wav'),
          volume: .45,
        );
      } catch (_) {
        /* Audio is optional. */
      }
    }
  }

  void dispose() {
    _audio?.dispose();
  }
}
