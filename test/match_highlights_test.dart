import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unour/core/match_highlights.dart';
import 'package:unour/core/match_history.dart';
import 'package:unour/core/models.dart';

import 'match_history_test.dart' show localSession, observedRoom;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'highlights describe confirmed UNO identifiers and observed limits',
    () async {
      SharedPreferences.setMockInitialValues({});
      final history = MatchHistory(await SharedPreferences.getInstance())
        ..selectAccount('a');
      history.observe(observedRoom(count: 2), localSession);
      history.observe(
        observedRoom(version: 2, count: 1, declared: 18, pending: 8),
        localSession,
      );
      history.observe(
        observedRoom(
          version: 3,
          count: 0,
          declared: 18,
          phase: 'finished',
          winner: 'me',
        ),
        localSession,
      );
      final highlights = matchHighlights(history.records.single);
      expect(
        highlights.map((h) => h.title),
        containsAll(['空手收工', 'UNO 喊到了', '罚牌池高点']),
      );
      expect(
        highlights.where((h) => h.kind == HighlightKind.uno).single.value,
        '1',
      );
      expect(
        highlights.where((h) => h.kind == HighlightKind.pressure).single.value,
        '+8',
      );
      expect(highlights.any((h) => h.kind == HighlightKind.close), false);
      await history.flush();
      history.dispose();
    },
  );

  test(
    'a state jump cannot manufacture reversal counts or a personal win',
    () async {
      SharedPreferences.setMockInitialValues({});
      final history = MatchHistory(await SharedPreferences.getInstance())
        ..selectAccount('a');
      history.observe(observedRoom(count: 4), localSession);
      final end = observedRoom(
        version: 9,
        phase: 'finished',
        winner: 'friend',
        count: 1,
      );
      history.observe(
        Room({
          ...end.raw,
          'state': {...end.state, 'direction': -1},
        }),
        localSession,
      );
      final highlights = matchHighlights(history.records.single);
      expect(highlights.any((h) => h.kind == HighlightKind.direction), false);
      expect(highlights.any((h) => h.title == '空手收工'), false);
      expect(highlights.single.title, '离终点很近');
      expect(highlights.single.detail, contains('记录里'));
      await history.flush();
      history.dispose();
    },
  );
}
