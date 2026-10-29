import 'match_history.dart';

enum HighlightKind { finish, uno, pressure, close, crowd, direction }

class MatchHighlight {
  final HighlightKind kind;
  final String title, detail, value;
  const MatchHighlight(this.kind, this.title, this.detail, this.value);
}

/// Every line describes a received state or an observed change. A version jump
/// is never expanded into imaginary draws, plays, reversals, or UNO calls.
List<MatchHighlight> matchHighlights(MatchRecord record) {
  final highlights = <MatchHighlight>[];
  final last = record.latest;
  if (record.won && last.player(record.myId)?.count == 0) {
    highlights.add(
      const MatchHighlight(HighlightKind.finish, '空手收工', '结算确认：你出完了所有手牌', '0'),
    );
  }
  if (record.observedUno > 0) {
    highlights.add(
      MatchHighlight(
        HighlightKind.uno,
        'UNO 喊到了',
        '本机确认了你的 ${record.observedUno} 次声明',
        '${record.observedUno}',
      ),
    );
  }
  if (record.peakPendingDraw >= 4) {
    highlights.add(
      MatchHighlight(
        HighlightKind.pressure,
        '罚牌池高点',
        '记录里，罚牌池最高叠到 +${record.peakPendingDraw}',
        '+${record.peakPendingDraw}',
      ),
    );
  }
  if (record.lowestHandCount > 0 && record.lowestHandCount <= 2) {
    highlights.add(
      MatchHighlight(
        HighlightKind.close,
        '离终点很近',
        '记录里，你最少剩 ${record.lowestHandCount} 张手牌',
        '${record.lowestHandCount}',
      ),
    );
  }
  var directionChanges = 0;
  final frames = record.frames;
  for (var i = 1; i < frames.length; i++) {
    if (!frames[i].gapBefore &&
        frames[i].version == frames[i - 1].version + 1 &&
        frames[i].direction != frames[i - 1].direction) {
      directionChanges++;
    }
  }
  if (directionChanges > 0) {
    highlights.add(
      MatchHighlight(
        HighlightKind.direction,
        '方向变了又变',
        '相邻记录中确认了 $directionChanges 次方向变化',
        '⇄',
      ),
    );
  }
  if (highlights.length < 3) {
    final maxCount = frames
        .expand((frame) => frame.players)
        .fold<RecordedPlayer?>(
          null,
          (best, p) => best == null || p.count > best.count ? p : best,
        );
    if (maxCount != null && maxCount.count >= 10) {
      highlights.add(
        MatchHighlight(
          HighlightKind.crowd,
          '手牌有点多',
          '记录里，${maxCount.name} 曾有 ${maxCount.count} 张手牌',
          '${maxCount.count}',
        ),
      );
    }
  }
  if (highlights.isEmpty && last.topCard != null) {
    highlights.add(
      MatchHighlight(
        HighlightKind.finish,
        '停在这张牌',
        '结算时的牌面是${last.topCard!.label}',
        last.topCard!.symbol,
      ),
    );
  }
  return highlights.take(4).toList(growable: false);
}
