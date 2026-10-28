import 'package:flutter_test/flutter_test.dart';
import 'package:unour/core/controller.dart';
import 'package:unour/core/models.dart';

Room snapshot({
  int revision = 1,
  int version = 1,
  String role = 'player',
  String phase = 'playing',
}) => Room({
  'id': 'test',
  'revision': revision,
  'role': role,
  'round': 1,
  'roster_version': 2,
  'state': {
    'version': version,
    'phase': phase,
    'you': 'a',
    'turn': 'a',
    'active_color': 'red',
    'players': [
      {
        'id': 'a',
        'name': 'Alice',
        'hand_count': 1,
        'hand': [
          {'id': 7, 'color': 'red', 'kind': 'number'},
        ],
      },
    ],
    'legal_actions': [
      {'action': 'play', 'card_id': 7},
      {'action': 'draw'},
    ],
  },
});
void main() {
  test('number zero may be omitted and wild has physical wild color', () {
    expect(
      UnoCard.fromJson({'id': 7, 'color': 'red', 'kind': 'number'}).number,
      0,
    );
    final wild = UnoCard.fromJson({
      'id': 9,
      'color': 'wild',
      'kind': 'wild_draw_four',
    });
    expect(wild.isWild, true);
    expect(wild.symbol, '+4');
  });
  test('spectators have no permitted game actions or private hand', () {
    final room = Room({
      'id': 'test',
      'role': 'spectator',
      'state': {
        'you': 'viewer',
        'players': [],
        'legal_actions': [
          {'action': 'draw'},
        ],
      },
    });
    expect(room.me, null);
    expect(room.allows('draw'), false);
  });
  test('room recognizes legal cards without implementing rules', () {
    final room = snapshot();
    expect(room.plays(room.me!.hand.first).length, 1);
    expect(room.allows('challenge'), false);
    expect(room.allows('draw'), true);
  });
  test('stale snapshots never replace newer versions or roster revisions', () {
    final room = snapshot(revision: 5, version: 4);
    expect(acceptsSnapshot(room, snapshot(revision: 4, version: 4)), false);
    expect(acceptsSnapshot(room, snapshot(revision: 5, version: 3)), false);
    expect(acceptsSnapshot(room, snapshot(revision: 6, version: 4)), true);
    expect(acceptsSnapshot(room, snapshot(revision: 6, version: 5)), true);
  });
  test('finished room may have no winner or wait for final plus four', () {
    expect(snapshot(phase: 'finished').state['winner'], null);
    final room = Room({
      'id': 'test',
      'state': {'phase': 'playing', 'finishing_player': 'a'},
    });
    expect(room.state['finishing_player'], 'a');
  });
  test('dynamic rule enforces constraints and dependent options', () {
    final rule = RuleSelection(
      RuleModule({
        'name': 'draw',
        'required': true,
        'options': [
          {'key': 'play_drawn_card', 'type': 'boolean', 'default': true},
          {
            'key': 'play_any_after_draw',
            'type': 'boolean',
            'default': false,
            'depends_on': [
              {'key': 'play_drawn_card', 'equals': true},
            ],
          },
        ],
      }),
    );
    rule.values['play_any_after_draw'] = true;
    rule.values['play_drawn_card'] = false;
    expect(object(rule.toJson()['options'])['play_any_after_draw'], false);
    final matching = RuleSelection(
      RuleModule({
        'name': 'matching',
        'required': true,
        'options': [
          {'key': 'same_color', 'type': 'boolean', 'default': true},
          {'key': 'same_value', 'type': 'boolean', 'default': true},
        ],
        'constraints': [
          {
            'kind': 'at_least_one',
            'fields': ['same_color', 'same_value'],
            'message': '至少一项',
          },
        ],
      }),
    );
    matching.values.updateAll((k, v) => false);
    expect(matching.error, '至少一项');
  });
  test(
    'unknown option types and invalid integers block enabled rule submission',
    () {
      final unknown = RuleSelection(
        RuleModule({
          'name': 'future',
          'default_enabled': true,
          'options': [
            {'key': 'x', 'type': 'future'},
          ],
        }),
      );
      expect(unknown.error, isNotNull);
      unknown.enabled = false;
      expect(unknown.error, null);
      final limit = RuleSelection(
        RuleModule({
          'name': 'limit',
          'default_enabled': true,
          'options': [
            {
              'key': 'limit',
              'type': 'integer',
              'default': 25,
              'min': 8,
              'max': 108,
            },
          ],
        }),
      );
      limit.values['limit'] = 7;
      expect(limit.error, isNotNull);
      limit.values['limit'] = 108;
      expect(limit.error, null);
    },
  );
}
