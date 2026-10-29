import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/controller.dart';
import '../core/match_history.dart';
import '../game/design.dart';
import '../game/motion.dart';

String matchDate(DateTime date) {
  final local = date.toLocal();
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${local.year}/${pad(local.month)}/${pad(local.day)} ${pad(local.hour)}:${pad(local.minute)}';
}

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(appProvider).history;
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('本机战绩'),
        actions: [
          IconButton(
            tooltip: '清空本机战绩',
            onPressed: history.records.isEmpty
                ? null
                : () async {
                    if (await confirm(
                      context,
                      '清空本机战绩？',
                      '删除当前账户在这台设备上的战绩与回顾。正在记录的这局也会停止保存。',
                    )) {
                      await history.clear();
                    }
                  },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                MotionEntrance(
                  child: GamePanel(
                    color: colors.primaryContainer,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.emoji_events_outlined,
                              color: colors.onPrimaryContainer,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '这台设备上的牌局',
                              style: theme.textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        LayoutBuilder(
                          builder: (context, constraints) => Wrap(
                            spacing: 12,
                            runSpacing: 16,
                            children: [
                              for (final (value, label) in [
                                ('${history.completed}', '已结算'),
                                ('${history.wins}', '获胜'),
                                (
                                  history.winRate == null
                                      ? '—'
                                      : '${history.winRate}%',
                                  '胜率',
                                ),
                              ])
                                SizedBox(
                                  width: (constraints.maxWidth - 24) / 3,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        value,
                                        style: theme.textTheme.headlineSmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        label,
                                        style: theme.textTheme.labelMedium,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (history.unsettled > 0) ...[
                          const SizedBox(height: 16),
                          Text('${history.unsettled} 局未收到结算，不计入胜率'),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '仅记录本机参与并收到的牌局，按账户保存。保留最近 ${MatchHistory.maxRecords} 局。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (history.storageError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    history.storageError!,
                    style: TextStyle(color: colors.error),
                  ),
                  TextButton.icon(
                    onPressed: history.flush,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('重试保存'),
                  ),
                ],
                const SizedBox(height: 24),
                if (history.records.isEmpty)
                  const GamePanel(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        children: [
                          Icon(Icons.style_outlined, size: 42),
                          SizedBox(height: 14),
                          Text('还没有本机战绩'),
                          SizedBox(height: 6),
                          Text('参与一局后，这里会留下记录。', textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
                for (final record in history.records) ...[
                  MatchResultTile(record: record),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MatchResultTile extends StatelessWidget {
  final MatchRecord record;
  final VoidCallback? onTap;
  const MatchResultTile({super.key, required this.record, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final accent = record.won ? cardColor('yellow') : colors.primary;
    return GamePanel(
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: .14),
          foregroundColor: record.won && theme.brightness == Brightness.light
              ? const Color(0xff7d5600)
              : accent,
          child: Icon(
            record.won ? Icons.emoji_events_rounded : Icons.style_rounded,
          ),
        ),
        title: Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(record.resultLabel, style: theme.textTheme.titleMedium),
            Text(
              '${record.hasBots ? '含电脑' : '多人'} · 第 ${record.round} 局',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            [
              '牌桌 ${record.roomId}',
              matchDate(record.endedAt ?? record.startedAt),
              if (record.finished && record.latest.winner.isNotEmpty)
                '胜者：${record.latest.playerName(record.latest.winner)}',
            ].join('\n'),
          ),
        ),
        trailing: onTap == null
            ? null
            : const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
