import 'match_history.dart';

enum MatchChangeKind {
  opening,
  gap,
  card,
  turn,
  count,
  uno,
  penalty,
  direction,
  color,
  finish,
  roster,
}

class MatchChange {
  final MatchChangeKind kind;
  final String text;
  const MatchChange(this.kind, this.text);
}

List<MatchChange> matchChanges(MatchFrame? before, MatchFrame next) {
  if (before == null) {
    return const [MatchChange(MatchChangeKind.opening, '从这次收到的牌况开始记录')];
  }
  final changes = <MatchChange>[
    if (next.gapBefore)
      const MatchChange(MatchChangeKind.gap, '期间有未记录的变化，以下为再次收到的牌况'),
  ];
  if (next.phase == 'finished' && before.phase != 'finished') {
    changes.add(
      MatchChange(
        MatchChangeKind.finish,
        next.winner.isEmpty
            ? '收到结算：本局无胜者'
            : '收到结算：${next.playerName(next.winner)} 获胜',
      ),
    );
  }
  if (next.topCard?.id != before.topCard?.id && next.topCard != null) {
    changes.add(
      MatchChange(MatchChangeKind.card, '当前牌变为${next.topCard!.label}'),
    );
  }
  if (next.activeColor != before.activeColor) {
    changes.add(
      MatchChange(MatchChangeKind.color, '有效颜色变为${_color(next.activeColor)}'),
    );
  }
  if (next.direction != before.direction) {
    changes.add(
      MatchChange(
        MatchChangeKind.direction,
        '当前方向：${next.direction == 1 ? '顺时针' : '逆时针'}',
      ),
    );
  }
  if (next.pendingDraw != before.pendingDraw) {
    changes.add(
      MatchChange(
        MatchChangeKind.penalty,
        '罚牌池：+${before.pendingDraw} → +${next.pendingDraw}',
      ),
    );
  }
  for (final player in next.players) {
    final old = before.player(player.id);
    if (old == null) {
      changes.add(
        MatchChange(
          MatchChangeKind.roster,
          '记录到玩家 ${player.name} · ${player.count} 张',
        ),
      );
      continue;
    }
    if (player.count != old.count) {
      changes.add(
        MatchChange(
          MatchChangeKind.count,
          '${player.name} 的牌数：${old.count} → ${player.count}',
        ),
      );
    }
    if (player.declared > old.declared) {
      changes.add(
        MatchChange(MatchChangeKind.uno, '收到 ${player.name} 的 UNO 声明'),
      );
    }
    if (player.penalized > old.penalized) {
      changes.add(
        MatchChange(MatchChangeKind.penalty, '收到 ${player.name} 漏喊 UNO 的罚牌标记'),
      );
    }
    if ((!old.eliminated && player.eliminated) ||
        (!old.departed && player.departed)) {
      changes.add(
        MatchChange(
          MatchChangeKind.roster,
          '${player.name} ${player.departed ? '已离开' : '已淘汰'}',
        ),
      );
    }
  }
  if (next.turn != before.turn && next.phase == 'playing') {
    changes.add(
      MatchChange(MatchChangeKind.turn, '当前轮到 ${next.playerName(next.turn)}'),
    );
  }
  if (changes.isEmpty) {
    changes.add(const MatchChange(MatchChangeKind.opening, '收到新的牌况'));
  }
  return changes;
}

String _color(String color) => switch (color) {
  'red' => '红色',
  'blue' => '蓝色',
  'green' => '绿色',
  'yellow' => '黄色',
  _ => '待选色',
};
