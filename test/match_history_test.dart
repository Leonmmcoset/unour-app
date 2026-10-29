import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unour/core/match_history.dart';
import 'package:unour/core/models.dart';

Room observedRoom({
  int version = 1,
  int round = 1,
  String phase = 'playing',
  String winner = '',
  String role = 'player',
  String createdAt = '2026-10-29T10:00:00Z',
  int count = 7,
  int declared = 0,
  int pending = 0,
  String color = 'red',
}) => Room({
  'id': 'LOCAL',
  'created_at': createdAt,
  'round': round,
  'revision': version,
  'role': role,
  'token': 'must-not-store',
  'profiles': {
    'me': {'avatar_url': 'must-not-store'},
  },
  'state': {
    'phase': phase,
    'version': version,
    'you': 'me',
    'turn': version.isEven ? 'friend' : 'me',
    'winner': winner,
    'active_color': color,
    'pending_draw': pending,
    'top_card': {'id': version, 'color': color, 'kind': 'number', 'number': 5},
    'legal_actions': [
      {'action': 'draw', 'secret': 'must-not-store'},
    ],
    'players': [
      {
        'id': 'me',
        'name': '小林',
        'hand_count': count,
        'uno_declared': declared,
        'hand': [
          {'id': 777, 'color': 'secret-color', 'kind': 'wild'},
        ],
      },
      {'id': 'friend', 'name': '朋友', 'hand_count': 4},
    ],
  },
});

const localSession = RoomSession(
  id: 'LOCAL',
  playerId: 'me',
  token: 'secret-token',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences store;
  late MatchHistory history;
  var time = DateTime.utc(2026, 10, 29, 10);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    time = DateTime.utc(2026, 10, 29, 10);
    history = MatchHistory(store, now: () => time)..selectAccount('account-a');
  });
  tearDown(() async {
    await history.flush();
    history.dispose();
  });

  test(
    'only an observed participant round followed by a result counts once',
    () {
      history.observe(observedRoom(phase: 'lobby'), localSession);
      history.observe(
        observedRoom(phase: 'finished', winner: 'me'),
        localSession,
      );
      history.observe(observedRoom(role: 'spectator'), localSession);
      history.observe(observedRoom(), null);
      expect(history.records, isEmpty);
      history.observe(observedRoom(), localSession);
      expect(history.completed, 0);
      expect(history.unsettled, 1);
      time = time.add(const Duration(minutes: 2));
      final result = observedRoom(
        version: 2,
        phase: 'finished',
        winner: 'me',
        count: 0,
      );
      history.observe(result, localSession);
      history.observe(result, localSession);
      history.observe(observedRoom(), localSession);
      expect(history.records, hasLength(1));
      expect(history.records.single.frames, hasLength(2));
      expect(history.completed, 1);
      expect(history.wins, 1);
      expect(history.winRate, 100);
      expect(history.records.single.endedAt, time);
    },
  );

  test('unsettled rounds are excluded and rematches are separate results', () {
    history.observe(observedRoom(), localSession);
    history.interrupt();
    history.observe(observedRoom(round: 2), localSession);
    history.observe(
      observedRoom(round: 2, version: 3, phase: 'finished', winner: 'friend'),
      localSession,
    );
    history.observe(observedRoom(round: 3), localSession);
    history.observe(
      observedRoom(round: 3, version: 4, phase: 'finished'),
      localSession,
    );
    expect(history.records, hasLength(3));
    expect(history.completed, 2);
    expect(history.wins, 0);
    expect(history.unsettled, 1);
    expect(history.records.first.resultLabel, '无胜者');
    history.observe(
      observedRoom(createdAt: '2026-11-01T10:00:00Z'),
      localSession,
    );
    expect(history.records, hasLength(4));
  });

  test(
    'repeated snapshots and vote revisions do not duplicate observations',
    () {
      final first = observedRoom();
      history.observe(first, localSession);
      time = time.add(const Duration(seconds: 1));
      history.observe(
        Room({
          ...first.raw,
          'revision': 10,
          'rematch_votes': ['me'],
        }),
        localSession,
      );
      expect(history.records.single.frames, hasLength(1));
      history.observe(observedRoom(version: 2, declared: 19), localSession);
      history.observe(observedRoom(version: 3, declared: 19), localSession);
      expect(history.records.single.observedUno, 1);
    },
  );

  test('gaps survive restart and backwards snapshots are ignored', () async {
    history.observe(observedRoom(), localSession);
    history.observe(observedRoom(version: 4), localSession);
    expect(history.records.single.latest.gapBefore, true);
    history.observe(observedRoom(version: 2), localSession);
    expect(history.records.single.frames, hasLength(2));
    await history.flush();
    final restored = MatchHistory(store, now: () => time)
      ..selectAccount('account-a');
    restored.observe(observedRoom(version: 5), localSession);
    expect(restored.records.single.latest.gapBefore, true);
    restored.interrupt();
    restored.observe(observedRoom(version: 6), localSession);
    expect(restored.records.single.latest.gapBefore, true);
    await restored.flush();
    restored.dispose();
  });

  test(
    'storage persists public summaries and isolates accounts without credentials',
    () async {
      history.observe(observedRoom(), localSession);
      history.observe(
        observedRoom(version: 2, phase: 'finished', winner: 'me'),
        localSession,
      );
      await history.flush();
      final saved = store.getString(MatchHistory.storageKey('account-a'))!;
      expect(saved, isNot(contains('secret')));
      expect(saved, isNot(contains('must-not-store')));
      expect(saved, isNot(contains('legal_actions')));
      expect(saved, isNot(contains('"hand"')));
      history.selectAccount('account-b');
      expect(history.records, isEmpty);
      history.observe(observedRoom(round: 8), localSession);
      await history.flush();
      history.selectAccount(null);
      expect(history.records, isEmpty);
      history.selectAccount('account-a');
      expect(history.records.single.round, 1);
      expect(history.wins, 1);
      history.selectAccount('account-b');
      expect(history.records.single.round, 8);
    },
  );

  test(
    'long matches retain the opening and latest state with an omission marker',
    () {
      for (var version = 1; version <= 125; version++) {
        history.observe(observedRoom(version: version), localSession);
      }
      final record = history.records.single;
      expect(record.frames, hasLength(MatchHistory.maxFrames));
      expect(record.frames.first.version, 1);
      expect(record.latest.version, 125);
      expect(record.frames[1].gapBefore, true);
      expect(record.omittedFrames, 125 - MatchHistory.maxFrames);
    },
  );

  test(
    'clearing during a round does not recreate it on the next poll or restart',
    () async {
      history.observe(observedRoom(), localSession);
      await history.clear();
      history.observe(observedRoom(version: 2), localSession);
      history.observe(
        observedRoom(version: 3, phase: 'finished', winner: 'me'),
        localSession,
      );
      expect(history.records, isEmpty);
      await history.flush();
      final restored = MatchHistory(store)..selectAccount('account-a');
      restored.observe(observedRoom(version: 4), localSession);
      expect(restored.records, isEmpty);
      restored.observe(observedRoom(round: 2), localSession);
      expect(restored.records, hasLength(1));
      await restored.flush();
      restored.dispose();
    },
  );

  test('one invalid record does not hide valid results', () async {
    history.observe(observedRoom(), localSession);
    await history.flush();
    final data =
        jsonDecode(store.getString(MatchHistory.storageKey('account-a'))!)
            as Map<String, dynamic>;
    (data['records'] as List).add({'id': 'bad'});
    await store.setString(
      MatchHistory.storageKey('account-a'),
      jsonEncode(data),
    );
    history.selectAccount('account-b');
    await history.flush();
    // The queued old-account write intentionally precedes the fixture below.
    await store.setString(
      MatchHistory.storageKey('account-a'),
      jsonEncode(data),
    );
    history.selectAccount('account-a');
    expect(history.records, hasLength(1));
    expect(history.storageError, isNotNull);
  });
}
