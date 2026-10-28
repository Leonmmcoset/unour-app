import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/controller.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferencesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('舒服地玩')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ListTile(title: Text('外观'), subtitle: Text('四色纸牌始终保持清晰鲜明')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
              ],
              selected: {prefs.theme},
              onSelectionChanged: (v) => prefs.setTheme(v.first),
            ),
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            title: const Text('游戏音效'),
            subtitle: const Text('纸牌、UNO 和胜利的声音'),
            value: prefs.sound,
            onChanged: (v) => prefs.toggle('sound', v),
          ),
          SwitchListTile(
            title: const Text('轻震动'),
            subtitle: const Text('轮到你和关键操作时的小提醒'),
            value: prefs.haptics,
            onChanged: (v) => prefs.toggle('haptics', v),
          ),
          SwitchListTile(
            title: const Text('减少动态效果'),
            subtitle: const Text('系统已开启时也会自动遵循'),
            value: prefs.reduceMotion,
            onChanged: (v) => prefs.toggle('reduce_motion', v),
          ),
          const SizedBox(height: 24),
          const ListTile(
            leading: Icon(Icons.favorite_outline),
            title: Text('Unour · 1.0.0'),
            subtitle: Text('好朋友，好手气。'),
          ),
        ],
      ),
    );
  }
}
