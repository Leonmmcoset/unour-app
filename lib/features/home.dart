import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/controller.dart';
import '../game/design.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider), user = app.account!;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Unour',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: '我的玩家卡',
            onPressed: () => context.push('/account'),
            icon: ProfileAvatar(
              name: user.username,
              url: user.avatarUrl,
              radius: 16,
            ),
          ),
          IconButton(
            tooltip: '偏好设置',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            children: [
              const PartyHero(),
              Text(
                '${user.username}，来一局？',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 24),
              _GameEntry(
                title: '人机开局',
                subtitle: '选择电脑人数和难度',
                icon: Icons.smart_toy_outlined,
                color: const Color(0xff397de0),
                onTap: () => context.push('/setup/solo'),
              ),
              const SizedBox(height: 12),
              _GameEntry(
                title: '和朋友玩',
                subtitle: '创建房间，邀请朋友',
                icon: Icons.celebration_outlined,
                color: const Color(0xffc75a4d),
                onTap: () => context.push('/setup/create'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push('/setup/join'),
                icon: const Icon(Icons.meeting_room_outlined),
                label: const Text('输入房间号 · 加入或观战'),
              ),
              ErrorStrip(app.error, onDismiss: app.clearError),
              if (app.room != null) ...[
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: () => context.push('/room'),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('回到当前牌桌'),
                ),
              ],
              if (app.recent.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('最近的牌桌', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                for (final session in app.recent)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.style_rounded),
                      title: Text(session.id),
                      subtitle: const Text('重新入座，恢复原来的身份'),
                      onTap: app.busy
                          ? null
                          : () async {
                              final ok = await app.enter(id: session.id);
                              if (ok && context.mounted) context.push('/room');
                            },
                      trailing: IconButton(
                        tooltip: '从本机记录移除',
                        onPressed: app.busy
                            ? null
                            : () => app.forget(session.id),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 24),
              const Text('小提示：只剩一张牌时，记得喊 UNO！', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameEntry extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _GameEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: BorderRadius.circular(26),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            Icon(icon, size: 34, color: Colors.white),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white),
          ],
        ),
      ),
    ),
  );
}
