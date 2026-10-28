import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';
import 'design.dart';
import 'motion.dart';

class OpponentsStrip extends StatefulWidget {
  final Room room;
  final bool compact;
  final VoidCallback onDetails;
  const OpponentsStrip({
    super.key,
    required this.room,
    required this.compact,
    required this.onDetails,
  });

  @override
  State<OpponentsStrip> createState() => _OpponentsStripState();
}

class _OpponentsStripState extends State<OpponentsStrip> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealTurn());
  }

  @override
  void didUpdateWidget(covariant OpponentsStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.turn != widget.room.turn ||
        oldWidget.room.players.length != widget.room.players.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealTurn());
    }
  }

  void _revealTurn() {
    if (!mounted || !_scroll.hasClients) return;
    final opponents = widget.room.players
        .where((p) => p.id != widget.room.you)
        .toList();
    final index = opponents.indexWhere((p) => p.id == widget.room.turn);
    if (index < 0) return;
    final target =
        (12 + index * 148 - (_scroll.position.viewportDimension - 138) / 2)
            .clamp(0.0, _scroll.position.maxScrollExtent);
    if (GameMotion.reduced(context)) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 480),
        curve: GameMotion.settle,
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final opponents = room.players.where((p) => p.id != room.you).toList();
    final theme = Theme.of(context), colors = theme.colorScheme;
    final textExtra =
        math.max(0.0, MediaQuery.textScalerOf(context).scale(13) - 13) * 2;
    return SizedBox(
      height: (widget.compact ? 76 : 88) + textExtra,
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        itemCount: opponents.length,
        separatorBuilder: (_, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final player = opponents[index], current = player.id == room.turn;
          final inactive =
              player.eliminated || room.departed.contains(player.id);
          return AnimatedContainer(
            key: ValueKey(player.id),
            duration: GameMotion.duration(context, 420),
            curve: GameMotion.change,
            width: 138,
            decoration: BoxDecoration(
              color: current
                  ? colors.primaryContainer
                  : colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: current
                    ? colors.primary
                    : colors.outlineVariant.withValues(alpha: .6),
                width: 1.5,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: widget.onDetails,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Row(
                    children: [
                      ProfileAvatar(
                        name: player.name,
                        radius: 17,
                        url:
                            '${object(object(room.raw['profiles'])[player.id])['avatar_url'] ?? ''}',
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              player.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 3),
                            MotionSwitcher(
                              child: Text(
                                player.eliminated
                                    ? '已淘汰'
                                    : room.departed.contains(player.id)
                                    ? '已离开'
                                    : '${player.handCount} 张${current ? ' · 出牌' : ''}',
                                key: ValueKey((
                                  player.handCount,
                                  current,
                                  inactive,
                                )),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: player.handCount == 1 && !inactive
                                      ? cardColor('red')
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class TableArena extends StatelessWidget {
  final Room room;
  final bool compact;
  final double minHeight;
  final VoidCallback? onDraw, onPlay;
  const TableArena({
    super.key,
    required this.room,
    required this.compact,
    required this.minHeight,
    this.onDraw,
    this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final mine = room.turn == room.you && !room.isSpectator;
    final active = cardColor(room.activeColor);
    final pending = integer(room.state['pending_draw']);
    final finishing = room.state['finishing_player'] != null;
    final top = room.topCard;
    return AnimatedContainer(
      duration: GameMotion.duration(context, 620),
      curve: GameMotion.change,
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: Color.alphaBlend(active.withValues(alpha: .075), colors.surface),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: active.withValues(alpha: .18)),
      ),
      child: CustomPaint(
        painter: _TableRings(active.withValues(alpha: .055)),
        child: Padding(
          padding: EdgeInsets.all(compact ? 14 : 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: MotionSwitcher(
                        child: Text(
                          finishing
                              ? '等待 +4 结算'
                              : mine
                              ? '轮到你出牌'
                              : '${room.playerName(room.turn)} 的回合',
                          key: ValueKey((room.turn, finishing)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TableTag(
                    color: active,
                    label: switch (room.activeColor) {
                      'red' => '红色',
                      'blue' => '蓝色',
                      'green' => '绿色',
                      'yellow' => '黄色',
                      _ => '万能',
                    },
                  ),
                ],
              ),
              SizedBox(height: compact ? 16 : 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    children: [
                      Semantics(
                        label:
                            '摸一张，牌堆还有 ${integer(room.state['draw_pile_count'])} 张',
                        button: onDraw != null,
                        onTap: onDraw,
                        excludeSemantics: true,
                        child: SizedBox(
                          width: compact ? 64 : 80,
                          height: (compact ? 56 : 68) * 1.46 + 6,
                          child: Stack(
                            alignment: Alignment.topCenter,
                            children: [
                              Positioned(
                                top: 6,
                                child: _DeckEdge(width: compact ? 56 : 68),
                              ),
                              Positioned(
                                top: 3,
                                child: _DeckEdge(width: compact ? 56 : 68),
                              ),
                              PlayingCard(
                                width: compact ? 56 : 68,
                                onTap: onDraw,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        '牌堆 · ${integer(room.state['draw_pile_count'])}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 12 : 22,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: integer(room.state['direction'], 1) == 1
                              ? '顺时针出牌'
                              : '逆时针出牌',
                          child: AnimatedRotation(
                            turns: integer(room.state['direction'], 1) == 1
                                ? 0
                                : 1,
                            duration: GameMotion.duration(context, 550),
                            curve: GameMotion.spring,
                            child: Icon(
                              integer(room.state['direction'], 1) == 1
                                  ? Icons.rotate_right_rounded
                                  : Icons.rotate_left_rounded,
                              color: colors.onSurfaceVariant,
                              size: compact ? 25 : 30,
                            ),
                          ),
                        ),
                        if (pending > 0) ...[
                          const SizedBox(height: 8),
                          MotionSwitcher(
                            child: Text(
                              '+$pending',
                              key: ValueKey(pending),
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: cardColor('red'),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      AnimatedSwitcher(
                        duration: GameMotion.duration(context, 460),
                        reverseDuration: GameMotion.duration(context, 180),
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.center,
                          children: [
                            for (final old in previous)
                              ExcludeSemantics(
                                child: IgnorePointer(child: old),
                              ),
                            if (current != null) current,
                          ],
                        ),
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation.drive(
                            CurveTween(curve: Curves.easeOut),
                          ),
                          child: SlideTransition(
                            position:
                                Tween(
                                  begin: const Offset(.16, .28),
                                  end: Offset.zero,
                                ).animate(
                                  animation.drive(
                                    CurveTween(curve: GameMotion.settle),
                                  ),
                                ),
                            child: ScaleTransition(
                              scale: Tween(begin: .86, end: 1.0).animate(
                                animation.drive(
                                  CurveTween(curve: GameMotion.spring),
                                ),
                              ),
                              child: child,
                            ),
                          ),
                        ),
                        child: PlayingCard(
                          key: ValueKey((room.id, room.round, top?.id)),
                          card: top,
                          width: compact ? 70 : 88,
                          onTap: onPlay,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        '当前牌',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TableTag extends StatelessWidget {
  final Color color;
  final String label;
  const TableTag({super.key, required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: .8),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _DeckEdge extends StatelessWidget {
  final double width;
  const _DeckEdge({required this.width});

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: width * 1.46,
    decoration: BoxDecoration(
      color: const Color(0xffc7bedf),
      borderRadius: BorderRadius.circular(width * .15),
      border: Border.all(color: Colors.white, width: 2),
    ),
  );
}

class _TableRings extends CustomPainter {
  final Color color;
  const _TableRings(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final center = Offset(size.width / 2, size.height * .6);
    for (var i = 0; i < 3; i++) {
      final width = size.width * (.6 + i * .2);
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: width,
          height: math.min(size.height * .8, width * .65),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TableRings oldDelegate) => oldDelegate.color != color;
}
