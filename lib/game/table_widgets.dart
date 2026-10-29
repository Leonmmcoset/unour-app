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
  double _step = 80;

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
        (12 + index * _step - (_scroll.position.viewportDimension - _step) / 2)
            .clamp(0.0, _scroll.position.maxScrollExtent);
    if (GameMotion.reduced(context)) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 400),
        curve: GameMotion.settle,
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _player(BuildContext context, Player player) {
    final room = widget.room;
    final current = player.id == room.turn;
    final inactive = player.eliminated || room.departed.contains(player.id);
    final theme = Theme.of(context), colors = theme.colorScheme;
    final radius = widget.compact ? 18.0 : 23.0;
    return Semantics(
      label:
          '${player.name}，${inactive
              ? player.eliminated
                    ? '已淘汰'
                    : '已离开'
              : '${player.handCount} 张牌'}${current ? '，正在出牌' : ''}',
      button: true,
      onTap: widget.onDetails,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onDetails,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: radius * 2 + 14,
                  height: radius * 2 + 12,
                  child: Stack(
                    children: [
                      AnimatedContainer(
                        duration: GameMotion.duration(context, 350),
                        curve: GameMotion.settle,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: current
                              ? colors.primaryContainer
                              : Colors.transparent,
                          border: Border.all(
                            width: 1.5,
                            color: current
                                ? colors.primary
                                : Colors.transparent,
                          ),
                        ),
                        child: Opacity(
                          opacity: inactive ? .45 : 1,
                          child: ProfileAvatar(
                            name: player.name,
                            radius: radius,
                            url:
                                '${object(object(room.raw['profiles'])[player.id])['avatar_url'] ?? ''}',
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: AnimatedContainer(
                          duration: GameMotion.duration(context, 250),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: player.handCount == 1 && !inactive
                                ? cardColor('red')
                                : current
                                ? colors.primary
                                : colors.inverseSurface,
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: colors.surface, width: 2),
                          ),
                          child: MotionSwitcher(
                            child: Text(
                              inactive ? '–' : '${player.handCount}',
                              key: ValueKey(player.handCount),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                                color:
                                    current ||
                                        (player.handCount == 1 && !inactive)
                                    ? colors.onPrimary
                                    : colors.onInverseSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  player.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: current ? FontWeight.w800 : FontWeight.w500,
                    color: current ? colors.primary : colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final opponents = widget.room.players
        .where((p) => p.id != widget.room.you)
        .toList();
    final textExtra =
        math.max(0.0, MediaQuery.textScalerOf(context).scale(12) - 12) * 2;
    return SizedBox(
      key: const ValueKey('opponents'),
      height: (widget.compact ? 82 : 94) + textExtra,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slot = widget.compact ? 68.0 : 76.0;
          _step = slot + 8;
          if (opponents.length * _step <= constraints.maxWidth - 24) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final player in opponents)
                  SizedBox(
                    key: ValueKey(player.id),
                    width: slot,
                    child: _player(context, player),
                  ),
              ],
            );
          }
          return ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: opponents.length,
            separatorBuilder: (_, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) => SizedBox(
              width: slot,
              child: _player(context, opponents[index]),
            ),
          );
        },
      ),
    );
  }
}

class TurnBanner extends StatelessWidget {
  final Room room;
  const TurnBanner({super.key, required this.room});

  @override
  Widget build(BuildContext context) {
    final mine = room.turn == room.you && !room.isSpectator;
    final colors = Theme.of(context).colorScheme;
    final label = room.state['finishing_player'] != null
        ? '等待最后一张 +4 结算'
        : mine
        ? '轮到你出牌'
        : '等待 ${room.playerName(room.turn)} 出牌';
    return AnimatedContainer(
      key: const ValueKey('turn-banner'),
      duration: GameMotion.duration(context, 350),
      curve: GameMotion.change,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? colors.primaryContainer : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            mine ? Icons.play_arrow_rounded : Icons.more_horiz_rounded,
            size: 20,
            color: mine ? colors.primary : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: MotionSwitcher(
              child: Align(
                alignment: Alignment.centerLeft,
                key: ValueKey(label),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: mine
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TableArena extends StatelessWidget {
  final Room room;
  final bool compact;
  final double minHeight;
  final VoidCallback? onDraw, onPlay;
  final Widget? overlay;
  const TableArena({
    super.key,
    required this.room,
    required this.compact,
    required this.minHeight,
    this.onDraw,
    this.onPlay,
    this.overlay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final active = cardColor(room.activeColor);
    final pending = integer(room.state['pending_draw']);
    final direction = integer(room.state['direction'], 1);
    final width = compact ? 60.0 : 88.0;
    return Stack(
      alignment: Alignment.center,
      children: [
        CustomPaint(
          painter: _TableRings(active.withValues(alpha: .09)),
          child: Container(
            key: const ValueKey('table-arena'),
            constraints: BoxConstraints(minHeight: minHeight),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 22 : 30,
              vertical: compact ? 6 : 8,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedRotation(
                          turns: direction == 1 ? 0 : 1,
                          curve: GameMotion.spring,
                          duration: GameMotion.duration(context, 500),
                          child: Icon(
                            direction == 1
                                ? Icons.rotate_right_rounded
                                : Icons.rotate_left_rounded,
                            size: 18,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          direction == 1 ? '顺时针' : '逆时针',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: compact ? 8 : 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TablePile(
                      width: width,
                      compact: compact,
                      label: '牌堆 · ${integer(room.state['draw_pile_count'])}',
                      child: Semantics(
                        label:
                            '摸一张，牌堆还有 ${integer(room.state['draw_pile_count'])} 张',
                        button: onDraw != null,
                        onTap: onDraw,
                        excludeSemantics: true,
                        child: SizedBox(
                          width: width,
                          height: width * 1.46 + 8,
                          child: Stack(
                            alignment: Alignment.topCenter,
                            children: [
                              Positioned(
                                top: 6,
                                child: _DeckEdge(width: width),
                              ),
                              Positioned(
                                top: 3,
                                child: _DeckEdge(width: width),
                              ),
                              PlayingCard(width: width, onTap: onDraw),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: compact ? 36 : 48),
                    _TablePile(
                      width: width,
                      compact: compact,
                      label: '当前牌',
                      child: AnimatedSwitcher(
                        duration: GameMotion.duration(context, 420),
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
                          key: ValueKey((
                            room.id,
                            room.round,
                            room.topCard?.id,
                          )),
                          card: room.topCard,
                          width: width,
                          onTap: onPlay,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 6 : 10),
                if (pending > 0)
                  MotionSwitcher(
                    child: Text(
                      '罚牌池 +$pending',
                      key: ValueKey(pending),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: cardColor('red'),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (overlay != null) overlay!,
      ],
    );
  }
}

class _TablePile extends StatelessWidget {
  final double width;
  final bool compact;
  final String label;
  final Widget child;
  const _TablePile({
    required this.width,
    required this.compact,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: width,
        height: width * 1.46 + 8,
        child: Align(alignment: Alignment.topCenter, child: child),
      ),
      SizedBox(height: compact ? 8 : 10),
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
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
