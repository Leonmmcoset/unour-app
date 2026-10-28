import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import 'design.dart';
import 'motion.dart';

/// A row of full, equally sized cards. Surviving cards keep their positions
/// even if a later snapshot serializes the same hand in a different order.
class HandStrip extends StatefulWidget {
  final List<UnoCard> cards;
  final int? selected;
  final double cardWidth;
  final bool reduceMotion, dimUnavailable;
  final bool Function(UnoCard) isPlayable;
  final ValueChanged<UnoCard> onTap;

  const HandStrip({
    super.key,
    required this.cards,
    required this.selected,
    required this.isPlayable,
    required this.onTap,
    this.cardWidth = 80,
    this.reduceMotion = false,
    this.dimUnavailable = false,
  });

  @override
  State<HandStrip> createState() => _HandStripState();
}

class _HandStripState extends State<HandStrip> {
  final _list = GlobalKey<AnimatedListState>();
  final _scroll = ScrollController();
  late final List<UnoCard> _cards = List.of(widget.cards);
  Timer? _revealTimer;

  Duration get _duration =>
      Duration(milliseconds: widget.reduceMotion ? 0 : 380);

  @override
  void didUpdateWidget(covariant HandStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = {for (final card in widget.cards) card.id: card};
    for (var index = _cards.length - 1; index >= 0; index--) {
      if (!next.containsKey(_cards[index].id)) {
        final removed = _cards.removeAt(index);
        _list.currentState?.removeItem(
          index,
          (context, animation) => _tile(removed, animation, removing: true),
          duration: _duration,
        );
      } else {
        _cards[index] = next[_cards[index].id]!;
      }
    }
    final ids = _cards.map((card) => card.id).toSet();
    final added = widget.cards.where((card) => !ids.contains(card.id)).toList();
    for (final card in added) {
      _cards.add(card);
      _list.currentState?.insertItem(_cards.length - 1, duration: _duration);
    }
    if (widget.selected != oldWidget.selected && widget.selected != null) {
      _revealTimer?.cancel();
      final selected = widget.selected!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(selected));
    } else if (added.isNotEmpty &&
        (!_scroll.hasClients || !_scroll.position.isScrollingNotifier.value)) {
      _revealTimer?.cancel();
      _revealTimer = Timer(_duration, () => _reveal(added.first.id));
    }
  }

  void _reveal(int id) {
    if (!mounted || !_scroll.hasClients) return;
    final index = _cards.indexWhere((card) => card.id == id);
    if (index < 0) return;
    final target =
        (16 +
                index * (widget.cardWidth + 10) -
                (_scroll.position.viewportDimension - widget.cardWidth) / 2)
            .clamp(0.0, _scroll.position.maxScrollExtent);
    if (widget.reduceMotion) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 420),
        curve: GameMotion.settle,
      );
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Widget _tile(
    UnoCard card,
    Animation<double> animation, {
    bool removing = false,
  }) {
    if (removing && widget.reduceMotion) return const SizedBox.shrink();
    final effective = widget.reduceMotion
        ? const AlwaysStoppedAnimation(1.0)
        : animation;
    final eased = effective.drive(CurveTween(curve: GameMotion.settle));
    return SizeTransition(
      axis: Axis.horizontal,
      sizeFactor: eased,
      child: FadeTransition(
        opacity: eased,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, .16),
            end: Offset.zero,
          ).animate(effective.drive(CurveTween(curve: GameMotion.spring))),
          child: SizedBox(
            width: widget.cardWidth + 10,
            child: Padding(
              padding: const EdgeInsets.only(right: 10, top: 18),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedSlide(
                  offset: widget.selected == card.id
                      ? const Offset(0, -.085)
                      : Offset.zero,
                  duration: Duration(
                    milliseconds: widget.reduceMotion ? 0 : 300,
                  ),
                  curve: GameMotion.spring,
                  child: PlayingCard(
                    key: ValueKey('hand-card-${card.id}'),
                    width: widget.cardWidth,
                    card: card,
                    selected: widget.selected == card.id,
                    playable: !widget.dimUnavailable || widget.isPlayable(card),
                    onTap: removing ? null : () => widget.onTap(card),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.cardWidth * 1.46 + 30,
    child: AnimatedList(
      key: _list,
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 6, 12),
      initialItemCount: _cards.length,
      itemBuilder: (context, index, animation) =>
          _tile(_cards[index], animation),
    ),
  );
}
