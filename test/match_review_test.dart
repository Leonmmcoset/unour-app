import 'package:flutter_test/flutter_test.dart';
import 'package:unour/core/match_history.dart';
import 'package:unour/core/match_review.dart';
import 'package:unour/core/models.dart';

import 'match_history_test.dart' show observedRoom;

void main() {
  test(
    'review reports public differences without inventing moves or actors',
    () {
      final start = MatchFrame.fromRoom(
        observedRoom(count: 7),
        DateTime.utc(2026),
      );
      final end = MatchFrame.fromRoom(
        observedRoom(version: 8, count: 10, pending: 8, color: 'blue'),
        DateTime.utc(2026, 1, 1, 0, 1),
        gap: true,
      );
      final changes = matchChanges(start, end);
      expect(changes.first.kind, MatchChangeKind.gap);
      expect(changes.map((c) => c.text), contains('小林 的牌数：7 → 10'));
      expect(changes.map((c) => c.text), contains('罚牌池：+0 → +8'));
      expect(changes.map((c) => c.text).join(), isNot(contains('摸了')));
      expect(changes.map((c) => c.text).join(), isNot(contains('打出')));
      expect(changes.any((c) => c.kind == MatchChangeKind.uno), false);
    },
  );

  test(
    'opening snapshot does not replay historical UNO or penalty markers',
    () {
      final room = observedRoom(declared: 99);
      final frame = MatchFrame.fromRoom(room, DateTime.utc(2026));
      expect(matchChanges(null, frame).single.kind, MatchChangeKind.opening);
      final next = observedRoom(
        version: 2,
        declared: 101,
        phase: 'finished',
        winner: 'friend',
      );
      final raw = {
        ...next.raw,
        'state': {...next.state, 'direction': -1},
      };
      final changes = matchChanges(
        frame,
        MatchFrame.fromRoom(Room(raw), DateTime.utc(2026, 1, 2)),
      );
      expect(changes.where((c) => c.kind == MatchChangeKind.uno), hasLength(1));
      expect(
        changes.where((c) => c.kind == MatchChangeKind.direction),
        hasLength(1),
      );
      expect(
        changes.where((c) => c.kind == MatchChangeKind.finish).single.text,
        '收到结算：朋友 获胜',
      );
    },
  );
}
