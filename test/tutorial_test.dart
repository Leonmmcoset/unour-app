import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unour/core/api.dart';
import 'package:unour/core/controller.dart';
import 'package:unour/core/feedback.dart';
import 'package:unour/core/models.dart';
import 'package:unour/core/preferences.dart';
import 'package:unour/features/tutorial.dart';
import 'package:unour/game/design.dart';
import 'package:unour/main.dart';

const _channel = MethodChannel('chat.csac.unour/live_table');

class _NoNetworkApi extends Api {
  int requests = 0;
  _NoNetworkApi() : super(const FlutterSecureStorage());

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    dynamic data,
    String? token,
    String? contentType,
  }) async {
    requests++;
    throw StateError('Tutorials must not call the game API');
  }
}

class _Fixture {
  final GamePreferences prefs;
  final AppController app;
  final _NoNetworkApi api;
  _Fixture(this.prefs, this.app, this.api);
}

Future<_Fixture> _mount(
  WidgetTester tester, {
  bool root = false,
  bool loggedIn = true,
  bool experienced = false,
  bool reduce = true,
  bool dark = false,
  double textScale = 1,
}) async {
  SharedPreferences.setMockInitialValues({
    'sound': false,
    'haptics': false,
    'reduce_motion': reduce,
  });
  final prefs = GamePreferences(await SharedPreferences.getInstance());
  final api = _NoNetworkApi();
  final app = AppController(api, GameFeedback(prefs))
    ..loading = false
    ..account = loggedIn ? const Account(id: 'me', username: '我') : null;
  if (experienced) {
    app.recent = [
      const RoomSession(id: 'existing', playerId: 'me', token: 'unused'),
    ];
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appProvider.overrideWith((ref) => app),
        preferencesProvider.overrideWith((ref) => prefs),
      ],
      child: root
          ? UnourApp(controller: app)
          : MaterialApp(
              theme: partyTheme(dark ? Brightness.dark : Brightness.light),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: reduce,
                  textScaler: TextScaler.linear(textScale),
                ),
                child: child!,
              ),
              home: const TutorialPage(),
            ),
    ),
  );
  await tester.pumpAndSettle();
  return _Fixture(prefs, app, api);
}

Future<void> _step(WidgetTester tester, int index) async {
  final page = tester.widget<PageView>(find.byType(PageView));
  page.controller!.jumpToPage(index);
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _channel,
          (call) async => {'supported': false, 'allowed': false},
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  testWidgets(
    'logged out players can learn and skip back without game API calls',
    (tester) async {
      final fixture = await _mount(tester, root: true, loggedIn: false);
      await _tapVisible(tester, find.text('第一次玩？看看怎么玩'));
      expect(find.byType(TutorialPage), findsOneWidget);
      expect(find.text('先认识牌桌'), findsOneWidget);
      await tester.tap(find.text('跳过'));
      await tester.pumpAndSettle();
      expect(find.byType(TutorialPage), findsNothing);
      expect(fixture.prefs.tutorialDismissed, true);
      expect(GamePreferences(fixture.prefs.store).tutorialDismissed, true);
      expect(fixture.app.account, isNull);
      expect(fixture.api.requests, 0);
      expect(fixture.app.history.records, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'home invitation can be dismissed and settings can reopen the guide',
    (tester) async {
      final fixture = await _mount(tester, root: true);
      expect(find.text('第一次玩？'), findsOneWidget);
      await _tapVisible(tester, find.text('我会玩了'));
      expect(find.text('第一次玩？'), findsNothing);
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('新手引导'));
      expect(find.byType(TutorialPage), findsOneWidget);
      await _step(tester, 4);
      await tester.tap(find.text('完成引导'));
      await tester.pumpAndSettle();
      expect(find.byType(TutorialPage), findsNothing);
      expect(find.text('设置'), findsOneWidget);
      expect(fixture.prefs.tutorialDismissed, true);
      expect(fixture.api.requests, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'existing players keep their normal home without a tutorial invitation',
    (tester) async {
      final fixture = await _mount(tester, root: true, experienced: true);
      expect(find.text('第一次玩？'), findsNothing);
      expect(find.text('和朋友玩'), findsOneWidget);
      expect(fixture.prefs.tutorialDismissed, false);
      expect(fixture.app.recent.single.id, 'existing');
      expect(fixture.api.requests, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'play example selects first and confirms only on a deliberate action',
    (tester) async {
      final fixture = await _mount(tester);
      await _step(tester, 1);
      final button = find.byKey(const ValueKey('tutorial-play'));
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      final red = find.byKey(const ValueKey('tutorial-hand-108'));
      await _tapVisible(tester, red);
      expect(tester.widget<PlayingCard>(red).selected, true);
      expect(
        find.byWidgetPredicate((w) => w is PlayingCard && w.card?.id == 105),
        findsOneWidget,
      );
      await _tapVisible(tester, button);
      expect(find.text('红色 8 接在红色 5 上，颜色相同'), findsOneWidget);
      expect(red, findsNothing);
      await _tapVisible(tester, find.text('再试一次'));
      await _tapVisible(tester, red);
      await _tapVisible(tester, red);
      expect(find.text('红色 8 接在红色 5 上，颜色相同'), findsOneWidget);
      expect(fixture.api.requests, 0);
      expect(fixture.app.history.records, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'draw and pass use the same button slot in the teaching example',
    (tester) async {
      await _mount(tester);
      await _step(tester, 2);
      final action = find.byKey(const ValueKey('tutorial-draw-pass'));
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      final before = tester.getRect(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('过牌'), findsOneWidget);
      expect(tester.getRect(action), before);
      expect(find.byKey(const ValueKey('tutorial-hand-207')), findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('回合结束，轮到下一位'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'wild color selection changes the effective color and keeps the wild face',
    (tester) async {
      await _mount(tester);
      await _step(tester, 3);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('tutorial-color-blue')),
      );
      expect(find.text('接下来按蓝色接牌，万能牌面保持不变'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is PlayingCard &&
              w.card?.color == 'wild' &&
              w.card?.kind == 'wild',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'UNO teaching has no penalty timer or effect on the current room',
    (tester) async {
      final fixture = await _mount(tester);
      final room = Room({
        'id': 'real-table',
        'state': {'phase': 'playing'},
      });
      fixture.app.room = room;
      await _step(tester, 4);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('点一下喊 UNO，这里没有倒计时'), findsOneWidget);
      await _tapVisible(tester, find.byKey(const ValueKey('tutorial-uno')));
      expect(find.text('UNO！喊到了'), findsOneWidget);
      expect(identical(fixture.app.room, room), true);
      expect(fixture.api.requests, 0);
      expect(fixture.app.history.records, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final (dark, reduce) in [(false, true), (true, false)]) {
    testWidgets(
      'all lessons support small phones and large text (dark: $dark, reduce: $reduce)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await _mount(tester, dark: dark, reduce: reduce, textScale: 1.6);
        for (var i = 0; i < 5; i++) {
          if (i > 0) {
            await tester.tap(find.text('下一步'));
            await tester.pumpAndSettle();
          }
          expect(find.text('${i + 1} / 5'), findsOneWidget);
          final next = find.text(i == 4 ? '完成引导' : '下一步');
          expect(tester.getRect(next).bottom, lessThanOrEqualTo(640));
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.takeException(), isNull);
        }
        await tester.tap(find.byTooltip('上一步'));
        await tester.pumpAndSettle();
        expect(find.text('4 / 5'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
