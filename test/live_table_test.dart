import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unour/core/api.dart';
import 'package:unour/core/controller.dart';
import 'package:unour/core/feedback.dart';
import 'package:unour/core/live_table.dart';
import 'package:unour/core/models.dart';
import 'package:unour/core/preferences.dart';
import 'package:unour/main.dart' show UnourApp;

const channel = MethodChannel('chat.csac.unour/live_table');

Room room({
  String phase = 'playing',
  bool spectator = false,
  int version = 1,
}) => Room({
  'id': 'LIVE',
  'round': 2,
  'revision': version,
  'role': spectator ? 'spectator' : 'player',
  'state': {
    'version': version,
    'phase': phase,
    'you': 'me',
    'turn': 'me',
    'active_color': 'blue',
    'direction': -1,
    'pending_draw': 4,
    'top_card': {'id': 1, 'color': 'wild', 'kind': 'wild_draw_four'},
    'players': [
      {
        'id': 'me',
        'name': '本人',
        'hand_count': 3,
        'hand': [
          {'id': 999, 'color': 'red', 'kind': 'number', 'number': 9},
        ],
      },
      {'id': 'a', 'name': '小林', 'hand_count': 1},
    ],
  },
});

class RecordingApi extends Api {
  RecordingApi() : super(const FlutterSecureStorage());
  final registrations = <Json>[];
  int reads = 0;
  @override
  Future<Json> get(String path, {String? token}) async {
    reads++;
    return {};
  }

  @override
  Future<Json> post(String path, [Json data = const {}, String? token]) async {
    registrations.add({'path': path, 'data': data, 'token': token});
    return {};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;
  late GamePreferences prefs;
  late AppController app;
  late RecordingApi api;
  var permission = true;
  var widgetOwnsControllers = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'sound': false, 'haptics': false});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = GamePreferences(await SharedPreferences.getInstance());
    api = RecordingApi()..accountId = 'account';
    app = AppController(api, GameFeedback(prefs))
      ..account = const Account(id: 'account', username: '本人')
      ..session = const RoomSession(
        id: 'LIVE',
        playerId: 'me',
        token: 'room-secret',
      )
      ..room = room()
      ..roomUpdatedAt = DateTime.now();
    calls = [];
    permission = true;
    widgetOwnsControllers = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'status' => {
              'supported': true,
              'allowed': permission,
              'realtime': true,
              'platform': 'android',
            },
            'requestPermission' => permission,
            'foreground' => {'cookies': []},
            _ => null,
          };
        });
  });

  tearDown(() {
    if (!widgetOwnsControllers) {
      app.dispose();
      prefs.dispose();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'system content contains public table state and never hand faces or tokens',
    () {
      final state = liveTableSnapshot(
        room(),
        DateTime.fromMillisecondsSinceEpoch(100000),
      );
      expect(state['topCard'], '万能加四');
      expect(state['activeColor'], 'blue');
      expect(state['isYourTurn'], true);
      expect(state['myCount'], 3);
      expect(state['pendingDraw'], 4);
      expect(state['direction'], -1);
      expect(state['players'], contains('小林 1'));
      expect(state['updatedAt'], 100);
      final encoded = jsonEncode(state);
      expect(encoded, isNot(contains('hand')));
      expect(encoded, isNot(contains('999')));
      expect(encoded, isNot(contains('secret')));
      expect(
        liveTableSnapshot(room(spectator: true), DateTime.now())['isYourTurn'],
        false,
      );
      expect(utf8.encode(encoded).length, lessThan(4096));
    },
  );

  testWidgets(
    'opt in publishes once, follows table changes and ends with the round',
    (tester) async {
      final live = LiveTableController(app, prefs);
      addTearDown(live.dispose);
      await live.initialize();
      await tester.pump();
      expect(calls.map((call) => call.method), ['status', 'stop']);
      await live.setEnabled(true);
      await tester.pump();
      final first =
          calls.where((call) => call.method == 'sync').single.arguments as Map;
      expect((first['connection'] as Map)['token'], 'room-secret');
      expect(jsonEncode(first['snapshot']), isNot(contains('room-secret')));
      expect(first['foreground'], true);
      app.changed();
      await tester.pump();
      expect(calls.where((call) => call.method == 'sync').length, 1);
      app.room = room(version: 2);
      app.changed();
      await tester.pump();
      expect(calls.where((call) => call.method == 'sync').length, 2);
      app.room = room(phase: 'finished', version: 3);
      app.changed();
      await tester.pump();
      expect(calls.last.method, 'stop');
      expect(api.reads, 0);
      expect(api.registrations, isEmpty);
    },
  );

  testWidgets('permission denial never enables tracking or sends credentials', (
    tester,
  ) async {
    permission = false;
    final live = LiveTableController(app, prefs);
    addTearDown(live.dispose);
    await live.initialize();
    await live.setEnabled(true);
    await tester.pump();
    expect(prefs.liveTable, false);
    expect(live.message, isNotEmpty);
    expect(calls.where((call) => call.method == 'sync'), isEmpty);
  });

  testWidgets('background handoff stops on logout and never polls from Dart', (
    tester,
  ) async {
    final live = LiveTableController(app, prefs);
    addTearDown(live.dispose);
    await live.initialize();
    await live.setEnabled(true);
    await tester.pump();
    await live.setForeground(false);
    await tester.pump();
    expect((calls.last.arguments as Map)['foreground'], false);
    app.online = false;
    app.changed();
    await tester.pump();
    expect(
      ((calls.last.arguments as Map)['snapshot'] as Map)['connected'],
      false,
    );
    app.closeTable();
    await tester.pump();
    expect(calls.last.method, 'stop');
    expect(api.reads, 0);
  });

  testWidgets('iOS stays explicitly in snapshot mode without a push endpoint', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'status' => {
              'supported': true,
              'allowed': true,
              'realtime': false,
              'platform': 'ios',
            },
            'requestPermission' => true,
            _ => null,
          };
        });
    final live = LiveTableController(app, prefs);
    addTearDown(live.dispose);
    await live.initialize();
    await live.setEnabled(true);
    await tester.pump();
    expect(live.realtime, false);
    expect(live.description, contains('最近同步'));
    final sent =
        calls.where((call) => call.method == 'sync').single.arguments as Map;
    expect(sent['pushEnabled'], false);
    expect(api.registrations, isEmpty);
  });

  testWidgets('unsupported systems preserve normal gameplay', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw MissingPluginException(),
        );
    final live = LiveTableController(app, prefs);
    addTearDown(live.dispose);
    await live.initialize();
    await live.setForeground(false);
    app.changed();
    await tester.pump();
    expect(live.supported, false);
    expect(app.room?.id, 'LIVE');
    expect(api.reads, 0);
  });

  Future<void> tokenEvent(WidgetTester tester, {int round = 2}) async {
    final finished = Completer<void>();
    tester.binding.channelBuffers.push(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('pushToken', {
          'roomId': 'LIVE',
          'round': round,
          'activityId': 'activity',
          'pushToken': 'abc123',
        }),
      ),
      (_) => finished.complete(),
    );
    await finished.future;
  }

  testWidgets(
    'push registration uses the room credential and rejects old rounds',
    (tester) async {
      final live = LiveTableController(
        app,
        prefs,
        registrationPath: 'rooms/{roomId}/live-activities',
      );
      addTearDown(live.dispose);
      await live.initialize();
      await live.setEnabled(true);
      await tester.pump();
      await tokenEvent(tester, round: 1);
      expect(api.registrations, isEmpty);
      await tokenEvent(tester);
      expect(api.registrations.single['path'], 'rooms/LIVE/live-activities');
      expect(api.registrations.single['token'], 'room-secret');
      expect(object(api.registrations.single['data'])['push_token'], 'abc123');
      await live.setEnabled(false);
      await tokenEvent(tester);
      expect(api.registrations.length, 1);
    },
  );

  testWidgets(
    'a push registration path cannot send credentials to another host',
    (tester) async {
      final live = LiveTableController(
        app,
        prefs,
        registrationPath: 'https://another.invalid/register',
      );
      addTearDown(live.dispose);
      await live.initialize();
      await live.setEnabled(true);
      await tester.pump();
      await tokenEvent(tester);
      expect(api.registrations, isEmpty);
    },
  );

  testWidgets(
    'returning from native tracking preserves rotated session cookies',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'status') {
              return {
                'supported': true,
                'allowed': true,
                'platform': 'android',
              };
            }
            if (call.method == 'foreground') {
              return {
                'cookies': [
                  'account_session=rotated; Max-Age=3600; Secure; HttpOnly',
                ],
              };
            }
            return null;
          });
      final live = LiveTableController(app, prefs);
      addTearDown(live.dispose);
      await live.initialize();
      await live.setForeground(true);
      expect(
        api.liveTableConnection(app.session!)['cookie'],
        'account_session=rotated',
      );
      expect(
        await api.storage.read(key: 'account_cookies'),
        contains('rotated'),
      );
    },
  );

  testWidgets(
    'a delayed resume cannot restart foreground polling after another pause',
    (tester) async {
      widgetOwnsControllers = true;
      final resume = Completer<Json>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'status') {
              return {
                'supported': true,
                'allowed': true,
                'platform': 'android',
              };
            }
            if (call.method == 'foreground' &&
                object(call.arguments)['value'] == true) {
              return resume.future;
            }
            return {};
          });
      app.loading = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appProvider.overrideWith((ref) => app),
            preferencesProvider.overrideWith((ref) => prefs),
          ],
          child: UnourApp(controller: app),
        ),
      );
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      resume.complete({'cookies': []});
      await tester.pumpAndSettle();
      expect(api.reads, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
