import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unour/core/api.dart';
import 'package:unour/core/controller.dart';
import 'package:unour/core/feedback.dart';
import 'package:unour/core/models.dart';
import 'package:unour/core/preferences.dart';

// In-memory transport fixtures only; no HTTP server or client game engine.
class FixtureApi extends Api {
  FixtureApi() : super(const FlutterSecureStorage());
  Json snapshot = roomData();
  ApiFailure? postError, readError, penaltyErrorOnce;
  int commands = 0, declarations = 0, penalties = 0, reads = 0;
  Json? lastUnoPayload, lastCommandPayload;
  @override
  Future<Json> get(String path, {String? token}) async {
    reads++;
    if (readError != null) throw readError!;
    return snapshot;
  }

  @override
  Future<Json> post(String path, [Json data = const {}, String? token]) async {
    if (path.endsWith('/players')) {
      return {'player_id': 'a', 'token': 'secret', 'room': snapshot};
    }
    if (path.endsWith('/uno')) {
      declarations++;
      lastUnoPayload = data;
      snapshot = roomData(version: 2, declared: 9);
      return {'room': snapshot};
    }
    if (path.endsWith('/uno-penalty')) {
      penalties++;
      lastUnoPayload = data;
      if (penaltyErrorOnce != null) {
        final error = penaltyErrorOnce!;
        penaltyErrorOnce = null;
        throw error;
      }
      snapshot = roomData(version: 2, penalized: 9);
      return {'room': snapshot};
    }
    commands++;
    lastCommandPayload = data;
    if (postError != null) throw postError!;
    return {'room': snapshot};
  }
}

Json roomData({
  int version = 1,
  bool uno = false,
  int declared = 0,
  int penalized = 0,
}) => {
  'id': 'table',
  'revision': version,
  'role': 'player',
  'state': {
    'version': version,
    'phase': 'playing',
    'you': 'a',
    'turn': 'a',
    'players': [
      {
        'id': 'a',
        'name': 'Alice',
        'hand_count': 1,
        'hand': [],
        if (uno) 'uno': {'id': 9, 'deadline': '2099-01-01T00:00:00Z'},
        'uno_declared': declared,
        'uno_penalized': penalized,
      },
    ],
  },
};
Future<AppController> create(FixtureApi api) async {
  SharedPreferences.setMockInitialValues({'sound': false, 'haptics': false});
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = GamePreferences(await SharedPreferences.getInstance());
  return AppController(api, GameFeedback(prefs))
    ..account = const Account(id: 'account-a', username: 'Alice');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'accepted snapshots save one local result through the controller',
    () async {
      final api = FixtureApi();
      final app = await create(api);
      await app.enter(id: 'table');
      expect(app.history.unsettled, 1);
      final result = roomData(version: 2);
      api.snapshot = {
        ...result,
        'state': {
          ...object(result['state']),
          'phase': 'finished',
          'winner': 'a',
        },
      };
      await app.refresh();
      await app.refresh();
      expect(app.history.completed, 1);
      expect(app.history.wins, 1);
      expect(app.history.records.single.frames, hasLength(2));
      app.closeTable();
      app.dispose();
    },
  );
  test(
    'uncertain command is not replayed and authoritative state is fetched',
    () async {
      final api = FixtureApi()
        ..postError = const ApiFailure('network', 'timeout')
        ..snapshot = roomData(version: 2);
      final app = await create(api);
      app.session = const RoomSession(
        id: 'table',
        playerId: 'a',
        token: 'secret',
      );
      app.room = Room(roomData());
      expect(await app.action('draw'), false);
      expect(api.commands, 1);
      expect(api.lastCommandPayload?['expected_version'], 1);
      expect(api.reads, 1);
      expect(app.room!.version, 2);
      app.dispose();
    },
  );
  test(
    'version conflict refreshes state and requests a deliberate new action',
    () async {
      final api = FixtureApi()
        ..postError = const ApiFailure('version_conflict', 'old', 409)
        ..snapshot = roomData(version: 3);
      final app = await create(api);
      app.session = const RoomSession(
        id: 'table',
        playerId: 'a',
        token: 'secret',
      );
      app.room = Room(roomData());
      await app.action('play', {'card_id': 7});
      expect(api.commands, 1);
      expect(api.lastCommandPayload?['expected_version'], 1);
      expect(app.room!.version, 3);
      expect(app.error, isNotNull);
      app.dispose();
    },
  );
  testWidgets('initial snapshot does not replay historical UNO notices', (
    tester,
  ) async {
    final api = FixtureApi()..snapshot = roomData(declared: 7);
    final app = await create(api);
    await app.enter(id: 'table');
    expect(app.notice, null);
    app.closeTable();
    app.dispose();
  });
  testWidgets(
    'UNO declaration uses window ID and disables duplicate submission',
    (tester) async {
      final api = FixtureApi()..snapshot = roomData(uno: true);
      final app = await create(api);
      await app.enter(id: 'table');
      expect(app.unoAvailable, true);
      await app.declareUno();
      await app.declareUno();
      expect(api.declarations, 1);
      expect(api.lastUnoPayload, {'window_id': 9});
      expect(api.penalties, 0);
      expect(app.unoAvailable, false);
      app.closeTable();
      app.dispose();
    },
  );
  testWidgets('missed UNO incurs one independent penalty and no normal draw', (
    tester,
  ) async {
    final api = FixtureApi()..snapshot = roomData(uno: true);
    final app = await create(api);
    await app.enter(id: 'table');
    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pump();
    expect(api.penalties, 1);
    expect(api.lastUnoPayload, {'window_id': 9});
    expect(api.commands, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(api.penalties, 1);
    expect(api.lastUnoPayload, {'window_id': 9});
    app.closeTable();
    app.dispose();
  });
  test('expired account while starting a game returns to login', () async {
    final api = FixtureApi()
      ..postError = const ApiFailure('unauthorized', 'expired', 401)
      ..readError = const ApiFailure('unauthorized', 'expired', 401);
    final app = await create(api);
    expect(await app.enter(solo: true), false);
    expect(app.account, null);
    expect(app.room, null);
    expect(app.recent, isEmpty);
    app.dispose();
  });
  test('offline logout still clears local account credentials', () async {
    final api = FixtureApi()
      ..postError = const ApiFailure('network', 'timeout');
    final app = await create(api);
    await app.logout();
    expect(app.account, null);
    expect(app.recent, isEmpty);
    expect(await api.storage.read(key: 'account_cookies'), null);
    app.dispose();
  });
  testWidgets('early UNO penalty is retried with the same window only', (
    tester,
  ) async {
    final api = FixtureApi()
      ..snapshot = roomData(uno: true)
      ..penaltyErrorOnce = const ApiFailure('uno_too_early', 'early', 409);
    final app = await create(api);
    await app.enter(id: 'table');
    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pump();
    expect(api.penalties, 1);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(api.penalties, 2);
    expect(api.lastUnoPayload, {'window_id': 9});
    expect(api.commands, 0);
    app.closeTable();
    app.dispose();
  });
}
