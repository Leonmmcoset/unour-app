import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/controller.dart';
import '../core/match_history.dart';
import '../core/match_review.dart';
import '../game/design.dart';
import '../game/motion.dart';
import '../game/round_summary.dart';
import 'history.dart';

class MatchReviewPage extends ConsumerStatefulWidget {
  final String recordId;
  const MatchReviewPage({super.key, required this.recordId});

  @override
  ConsumerState<MatchReviewPage> createState() => _MatchReviewPageState();
}

class _MatchReviewPageState extends ConsumerState<MatchReviewPage> {
  MatchFrame? _selectedFrame;

  @override
  void didUpdateWidget(covariant MatchReviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recordId != widget.recordId) _selectedFrame = null;
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final record = app.history.find(widget.recordId);
    if (record == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('牌局回顾')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('这条本机记录已清除或不属于当前账户。', textAlign: TextAlign.center),
          ),
        ),
      );
    }
    final frames = record.frames;
    var index = _selectedFrame == null
        ? frames.length - 1
        : frames.indexOf(_selectedFrame!);
    if (index < 0) index = frames.length - 1;
    final selected = frames[index];
    final active =
        app.room != null &&
        app.history.forRoom(app.room!)?.id == record.id &&
        !record.finished;
    final theme = Theme.of(context), colors = theme.colorScheme;
    void select(int next) => setState(() {
      _selectedFrame = frames[next];
    });

    return Scaffold(
      appBar: AppBar(title: const Text('牌局回顾')),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '牌桌 ${record.roomId}',
                      style: theme.textTheme.titleLarge,
                    ),
                    Text(
                      '第 ${record.round} 局 · ${record.resultLabel}',
                      style: theme.textTheme.labelLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '仅含本机收到的公开牌况；中途加入、切到后台或断线时可能漏记。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (record.omittedFrames > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '记录较长，已省略 ${record.omittedFrames} 条较早的牌况，保留起点和最近记录。',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 20),
                GamePanel(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '记录 ${index + 1} / ${frames.length}',
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          if (active)
                            TextButton.icon(
                              onPressed: _selectedFrame == null
                                  ? null
                                  : () => setState(() => _selectedFrame = null),
                              icon: const Icon(Icons.update_rounded, size: 17),
                              label: const Text('最新'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      MotionSwitcher(
                        child: _FrameTable(
                          key: ObjectKey(selected),
                          frame: selected,
                          myId: record.myId,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          IconButton.filledTonal(
                            tooltip: '上一条牌况',
                            onPressed: index == 0
                                ? null
                                : () => select(index - 1),
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          Expanded(
                            child: Slider(
                              label: '第 ${index + 1} 条',
                              semanticFormatterCallback: (value) =>
                                  '第 ${value.round() + 1} 条，共 ${frames.length} 条',
                              min: 0,
                              max: (frames.length - 1)
                                  .clamp(1, MatchHistory.maxFrames)
                                  .toDouble(),
                              divisions: frames.length > 1
                                  ? frames.length - 1
                                  : null,
                              value: index.toDouble(),
                              onChanged: frames.length <= 1
                                  ? null
                                  : (value) => select(value.round()),
                            ),
                          ),
                          IconButton.filledTonal(
                            tooltip: '下一条牌况',
                            onPressed: index == frames.length - 1
                                ? null
                                : () => select(index + 1),
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('收到的变化', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                GamePanel(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      for (final change in matchChanges(
                        index == 0 ? null : frames[index - 1],
                        selected,
                      ))
                        ListTile(
                          leading: Icon(
                            _changeIcon(change.kind),
                            color: change.kind == MatchChangeKind.gap
                                ? colors.tertiary
                                : colors.primary,
                          ),
                          title: Text(
                            change.text,
                            style: theme.textTheme.bodyMedium,
                          ),
                          dense: true,
                        ),
                    ],
                  ),
                ),
                if (record.finished) ...[
                  const SizedBox(height: 24),
                  MatchHighlights(record: record),
                ],
                const SizedBox(height: 24),
                Text('记录时间线', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                for (final (position, frame) in frames.indexed)
                  _TimelineStep(
                    frame: frame,
                    position: position,
                    myId: record.myId,
                    selected: position == index,
                    onTap: () => select(position),
                    last: position == frames.length - 1,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

IconData _changeIcon(MatchChangeKind kind) => switch (kind) {
  MatchChangeKind.gap => Icons.more_horiz_rounded,
  MatchChangeKind.card => Icons.style_outlined,
  MatchChangeKind.turn => Icons.person_outline_rounded,
  MatchChangeKind.count => Icons.numbers_rounded,
  MatchChangeKind.uno => Icons.campaign_outlined,
  MatchChangeKind.penalty => Icons.add_card_rounded,
  MatchChangeKind.direction => Icons.swap_horiz_rounded,
  MatchChangeKind.color => Icons.palette_outlined,
  MatchChangeKind.finish => Icons.emoji_events_outlined,
  MatchChangeKind.roster => Icons.people_outline_rounded,
  MatchChangeKind.opening => Icons.flag_outlined,
};

class _FrameTable extends StatelessWidget {
  final MatchFrame frame;
  final String myId;
  const _FrameTable({super.key, required this.frame, required this.myId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PlayingCard(card: frame.topCard, width: 54),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      frame.topCard?.label ?? '等待牌面',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '当前${colorName(frame.activeColor)} · ${frame.direction == 1 ? '顺时针' : '逆时针'}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      frame.phase == 'finished'
                          ? frame.winner.isEmpty
                                ? '本局结束 · 无胜者'
                                : '${frame.playerName(frame.winner)} 获胜'
                          : '轮到${frame.turn == myId ? '你' : frame.playerName(frame.turn)}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.primary,
                      ),
                    ),
                    if (frame.pendingDraw > 0)
                      Text(
                        '罚牌池 +${frame.pendingDraw}',
                        style: theme.textTheme.labelLarge,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final player in frame.players)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: player.id == myId
                        ? colors.secondaryContainer
                        : colors.surfaceContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${player.id == myId ? '我' : player.name} · ${player.departed
                        ? '已离开'
                        : player.eliminated
                        ? '已淘汰'
                        : '${player.count} 张'}',
                    style: theme.textTheme.labelMedium,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            matchDate(frame.at),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (frame.gapBefore) ...[
            const SizedBox(height: 8),
            Text(
              '此前有未记录的变化',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.tertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final MatchFrame frame;
  final int position;
  final String myId;
  final bool selected, last;
  final VoidCallback onTap;
  const _TimelineStep({
    required this.frame,
    required this.position,
    required this.myId,
    required this.selected,
    required this.onTap,
    required this.last,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                const SizedBox(height: 20),
                Container(
                  width: selected ? 12 : 8,
                  height: selected ? 12 : 8,
                  decoration: BoxDecoration(
                    color: selected ? colors.primary : colors.outlineVariant,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 2, color: colors.outlineVariant),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 8),
              child: Material(
                color: selected
                    ? colors.secondaryContainer
                    : colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(18),
                child: ListTile(
                  selected: selected,
                  onTap: onTap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  title: Text(
                    '${position + 1}. ${frame.phase == 'finished' ? '收到结算' : frame.topCard?.label ?? '牌况记录'}',
                    style: theme.textTheme.titleSmall,
                  ),
                  subtitle: Text(
                    [
                      if (frame.gapBefore) '··· 此前有记录缺口',
                      '${frame.player(myId)?.count ?? '—'} 张手牌 · ${matchDate(frame.at)}',
                    ].join('\n'),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check_rounded, size: 20)
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
