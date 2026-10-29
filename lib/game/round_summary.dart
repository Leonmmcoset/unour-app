import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/match_highlights.dart';
import '../core/match_history.dart';
import 'design.dart';
import 'motion.dart';

class MatchHighlights extends StatelessWidget {
  final MatchRecord record;
  final bool animate;
  const MatchHighlights({
    super.key,
    required this.record,
    this.animate = false,
  });

  @override
  Widget build(BuildContext context) {
    final highlights = matchHighlights(record);
    if (highlights.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('这局的小插曲', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          '来自本机收到的牌况',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        for (final (index, highlight) in highlights.indexed) ...[
          MotionEntrance(
            key: ValueKey((record.id, highlight.kind)),
            delay: 120 + index * 100,
            offset: const Offset(18, 8),
            animate: animate,
            child: _HighlightCard(highlight: highlight),
          ),
          if (index < highlights.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _HighlightCard extends StatelessWidget {
  final MatchHighlight highlight;
  const _HighlightCard({required this.highlight});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final accent = cardColor(switch (highlight.kind) {
      HighlightKind.uno || HighlightKind.close => 'red',
      HighlightKind.pressure => 'blue',
      HighlightKind.direction => 'green',
      _ => 'yellow',
    });
    final foreground = Color.alphaBlend(
      accent.withValues(alpha: .75),
      colors.onSurface,
    );
    return GamePanel(
      color: Color.alphaBlend(accent.withValues(alpha: .08), colors.surface),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 66,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: accent.withValues(alpha: .25)),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  highlight.value,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w900,
                    fontSize: 25,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(highlight.title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  highlight.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A finite card fan with staggered spring travel and a soft settling turn.
/// It ends completely; polling the settled round cannot restart the ticker.
class SettlementEmblem extends StatefulWidget {
  final bool hasWinner;
  const SettlementEmblem({super.key, required this.hasWinner});

  @override
  State<SettlementEmblem> createState() => _SettlementEmblemState();
}

class _SettlementEmblemState extends State<SettlementEmblem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (GameMotion.reduced(context)) {
      _controller.value = 1;
      _started = true;
    } else if (!_started) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RoundCelebration(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < 4; i++) _card(i),
            Transform.scale(
              scale:
                  .7 +
                  .3 *
                      GameMotion.spring.transform(
                        ((_controller.value - .15) / .65).clamp(0.0, 1.0),
                      ),
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: cardColor('yellow').withValues(alpha: .3),
                    width: 2,
                  ),
                ),
                child: Icon(
                  widget.hasWinner
                      ? Icons.emoji_events_rounded
                      : Icons.style_rounded,
                  color: cardColor('yellow'),
                  size: 48,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _card(int index) {
    final progress = ((_controller.value - index * .065) / .7).clamp(0.0, 1.0);
    final travel = GameMotion.spring.transform(progress);
    final angle = (index - 1.5) * .33;
    return Opacity(
      opacity: Curves.easeOut.transform(progress),
      child: Transform.translate(
        offset: Offset(
          math.sin(angle) * 92 * travel,
          -18 * travel + 25 * (1 - travel),
        ),
        child: Transform.rotate(
          angle: angle * travel,
          child: Container(
            width: 47,
            height: 68,
            decoration: BoxDecoration(
              color: cardColor(['red', 'blue', 'green', 'yellow'][index]),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: Colors.white.withValues(alpha: .8),
                width: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
