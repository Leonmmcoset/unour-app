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
import 'package:unour/features/history.dart';
import 'package:unour/features/match_review.dart';
import 'package:unour/game/design.dart';
import 'package:unour/game/room_page.dart';
import 'package:unour/game/round_summary.dart';

import 'match_history_test.dart' show localSession, observedRoom;

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'review scrubs public frames and marks gaps on small screens (dark: $dark)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'sound': false,
          'haptics': false,
        });
        final prefs = GamePreferences(await SharedPreferences.getInstance());
        final app = AppController(
          Api(const FlutterSecureStorage()),
          GameFeedback(prefs),
        )..account = const Account(id: 'account-a', username: '小林');
        app.history.selectAccount('account-a');
        app.history.observe(observedRoom(), localSession);
        app.history.observe(
          observedRoom(version: 2, count: 2, color: 'blue'),
          localSession,
        );
        app.history.interrupt();
        app.history.observe(
          observedRoom(
            version: 8,
            phase: 'finished',
            winner: 'friend',
            count: 1,
          ),
          localSession,
        );
        final record = app.history.records.single;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appProvider.overrideWith((ref) => app)],
            child: MaterialApp(
              theme: partyTheme(dark ? Brightness.dark : Brightness.light),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: const TextScaler.linear(1.6),
                ),
                child: child!,
              ),
              home: MatchReviewPage(recordId: record.id),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('记录 3 / 3'), findsOneWidget);
        expect(find.text('此前有未记录的变化'), findsOneWidget);
        await tester.ensureVisible(find.byTooltip('上一条牌况'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('上一条牌况'));
        await tester.pumpAndSettle();
        expect(find.text('记录 2 / 3'), findsOneWidget);
        expect(find.text('蓝色5'), findsWidgets);
        final slider = tester.widget<Slider>(find.byType(Slider));
        slider.onChanged!(0);
        await tester.pumpAndSettle();
        expect(find.text('记录 1 / 3'), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) => widget is IconButton && widget.tooltip == '上一条牌况',
                ),
              )
              .onPressed,
          isNull,
        );
        await tester.scrollUntilVisible(find.text('记录时间线'), 220);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('review never exposes another account after a switch', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'sound': false, 'haptics': false});
    final prefs = GamePreferences(await SharedPreferences.getInstance());
    final app = AppController(
      Api(const FlutterSecureStorage()),
      GameFeedback(prefs),
    )..account = const Account(id: 'account-a', username: '小林');
    app.history.selectAccount('account-a');
    app.history.observe(observedRoom(), localSession);
    final id = app.history.records.single.id;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appProvider.overrideWith((ref) => app)],
        child: MaterialApp(home: MatchReviewPage(recordId: id)),
      ),
    );
    await tester.pumpAndSettle();
    app.account = const Account(id: 'account-b', username: '另一个账户');
    app.changed();
    await tester.pumpAndSettle();
    expect(find.text('这条本机记录已清除或不属于当前账户。'), findsOneWidget);
    expect(find.textContaining('牌桌 LOCAL'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final reduce in [true, false]) {
    testWidgets(
      'settlement highlights fit and polling does not replay animations (reduce: $reduce)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'sound': false,
          'haptics': false,
          'reduce_motion': reduce,
        });
        final prefs = GamePreferences(await SharedPreferences.getInstance());
        final app = AppController(
          Api(const FlutterSecureStorage()),
          GameFeedback(prefs),
        )..account = const Account(id: 'account-a', username: '小林');
        app.history.selectAccount('account-a');
        app.history.observe(observedRoom(count: 2), localSession);
        app.history.observe(
          observedRoom(version: 2, count: 1, declared: 12, pending: 8),
          localSession,
        );
        app.room = observedRoom(
          version: 3,
          phase: 'finished',
          winner: 'me',
          count: 0,
          declared: 12,
        );
        app.history.observe(app.room!, localSession);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appProvider.overrideWith((ref) => app),
              preferencesProvider.overrideWith((ref) => prefs),
            ],
            child: MaterialApp(
              theme: partyTheme(Brightness.dark),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!,
              ),
              home: const RoomPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SettlementEmblem), findsOneWidget);
        expect(tester.binding.transientCallbackCount, 0);
        app.changed();
        await tester.pump(const Duration(milliseconds: 30));
        expect(tester.binding.transientCallbackCount, 0);
        await tester.scrollUntilVisible(find.text('UNO 喊到了'), 150);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  for (final populated in [false, true]) {
    testWidgets(
      'local history supports small screens and large text (records: $populated)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'sound': false,
          'haptics': false,
        });
        final prefs = GamePreferences(await SharedPreferences.getInstance());
        final app = AppController(
          Api(const FlutterSecureStorage()),
          GameFeedback(prefs),
        )..account = const Account(id: 'account-a', username: '小林');
        app.history.selectAccount('account-a');
        if (populated) {
          app.history.observe(observedRoom(), localSession);
          app.history.observe(
            observedRoom(version: 2, phase: 'finished', winner: 'me', count: 0),
            localSession,
          );
        }
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appProvider.overrideWith((ref) => app)],
            child: MaterialApp(
              theme: partyTheme(Brightness.light),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: const TextScaler.linear(1.6),
                ),
                child: child!,
              ),
              home: const HistoryPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(populated ? '100%' : '—'), findsOneWidget);
        if (populated) {
          await tester.scrollUntilVisible(find.byType(MatchResultTile), 220);
          expect(find.text('获胜'), findsWidgets);
          expect(find.textContaining('胜者：小林'), findsOneWidget);
        } else {
          await tester.scrollUntilVisible(find.text('还没有本机战绩'), 220);
          expect(find.text('还没有本机战绩'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
