import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GamePreferences extends ChangeNotifier {
  final SharedPreferences store;
  GamePreferences(this.store);
  bool get sound => store.getBool('sound') ?? true;
  bool get haptics => store.getBool('haptics') ?? true;
  bool get reduceMotion => store.getBool('reduce_motion') ?? false;
  bool get liveTable => store.getBool('live_table') ?? false;
  bool get tutorialDismissed => store.getBool('tutorial_seen_v1') ?? false;
  ThemeMode get theme => ThemeMode.values[store.getInt('theme') ?? 0];
  Future<void> toggle(String key, bool value) async {
    await store.setBool(key, value);
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode mode) async {
    await store.setInt('theme', mode.index);
    notifyListeners();
  }

  Future<void> finishTutorial() async {
    if (!await store.setBool('tutorial_seen_v1', true)) {
      throw StateError('Could not save tutorial preference');
    }
    notifyListeners();
  }
}
