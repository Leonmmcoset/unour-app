import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unour/core/models.dart';
import 'package:unour/game/design.dart';
import 'package:unour/game/hand_strip.dart';
import 'package:unour/game/motion.dart';
import 'package:unour/game/table_widgets.dart';

const cards = [
  UnoCard(id: 1, color: 'red', kind: 'number', number: 7),
  UnoCard(id: 2, color: 'blue', kind: 'number', number: 4),
  UnoCard(id: 3, color: 'green', kind: 'reverse'),
];

Finder cardFinder(int id) => find.byKey(ValueKey('hand-card-$id'));

void main() {
  testWidgets('hand cards never overlap or resize when selected', (
    tester,
  ) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: partyTheme(Brightness.light),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Center(
              child: HandStrip(
                cards: cards,
                selected: selected,
                isPlayable: (_) => true,
                onTap: (card) => setState(() => selected = card.id),
              ),
            ),
          ),
        ),
      ),
    );
    final original = [
      for (final card in cards) tester.getRect(cardFinder(card.id)),
    ];
    for (var i = 1; i < original.length; i++) {
      expect(original[i].top, original.first.top);
      expect(original[i].width, original.first.width);
      expect(original[i].left - original[i - 1].right, closeTo(10, .01));
    }
    await tester.tap(cardFinder(2));
    await tester.pumpAndSettle();
    final clip = tester.getRect(
      find.ancestor(of: cardFinder(2), matching: find.byType(ClipRect)).first,
    );
    expect(tester.getRect(cardFinder(2)).top, greaterThanOrEqualTo(clip.top));
    for (var i = 0; i < cards.length; i++) {
      final after = tester.getRect(cardFinder(cards[i].id));
      expect(after.width, original[i].width);
      expect(after.left, original[i].left);
      expect(
        after.top,
        cards[i].id == 2 ? lessThan(original[i].top) : original[i].top,
      );
    }
    expect(tester.takeException(), null);
  });

  for (final reduce in [false, true]) {
    testWidgets(
      'snapshots keep card order and animate only hand changes (reduce: $reduce)',
      (tester) async {
        var hand = List.of(cards);
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            theme: partyTheme(Brightness.light),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return Center(
                    child: HandStrip(
                      cards: hand,
                      selected: null,
                      isPlayable: (_) => true,
                      onTap: (_) {},
                      reduceMotion: reduce,
                    ),
                  );
                },
              ),
            ),
          ),
        );
        final positions = [
          for (final card in cards) tester.getRect(cardFinder(card.id)),
        ];
        update(() => hand = [cards[2], cards[0], cards[1]]);
        await tester.pump();
        for (var i = 0; i < cards.length; i++) {
          expect(tester.getRect(cardFinder(cards[i].id)), positions[i]);
        }
        expect(tester.binding.hasScheduledFrame, isFalse);
        update(
          () => hand = [
            cards[2],
            cards[1],
            const UnoCard(id: 4, color: 'yellow', kind: 'draw_two'),
          ],
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(cardFinder(1), findsNothing);
        expect(
          tester.getRect(cardFinder(2)).left,
          lessThan(tester.getRect(cardFinder(3)).left),
        );
        expect(
          tester.getRect(cardFinder(3)).left,
          lessThan(tester.getRect(cardFinder(4)).left),
        );
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), null);
      },
    );
  }

  testWidgets(
    'selecting a visible card keeps the row still; distant selection scrolls into view',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      int? selected;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Center(
                  child: HandStrip(
                    cards: List.generate(
                      7,
                      (i) => UnoCard(
                        id: i + 1,
                        color: 'red',
                        kind: 'number',
                        number: i,
                      ),
                    ),
                    selected: selected,
                    isPlayable: (_) => true,
                    onTap: (card) => setState(() => selected = card.id),
                  ),
                );
              },
            ),
          ),
        ),
      );
      final before = tester.getRect(cardFinder(3));
      await tester.tap(cardFinder(3));
      await tester.pumpAndSettle();
      expect(tester.getRect(cardFinder(3)).left, before.left);
      update(() => selected = 7);
      await tester.pumpAndSettle();
      final distant = tester.getRect(cardFinder(7));
      expect(distant.left, greaterThanOrEqualTo(0));
      expect(distant.right, lessThanOrEqualTo(320));
      expect(tester.takeException(), null);
    },
  );

  testWidgets(
    'the same top card does not replay and outgoing cards cannot be tapped',
    (tester) async {
      var id = 7;
      late StateSetter update;
      Room snapshot() => Room({
        'id': 'room',
        'round': 1,
        'state': {
          'you': 'me',
          'turn': 'me',
          'active_color': 'red',
          'top_card': {'id': id, 'kind': 'number', 'color': 'red', 'number': 7},
        },
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: partyTheme(Brightness.light),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return TableArena(
                  room: snapshot(),
                  compact: true,
                  minHeight: 220,
                  onPlay: () {},
                );
              },
            ),
          ),
        ),
      );
      update(() {});
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      update(() => id = 8);
      await tester.pump();
      final old = find.byWidgetPredicate(
        (widget) => widget is PlayingCard && widget.card?.id == 7,
      );
      expect(old, findsOneWidget);
      expect(
        find.ancestor(
          of: old,
          matching: find.byWidgetPredicate(
            (widget) => widget is IgnorePointer && widget.ignoring,
          ),
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(old, findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is PlayingCard && widget.card?.id == 8,
        ),
        findsOneWidget,
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets('reduced motion immediately settles entrance and celebration', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: RoundCelebration(child: MotionEntrance(child: Text('结算'))),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('结算'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), null);
  });
}
