import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unour/core/api.dart';
import 'package:unour/core/controller.dart';
import 'package:unour/core/feedback.dart';
import 'package:unour/core/models.dart';
import 'package:unour/core/preferences.dart';
import 'package:unour/game/design.dart';
import 'package:unour/game/hand_strip.dart';
import 'package:unour/game/room_page.dart';
import 'package:unour/game/table_widgets.dart';

class LayoutController extends AppController {
  LayoutController(GamePreferences prefs)
    : super(Api(const FlutterSecureStorage()), GameFeedback(prefs));
  bool showUno = false;
  final commands = <String>[];
  Room? actionResponse;

  @override
  Future<bool> action(String action, [Json payload = const {}]) async {
    commands.add(action);
    if (actionResponse != null) {
      room = actionResponse;
      actionResponse = null;
      changed();
    }
    return true;
  }

  @override
  bool get unoAvailable => showUno;
  @override
  double get unoProgress => .5;
}

Room tableRoom({int players = 4, bool spectator = false}) => Room({
  'id': 'LAYOUT',
  'round': 1,
  'role': spectator ? 'spectator' : 'player',
  'state': {
    'phase': 'playing',
    'you': 'me',
    'turn': 'p1',
    'active_color': 'red',
    'draw_pile_count': 60,
    'top_card': {'id': 99, 'color': 'red', 'kind': 'number', 'number': 5},
    'players': [
      if (!spectator)
        {
          'id': 'me',
          'name': '本人',
          'hand_count': 7,
          'hand': [
            for (var i = 0; i < 7; i++)
              {
                'id': i,
                'color': [
                  'blue',
                  'red',
                  'yellow',
                  'wild',
                  'green',
                  'red',
                  'blue',
                ][i],
                'kind': i == 3 ? 'wild' : 'number',
                'number': i,
              },
          ],
        },
      for (var i = 1; i < players; i++)
        {'id': 'p$i', 'name': '玩家$i', 'hand_count': 7},
    ],
    'legal_actions': [
      {'action': 'draw'},
      {'action': 'play', 'card_id': 1},
    ],
  },
});

Future<LayoutController> mountTable(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  bool spectator = false,
  int players = 4,
  bool reduceMotion = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({
    'sound': false,
    'haptics': false,
    'reduce_motion': reduceMotion,
  });
  final prefs = GamePreferences(await SharedPreferences.getInstance());
  final app = LayoutController(prefs)
    ..room = tableRoom(players: players, spectator: spectator);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appProvider.overrideWith((ref) => app),
        preferencesProvider.overrideWith((ref) => prefs),
      ],
      child: MaterialApp(
        theme: partyTheme(Brightness.light),
        home: const RoomPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

void main() {
  for (final size in [const Size(320, 640), const Size(390, 844)]) {
    testWidgets('deck and current card match in size and alignment at $size', (
      tester,
    ) async {
      await mountTable(tester, size: size);
      final arena = find.byType(TableArena);
      final deck = tester.getRect(
        find.descendant(
          of: arena,
          matching: find.byWidgetPredicate(
            (widget) => widget is PlayingCard && widget.card == null,
          ),
        ),
      );
      final current = tester.getRect(
        find.descendant(
          of: arena,
          matching: find.byWidgetPredicate(
            (widget) => widget is PlayingCard && widget.card?.id == 99,
          ),
        ),
      );
      expect(deck.size, current.size);
      expect(deck.top, current.top);
      expect(deck.bottom, current.bottom);
      final deckLabel = tester.getRect(find.text('牌堆 · 60'));
      final currentLabel = tester.getRect(find.text('当前牌'));
      expect(deckLabel.top, currentLabel.top);
      expect(deckLabel.center.dx, closeTo(deck.center.dx, .01));
      expect(currentLabel.center.dx, closeTo(current.center.dx, .01));
      expect(tester.takeException(), null);
    });

    for (final reduce in [false, true]) {
      testWidgets(
        'draw changes to pass in the same slot without adding scroll at $size (reduce: $reduce)',
        (tester) async {
          final app = await mountTable(
            tester,
            size: size,
            reduceMotion: reduce,
          );
          final before = app.room!;
          app.room = Room({
            ...before.raw,
            'state': {...before.state, 'turn': 'me'},
          });
          app.changed();
          await tester.pumpAndSettle();
          final secondary = find.byKey(const ValueKey('secondary-action'));
          final play = find.byKey(const ValueKey('play-card'));
          final slotBefore = tester.getRect(secondary);
          final playBefore = tester.getRect(play);
          final handBefore = tester.getRect(find.byType(HandStrip));
          final scroll = tester.state<ScrollableState>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            ),
          );
          expect(scroll.position.maxScrollExtent, 0);
          final players = before.players
              .map(
                (player) => {
                  'id': player.id,
                  'name': player.name,
                  'hand_count': player.handCount + (player.id == 'me' ? 1 : 0),
                  if (player.id == 'me')
                    'hand': [
                      ...objects(before.state['players']).first['hand'] as List,
                      {'id': 7, 'color': 'red', 'kind': 'number', 'number': 8},
                    ],
                },
              )
              .toList();
          app.actionResponse = Room({
            ...before.raw,
            'state': {
              ...before.state,
              'turn': 'me',
              'players': players,
              'legal_actions': [
                {'action': 'pass'},
                {'action': 'play', 'card_id': 7},
              ],
            },
          });
          await tester.tap(secondary);
          await tester.pump();
          expect(app.commands, ['draw']);
          expect(find.text('摸一张'), findsNothing);
          expect(find.text('过牌').hitTestable(), findsOneWidget);
          expect(tester.getRect(secondary), slotBefore);
          expect(tester.getRect(play), playBefore);
          expect(tester.getRect(find.byType(HandStrip)), handBefore);
          expect(scroll.position.maxScrollExtent, 0);
          await tester.pumpAndSettle();
          expect(tester.getRect(secondary), slotBefore);
          expect(tester.getRect(play), playBefore);
          expect(scroll.position.maxScrollExtent, 0);
          await tester.tap(secondary);
          await tester.pumpAndSettle();
          expect(app.commands, ['draw', 'pass']);
          app.room = Room({
            ...before.raw,
            'state': {...before.state, 'turn': 'me'},
          });
          app.changed();
          await tester.pumpAndSettle();
          expect(find.text('过牌'), findsNothing);
          expect(find.text('摸一张'), findsOneWidget);
          expect(tester.getRect(secondary), slotBefore);
          expect(scroll.position.maxScrollExtent, 0);
          expect(tester.takeException(), null);
        },
      );
    }
  }

  testWidgets(
    'players, piles, turn and hand form one vertical table with seven visible cards',
    (tester) async {
      await mountTable(tester);
      final players = tester.getRect(find.byKey(const ValueKey('opponents')));
      final arena = tester.getRect(find.byKey(const ValueKey('table-arena')));
      final turn = tester.getRect(find.byKey(const ValueKey('turn-banner')));
      final hand = tester.getRect(find.byType(HandStrip));
      expect(players.bottom, lessThanOrEqualTo(arena.top));
      expect(arena.bottom, lessThanOrEqualTo(turn.top));
      expect(turn.bottom, lessThan(hand.top));
      for (var i = 0; i < 7; i++) {
        final card = tester.getRect(find.byKey(ValueKey('hand-card-$i')));
        expect(card.left, greaterThanOrEqualTo(0));
        expect(card.right, lessThanOrEqualTo(390));
      }
      for (var i = 1; i < 4; i++) {
        expect(find.text('玩家$i').hitTestable(), findsOneWidget);
      }
      expect(
        tester.getRect(find.byKey(const ValueKey('play-card'))).bottom,
        lessThanOrEqualTo(844),
      );
      expect(tester.takeException(), null);
    },
  );

  testWidgets(
    'sorting in the room keeps selection and the matching full hand order',
    (tester) async {
      await mountTable(tester);
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('hand-card-1'))) +
            const Offset(12, 24),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sort-hand')));
      await tester.pumpAndSettle();
      final ordered = sortedHand(tableRoom().me!.hand);
      final cardWidgets = tester
          .widgetList<PlayingCard>(find.byType(PlayingCard))
          .where((card) => card.selected)
          .toList();
      expect(cardWidgets.single.card?.id, 1);
      for (var i = 1; i < ordered.length; i++) {
        expect(
          tester
              .getRect(find.byKey(ValueKey('hand-card-${ordered[i].id}')))
              .left,
          greaterThan(
            tester
                .getRect(find.byKey(ValueKey('hand-card-${ordered[i - 1].id}')))
                .left,
          ),
        );
      }
      await tester.tap(find.byTooltip('全部手牌'));
      await tester.pumpAndSettle();
      final gridCards = tester
          .widgetList<PlayingCard>(
            find.descendant(
              of: find.byType(SliverGrid),
              matching: find.byType(PlayingCard),
            ),
          )
          .toList();
      expect(
        gridCards.map((card) => card.card!.id),
        ordered.map((card) => card.id),
      );
      expect(tester.takeException(), null);
    },
  );

  testWidgets(
    'UNO call stays on the table without shifting the hand or bottom actions',
    (tester) async {
      final app = await mountTable(tester, size: const Size(320, 640));
      final handBefore = tester.getRect(find.byType(HandStrip));
      final actionsBefore = tester.getRect(
        find.byKey(const ValueKey('play-card')),
      );
      app.showUno = true;
      app.changed();
      await tester.pumpAndSettle();
      expect(find.text('UNO！').hitTestable(), findsOneWidget);
      expect(tester.getRect(find.byType(HandStrip)), handBefore);
      expect(
        tester.getRect(find.byKey(const ValueKey('play-card'))),
        actionsBefore,
      );
      expect(tester.takeException(), null);
    },
  );

  testWidgets(
    'a spectator sees all players and reservation without any hand controls',
    (tester) async {
      await mountTable(tester, spectator: true);
      expect(find.byType(HandStrip), findsNothing);
      expect(find.byKey(const ValueKey('play-card')), findsNothing);
      expect(find.text('预约下一局'), findsOneWidget);
      expect(tester.takeException(), null);
    },
  );
}
