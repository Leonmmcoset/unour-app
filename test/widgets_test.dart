import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unour/core/api.dart';
import 'package:unour/core/controller.dart';
import 'package:unour/core/feedback.dart';
import 'package:unour/core/models.dart';
import 'package:unour/core/preferences.dart';
import 'package:unour/game/design.dart';
import 'package:unour/game/room_page.dart';
import 'package:unour/features/account.dart';
import 'package:unour/features/setup.dart';
import 'package:unour/features/home.dart';
import 'package:unour/features/settings.dart';

void main() {
  testWidgets('card has descriptive semantics and selected state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayingCard(
            card: const UnoCard(id: 1, color: 'red', kind: 'reverse'),
            selected: true,
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('红色反转'), findsOneWidget);
    expect(tester.takeException(), null);
  });
  testWidgets('dependent switches and rule constraints update', (tester) async {
    final rule = RuleSelection(
      RuleModule({
        'name': 'draw',
        'required': true,
        'title': '摸牌',
        'options': [
          {'key': 'play', 'type': 'boolean', 'label': '摸后可出', 'default': true},
          {
            'key': 'any',
            'type': 'boolean',
            'label': '出任意牌',
            'default': false,
            'depends_on': [
              {'key': 'play', 'equals': true},
            ],
          },
        ],
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => RuleEditor(
              rule: rule,
              locked: false,
              onChanged: () => setState(() {}),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('摸后可出'));
    await tester.pumpAndSettle();
    final switches = tester
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .toList();
    expect(switches.last.onChanged, null);
  });
  testWidgets('login has party identity and validates password bounds', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'sound': false, 'haptics': false});
    final prefs = GamePreferences(await SharedPreferences.getInstance());
    final app = AppController(
      Api(const FlutterSecureStorage()),
      GameFeedback(prefs),
    )..loading = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appProvider.overrideWith((ref) => app)],
        child: MaterialApp(
          theme: partyTheme(Brightness.light),
          home: const LoginPage(),
        ),
      ),
    );
    final loginButton = find.widgetWithText(FilledButton, '登录');
    await tester.ensureVisible(loginButton);
    await tester.tap(loginButton);
    await tester.pumpAndSettle();
    expect(find.text('Unour'), findsOneWidget);
    expect(find.text('密码需要 8–14 个字符'), findsOneWidget);
    expect(tester.takeException(), null);
  });
  for (final (dark, textScale) in [
    (false, 1.0),
    (true, 1.0),
    (false, 1.6),
    (true, 1.6),
  ]) {
    testWidgets(
      'small portrait table with ten players and many cards (${dark ? 'dark' : 'light'}, text $textScale)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'sound': false,
          'haptics': false,
          'reduce_motion': true,
        });
        final prefs = GamePreferences(await SharedPreferences.getInstance());
        final app = AppController(
          Api(const FlutterSecureStorage()),
          GameFeedback(prefs),
        );
        app.room = Room({
          'id': 'party',
          'revision': 1,
          'role': 'player',
          'state': {
            'phase': 'playing',
            'you': '0',
            'turn': '0',
            'active_color': 'red',
            'top_card': {
              'id': 99,
              'color': 'red',
              'kind': 'number',
              'number': 3,
            },
            'players': List.generate(
              10,
              (i) => {
                'id': '$i',
                'name': '玩家$i',
                'hand_count': i == 0 ? 40 : 7,
                if (i == 0)
                  'hand': List.generate(
                    40,
                    (n) => {
                      'id': n,
                      'color': 'red',
                      'kind': 'number',
                      'number': n % 10,
                    },
                  ),
              },
            ),
            'legal_actions': [
              {'action': 'draw'},
              {'action': 'play', 'card_id': 0},
            ],
          },
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appProvider.overrideWith((ref) => app),
              preferencesProvider.overrideWith((ref) => prefs),
            ],
            child: MaterialApp(
              theme: partyTheme(dark ? Brightness.dark : Brightness.light),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
              home: const RoomPage(),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('我的手牌 · 40 张'), findsOneWidget);
        expect(tester.takeException(), null);
        if (textScale == 1) {
          expect(
            tester.getRect(find.byKey(const ValueKey('play-card'))).bottom,
            lessThanOrEqualTo(640),
          );
        }
        await tester.tap(find.byKey(const ValueKey('hand-card-0')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), null);
        await tester.tap(find.byTooltip('全部手牌'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), null);
      },
    );
  }
  for (final home in [true, false]) {
    testWidgets(
      '${home ? 'home with recent rooms' : 'settings'} supports large text on small phones',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'sound': false,
          'haptics': false,
          'reduce_motion': true,
        });
        final prefs = GamePreferences(await SharedPreferences.getInstance());
        final app =
            AppController(
                Api(const FlutterSecureStorage()),
                GameFeedback(prefs),
              )
              ..account = const Account(id: 'me', username: '玩家名字比较长')
              ..recent = [
                const RoomSession(
                  id: 'ROOM1234',
                  playerId: 'me',
                  token: 'test',
                ),
              ];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appProvider.overrideWith((ref) => app),
              preferencesProvider.overrideWith((ref) => prefs),
            ],
            child: MaterialApp(
              theme: partyTheme(Brightness.light),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: const TextScaler.linear(1.6),
                ),
                child: child!,
              ),
              home: home ? const HomePage() : const SettingsPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), null);
      },
    );
  }
}
