import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';
import 'design.dart';
import 'motion.dart';

List<UnoCard> sortedHand(Iterable<UnoCard> cards) {
  const colors = ['red', 'yellow', 'green', 'blue', 'wild'];
  const kinds = [
    'number',
    'skip',
    'reverse',
    'draw_two',
    'wild',
    'wild_draw_four',
  ];
  int rank(UnoCard card) =>
      !colors.contains(card.color) ? colors.length : colors.indexOf(card.color);
  return cards.toList()..sort((a, b) {
    var result = rank(a).compareTo(rank(b));
    if (result == 0) {
      result = kinds.indexOf(a.kind).compareTo(kinds.indexOf(b.kind));
    }
    if (result == 0) result = a.number.compareTo(b.number);
    if (result == 0) result = a.id.compareTo(b.id);
    return result;
  });
}

/// Straight cards share a fixed step, with modest overlap so a normal hand
/// fits on a phone. Selecting one changes its elevation, never its slot.
class HandStrip extends StatefulWidget {
  final List<UnoCard> cards;
  final int? selected;
  final double cardWidth;
  final bool reduceMotion, dimUnavailable, sorted;
  final bool Function(UnoCard) isPlayable;
  final ValueChanged<UnoCard> onTap;

  const HandStrip({
    super.key,
    required this.cards,
    required this.selected,
    required this.isPlayable,
    required this.onTap,
    this.cardWidth = 78,
    this.reduceMotion = false,
    this.dimUnavailable = false,
    this.sorted = false,
  });

  @override
  State<HandStrip> createState() => _HandStripState();
}

class _HandStripState extends State<HandStrip>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  late final AnimationController _change = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final List<UnoCard> _cards = List.of(widget.cards);
  late List<_CardPose> _poses;
  Timer? _revealTimer;
  double _step = 48, _start = 12;
  double _fromCount = 0, _toCount = 0;

  List<UnoCard> get _ordered => widget.sorted ? sortedHand(_cards) : _cards;
  bool get _reduce => widget.reduceMotion || GameMotion.reduced(context);
  double get _progress => GameMotion.settle.transform(_change.value);

  @override
  void initState() {
    super.initState();
    _poses = [
      for (final (index, card) in _ordered.indexed)
        _CardPose(card, index.toDouble(), index.toDouble(), 1, 1),
    ];
    _fromCount = _toCount = _cards.length.toDouble();
    _change.value = 1;
    _change.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _poses.removeWhere((pose) => pose.toOpacity == 0));
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduce && _change.isAnimating) _change.value = 1;
  }

  @override
  void didUpdateWidget(covariant HandStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_reduce && _change.isAnimating) _change.value = 1;
    final incoming = {for (final card in widget.cards) card.id: card};
    _cards.removeWhere((card) => !incoming.containsKey(card.id));
    for (var i = 0; i < _cards.length; i++) {
      _cards[i] = incoming[_cards[i].id]!;
    }
    final existing = _cards.map((card) => card.id).toSet();
    final added = widget.cards
        .where((card) => !existing.contains(card.id))
        .toList();
    _cards.addAll(added);
    final ordered = _ordered;
    final current = {for (final pose in _poses) pose.card.id: pose};
    final changed =
        current.values.where((pose) => pose.toOpacity == 1).length !=
            ordered.length ||
        ordered.indexed.any(
          (entry) =>
              current[entry.$2.id]?.toSlot != entry.$1 ||
              current[entry.$2.id]?.toOpacity != 1,
        );
    if (changed) {
      final t = _progress;
      _fromCount += (_toCount - _fromCount) * t;
      _toCount = ordered.length.toDouble();
      final nextIds = ordered.map((card) => card.id).toSet();
      _poses = [
        for (final pose in _poses.where(
          (pose) => !nextIds.contains(pose.card.id),
        ))
          _CardPose(pose.card, pose.slot(t), pose.slot(t), pose.opacity(t), 0),
        for (final (index, card) in ordered.indexed)
          _CardPose(
            card,
            current[card.id]?.slot(t) ?? index.toDouble(),
            index.toDouble(),
            current[card.id]?.opacity(t) ?? 0,
            1,
          ),
      ];
      if (_reduce) {
        _poses.removeWhere((pose) => pose.toOpacity == 0);
        _change.value = 1;
      } else {
        _change.forward(from: 0);
      }
    }
    if (widget.selected != oldWidget.selected ||
        oldWidget.sorted != widget.sorted) {
      _scheduleReveal(widget.selected);
    } else if (added.isNotEmpty) {
      _scheduleReveal(added.first.id, afterChange: true);
    }
  }

  void _scheduleReveal(int? id, {bool afterChange = false}) {
    _revealTimer?.cancel();
    if (id == null) return;
    if (afterChange && !_reduce) {
      _revealTimer = Timer(
        const Duration(milliseconds: 340),
        () => _reveal(id),
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(id));
    }
  }

  void _reveal(int id) {
    if (!mounted ||
        !_scroll.hasClients ||
        _scroll.position.isScrollingNotifier.value) {
      return;
    }
    final index = _ordered.indexWhere((card) => card.id == id);
    if (index < 0) return;
    final left = _start + index * _step;
    final right = left + widget.cardWidth;
    final visibleLeft = _scroll.offset + 8;
    final visibleRight =
        _scroll.offset + _scroll.position.viewportDimension - 8;
    final offset = left < visibleLeft
        ? left - 8
        : right > visibleRight
        ? right - _scroll.position.viewportDimension + 8
        : _scroll.offset;
    final target = offset.clamp(0.0, _scroll.position.maxScrollExtent);
    if (_reduce) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: GameMotion.settle,
      );
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _change.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Keep the step unchanged when cards are drawn, played or selected.
      _step = ((constraints.maxWidth - 24 - widget.cardWidth) / 6).clamp(
        44.0,
        58.0,
      );
      final height = widget.cardWidth * 1.46 + 30;
      return SizedBox(
        height: height,
        child: AnimatedBuilder(
          animation: _change,
          builder: (context, child) {
            final t = _reduce ? 1.0 : _progress;
            final count = _fromCount + (_toCount - _fromCount) * t;
            final maxSlot = _poses.fold(
              0.0,
              (value, pose) => math.max(value, pose.slot(t)),
            );
            final width = _poses.isEmpty
                ? constraints.maxWidth
                : math.max(
                    constraints.maxWidth,
                    maxSlot * _step + widget.cardWidth + 24,
                  );
            final visibleWidth = count == 0
                ? 0.0
                : math.max(0, count - 1) * _step + widget.cardWidth;
            _start = math.max(12, (constraints.maxWidth - visibleWidth) / 2);
            final poses = [
              ..._poses.where((pose) => pose.toOpacity == 0),
              ..._poses.where(
                (pose) =>
                    pose.toOpacity == 1 && pose.card.id != widget.selected,
              ),
              ..._poses.where(
                (pose) =>
                    pose.toOpacity == 1 && pose.card.id == widget.selected,
              ),
            ];
            return SingleChildScrollView(
              key: const ValueKey('hand-scroll'),
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                height: height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final pose in poses)
                      Positioned(
                        key: ValueKey(pose.card.id),
                        left: _start + pose.slot(t) * _step,
                        top: 18 + (1 - pose.opacity(t)) * 12,
                        child: IgnorePointer(
                          ignoring: pose.toOpacity == 0,
                          child: ExcludeSemantics(
                            excluding: pose.toOpacity == 0,
                            child: Opacity(
                              opacity: pose.opacity(t),
                              child: AnimatedSlide(
                                offset: widget.selected == pose.card.id
                                    ? const Offset(0, -.085)
                                    : Offset.zero,
                                duration: Duration(
                                  milliseconds: _reduce ? 0 : 260,
                                ),
                                curve: GameMotion.spring,
                                child: PlayingCard(
                                  key: ValueKey('hand-card-${pose.card.id}'),
                                  card: pose.card,
                                  width: widget.cardWidth,
                                  selected: pose.card.id == widget.selected,
                                  playable:
                                      !widget.dimUnavailable ||
                                      widget.isPlayable(pose.card),
                                  onTap: pose.toOpacity == 0
                                      ? null
                                      : () => widget.onTap(pose.card),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

class _CardPose {
  final UnoCard card;
  final double fromSlot, toSlot, fromOpacity, toOpacity;
  const _CardPose(
    this.card,
    this.fromSlot,
    this.toSlot,
    this.fromOpacity,
    this.toOpacity,
  );
  double slot(double t) => fromSlot + (toSlot - fromSlot) * t;
  double opacity(double t) =>
      (fromOpacity + (toOpacity - fromOpacity) * t).clamp(0, 1);
}
