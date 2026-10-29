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
import 'package:unour/game/design.dart';
import 'package:unour/game/room_page.dart';
import 'package:unour/game/round_summary.dart';

import 'match_history_test.dart' show localSession, observedRoom;

void main() {
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
