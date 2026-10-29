import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/controller.dart';
import '../game/design.dart';
import '../game/motion.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider), user = app.account!;
    final prefs = ref.watch(preferencesProvider);
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                'Unour',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
              ),
            ),
            SizedBox(width: 12),
            ColorDots(),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '我的玩家卡',
            onPressed: () => context.push('/account'),
            icon: ProfileAvatar(
              name: user.username,
              url: user.avatarUrl,
              radius: 17,
            ),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: MotionEntrance(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('来一局？', style: theme.textTheme.headlineMedium),
                          ],
                        ),
                      ),
                    ),
                    const Expanded(child: PartyHero(compact: true)),
                  ],
                ),
                if (app.room != null) ...[
                  MotionEntrance(
                    child: Card(
                      color: colors.secondaryContainer,
                      child: ListTile(
                        leading: const Icon(Icons.play_circle_outline_rounded),
                        title: const Text('回到当前牌桌'),
                        subtitle: Text(app.room!.id),
                        trailing: const Icon(Icons.arrow_forward_rounded),
                        onTap: () => context.push('/room'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (!prefs.tutorialDismissed &&
                    app.room == null &&
                    app.recent.isEmpty &&
                    app.history.records.isEmpty) ...[
                  const SizedBox(height: 14),
                  GamePanel(
                    color: colors.tertiaryContainer,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('第一次玩？', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 6),
                        const Text('跟着牌面试试出牌、摸牌和喊 UNO。'),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () => context.push('/learn'),
                              icon: const Icon(Icons.school_outlined),
                              label: const Text('看看怎么玩'),
                            ),
                            TextButton(
                              onPressed: () async {
                                try {
                                  await prefs.finishTutorial();
                                } on Object {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('暂未保存，请稍后再试'),
                                      ),
                                    );
                                  }
                                }
                              },
                              child: const Text('我会玩了'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                MotionEntrance(
                  delay: 70,
                  child: PressScale(
                    child: Material(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(28),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(28),
                        onTap: () => context.push('/setup/create'),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colors.onPrimary.withValues(
                                    alpha: .14,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Icon(
                                  Icons.celebration_outlined,
                                  size: 30,
                                  color: colors.onPrimary,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '和朋友玩',
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(color: colors.onPrimary),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '创建牌桌',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: colors.onPrimary.withValues(
                                              alpha: .8,
                                            ),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_rounded,
                                color: colors.onPrimary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: MotionEntrance(
                        delay: 130,
                        child: _ModeTile(
                          title: '人机对战',
                          subtitle: '选择人数和难度',
                          icon: Icons.smart_toy_outlined,
                          accent: cardColor('red'),
                          onTap: () => context.push('/setup/solo'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: MotionEntrance(
                        delay: 190,
                        child: _ModeTile(
                          title: '加入牌桌',
                          subtitle: '输入房间号',
                          icon: Icons.meeting_room_outlined,
                          accent: cardColor('blue'),
                          onTap: () => context.push('/setup/join'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                GamePanel(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(Icons.history_rounded, color: colors.primary),
                    title: const Text('本机战绩'),
                    subtitle: Text(
                      app.history.completed == 0
                          ? '查看这台设备上的牌局记录'
                          : '${app.history.completed} 局已结算 · ${app.history.wins} 次获胜',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/history'),
                  ),
                ),
                ErrorStrip(app.error, onDismiss: app.clearError),
                if (app.recent.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Text('最近的牌桌', style: theme.textTheme.titleMedium),
                      const Spacer(),
                      Text(
                        '${app.recent.length}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GamePanel(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        for (final session in app.recent)
                          ListTile(
                            leading: Icon(
                              Icons.style_outlined,
                              color: colors.primary,
                            ),
                            title: Text(
                              session.id,
                              style: theme.textTheme.titleSmall,
                            ),
                            subtitle: const Text('重新加入'),
                            onTap: app.busy
                                ? null
                                : () async {
                                    final ok = await app.enter(id: session.id);
                                    if (ok && context.mounted) {
                                      context.push('/room');
                                    }
                                  },
                            trailing: IconButton(
                              tooltip: '从本机记录移除',
                              onPressed: app.busy
                                  ? null
                                  : () => app.forget(session.id),
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.campaign_outlined,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '剩一张牌时，记得喊 UNO',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  const _ModeTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PressScale(
      child: Material(
        color: Color.alphaBlend(
          accent.withValues(alpha: .09),
          theme.colorScheme.surface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(color: accent.withValues(alpha: .16)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(26),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 29, color: accent),
                const SizedBox(height: 20),
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
