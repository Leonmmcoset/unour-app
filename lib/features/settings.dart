import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/controller.dart';
import '../core/live_table.dart';
import '../game/design.dart';
import '../game/motion.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferencesProvider);
    final live = ref.watch(liveTableProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              MotionEntrance(
                child: GamePanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.palette_outlined, size: 22),
                          SizedBox(width: 10),
                          Text(
                            '外观',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.system,
                              label: Text('系统'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              label: Text('浅色'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              label: Text('深色'),
                            ),
                          ],
                          selected: {prefs.theme},
                          onSelectionChanged: (v) => prefs.setTheme(v.first),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              MotionEntrance(
                delay: 80,
                child: GamePanel(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.volume_up_outlined),
                        title: const Text('游戏音效'),
                        value: prefs.sound,
                        onChanged: (v) => prefs.toggle('sound', v),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.vibration_rounded),
                        title: const Text('轻震动'),
                        value: prefs.haptics,
                        onChanged: (v) => prefs.toggle('haptics', v),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Divider(),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.animation_rounded),
                        title: const Text('减少动态效果'),
                        subtitle: const Text('也会遵循系统设置'),
                        value: prefs.reduceMotion,
                        onChanged: (v) => prefs.toggle('reduce_motion', v),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Divider(),
                      ),
                      SwitchListTile(
                        secondary: const Icon(
                          Icons.notifications_active_outlined,
                        ),
                        title: const Text('后台牌桌'),
                        subtitle: Text(live.description),
                        value: prefs.liveTable,
                        onChanged: live.supported || prefs.liveTable
                            ? live.setEnabled
                            : null,
                      ),
                      if (live.message.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          child: Text(live.message),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GamePanel(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.school_outlined),
                  title: const Text('新手引导'),
                  subtitle: const Text('重看出牌、选色和 UNO 的操作'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/learn'),
                ),
              ),
              const SizedBox(height: 32),
              const Center(child: ColorDots()),
              const SizedBox(height: 10),
              Text(
                'Unour · 1.0.0',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
