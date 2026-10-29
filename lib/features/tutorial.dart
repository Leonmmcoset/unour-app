import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/controller.dart';
import '../core/models.dart';
import '../game/design.dart';
import '../game/motion.dart';

const _redFive = UnoCard(id: 105, color: 'red', kind: 'number', number: 5);
const _redEight = UnoCard(id: 108, color: 'red', kind: 'number', number: 8);
const _blueTwo = UnoCard(id: 202, color: 'blue', kind: 'number', number: 2);
const _greenFour = UnoCard(id: 304, color: 'green', kind: 'number', number: 4);
const _blueSeven = UnoCard(id: 207, color: 'blue', kind: 'number', number: 7);
const _wild = UnoCard(id: 500, color: 'wild', kind: 'wild');
const _titles = ['先认识牌桌', '选牌，再出牌', '摸牌与过牌', '特殊牌与选色', '剩一张，喊 UNO'];
const _descriptions = [
  '上方是其他玩家和牌数，中间看当前牌，下方是你的手牌。目标是先出完手牌。',
  '通常按颜色、数字或图案接牌。轮到你时，可出的牌会亮起；点一下选中，再点一次或按「出牌」。',
  '没有合适的牌时，先看「摸一张」。允许结束回合时，原来的位置会变成「过牌」。',
  '万能牌的牌面不变，出牌时要选接下来的颜色。能否出牌、叠加和质疑，都以本桌规则为准。',
  '出牌后剩一张时，看到 UNO 按钮，要在 2 秒内点下。漏喊会罚牌。这里不计时，可以慢慢试。',
];

/// Fixed teaching illustrations only: no Room, game engine, networking, real
/// countdown, or AppController action is involved in this page.
class TutorialPage extends ConsumerStatefulWidget {
  const TutorialPage({super.key});

  @override
  ConsumerState<TutorialPage> createState() => _TutorialPageState();
}

class _TutorialPageState extends ConsumerState<TutorialPage> {
  final _pages = PageController();
  int _step = 0, _drawStage = 0;
  bool _selected = false, _played = false, _unoCalled = false, _leaving = false;
  String? _wildColor;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _move(int step) {
    if (GameMotion.reduced(context)) {
      _pages.jumpToPage(step);
    } else {
      _pages.animateToPage(
        step,
        duration: const Duration(milliseconds: 360),
        curve: GameMotion.settle,
      );
    }
  }

  Future<void> _finish() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    try {
      await ref.read(preferencesProvider).finishTutorial();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('引导进度暂未保存，仍可从设置里重看')));
      }
    }
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('新手引导'),
        actions: [
          TextButton(
            onPressed: _leaving ? null : _finish,
            child: const Text('跳过'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Row(
                    children: [
                      for (var i = 0; i < _titles.length; i++)
                        Expanded(
                          child: Semantics(
                            selected: i == _step,
                            child: Tooltip(
                              message: '第 ${i + 1} 步：${_titles[i]}',
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => _move(i),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                    vertical: 22,
                                  ),
                                  child: AnimatedContainer(
                                    duration: GameMotion.duration(context, 200),
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: i <= _step
                                          ? colors.primary
                                          : colors.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 23),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '教学示意 · 以本桌规则为准',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          '${_step + 1} / ${_titles.length}',
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: _titles.length,
                    onPageChanged: (step) => setState(() => _step = step),
                    itemBuilder: (context, step) => SingleChildScrollView(
                      key: PageStorageKey('tutorial-step-$step'),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _titles[step],
                            style: theme.textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _descriptions[step],
                            style: theme.textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 24),
                          _lesson(step),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    children: [
                      if (_step > 0) ...[
                        IconButton.filledTonal(
                          tooltip: '上一步',
                          onPressed: _leaving ? null : () => _move(_step - 1),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _leaving
                              ? null
                              : _step == _titles.length - 1
                              ? _finish
                              : () => _move(_step + 1),
                          icon: Icon(
                            _step == _titles.length - 1
                                ? Icons.check_rounded
                                : Icons.arrow_forward_rounded,
                          ),
                          label: Text(
                            _step == _titles.length - 1 ? '完成引导' : '下一步',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _lesson(int step) => switch (step) {
    0 => _table(),
    1 => _play(),
    2 => _draw(),
    3 => _colors(),
    _ => _uno(),
  };

  Widget _table() => GamePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceEvenly,
          spacing: 20,
          runSpacing: 12,
          children: [
            for (final (name, count) in [('小林', 4), ('阿青', 7)])
              Column(
                children: [
                  ProfileAvatar(name: name, radius: 19),
                  const SizedBox(height: 5),
                  Text(
                    '$name · $count 张',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 24),
        const _GuidePiles(card: _redFive),
        const SizedBox(height: 18),
        _GuideNote(text: '轮到谁，看手牌上方的回合提示', icon: Icons.person_outline_rounded),
        const SizedBox(height: 16),
        const _GuideHand(cards: [_redEight, _blueTwo, _greenFour]),
        const SizedBox(height: 12),
        Text(
          '你的手牌在这里，可横向滑动查看',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );

  Widget _play() => GamePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GuidePiles(card: _played ? _redEight : _redFive),
        const SizedBox(height: 22),
        _GuideNote(
          text: _played
              ? '红色 8 接在红色 5 上，颜色相同'
              : _selected
              ? '选中了，再点这张牌或按「出牌」'
              : '试试点亮起的红色 8',
          icon: _played
              ? Icons.check_circle_outline_rounded
              : Icons.touch_app_outlined,
        ),
        const SizedBox(height: 12),
        _GuideHand(
          cards: [if (!_played) _redEight, _blueTwo, _greenFour],
          selected: _selected && !_played ? _redEight.id : null,
          playable: (card) => card.id == _redEight.id && !_played,
          onTap: (card) {
            if (card.id != _redEight.id || _played) return;
            setState(() {
              if (_selected) {
                _played = true;
              } else {
                _selected = true;
              }
            });
          },
        ),
        const SizedBox(height: 14),
        FilledButton.tonalIcon(
          key: const ValueKey('tutorial-play'),
          onPressed: _played
              ? () => setState(() {
                  _played = false;
                  _selected = false;
                })
              : _selected
              ? () => setState(() => _played = true)
              : null,
          icon: Icon(_played ? Icons.replay_rounded : Icons.north_rounded),
          label: Text(_played ? '再试一次' : '出牌'),
        ),
      ],
    ),
  );

  Widget _draw() => GamePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GuidePiles(card: _redFive),
        const SizedBox(height: 22),
        _GuideNote(
          text: switch (_drawStage) {
            0 => '这个示例里没有能接的牌，点「摸一张」',
            1 => '摸到蓝色 7；这个示例允许过牌',
            _ => '回合结束，轮到下一位',
          },
          icon: _drawStage == 2
              ? Icons.check_circle_outline_rounded
              : Icons.touch_app_outlined,
        ),
        const SizedBox(height: 12),
        _GuideHand(
          cards: [_blueTwo, _greenFour, if (_drawStage > 0) _blueSeven],
        ),
        const SizedBox(height: 14),
        FilledButton.tonalIcon(
          key: const ValueKey('tutorial-draw-pass'),
          onPressed: () => setState(() => _drawStage = (_drawStage + 1) % 3),
          icon: Icon(switch (_drawStage) {
            0 => Icons.add_rounded,
            1 => Icons.skip_next_rounded,
            _ => Icons.replay_rounded,
          }),
          label: Text(switch (_drawStage) {
            0 => '摸一张',
            1 => '过牌',
            _ => '再试一次',
          }),
        ),
        const SizedBox(height: 12),
        Text(
          '摸到后能否出牌、可否过牌，由本桌规则决定。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );

  Widget _colors() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GamePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: PlayingCard(card: _wild, width: 68)),
            const SizedBox(height: 18),
            _GuideNote(
              text: _wildColor == null
                  ? '点一个颜色，试着给万能牌选色'
                  : '接下来按${colorName(_wildColor!)}接牌，万能牌面保持不变',
              icon: Icons.palette_outlined,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                for (final color in ['red', 'blue', 'green', 'yellow'])
                  FilledButton.icon(
                    key: ValueKey('tutorial-color-$color'),
                    style: FilledButton.styleFrom(
                      backgroundColor: cardColor(color),
                      foregroundColor: color == 'yellow'
                          ? const Color(0xff553812)
                          : Colors.white,
                      minimumSize: const Size(100, 48),
                      textStyle: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(fontSize: 20),
                    ),
                    onPressed: () => setState(() => _wildColor = color),
                    icon: Icon(
                      _wildColor == color
                          ? Icons.check_rounded
                          : Icons.circle_outlined,
                      size: 17,
                    ),
                    label: Text(colorName(color)),
                  ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      GamePanel(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            for (final (symbol, title, detail) in [
              ('⊘', '跳过', '跳过下一位的回合'),
              ('⇄', '反转', '改变出牌方向'),
              ('+2', '加二 / 加四', '可能产生罚牌；叠加和质疑要看本桌规则'),
            ])
              ListTile(
                leading: SizedBox(
                  width: 32,
                  child: Text(
                    symbol,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                title: Text(title),
                subtitle: Text(detail),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _uno() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GamePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: PlayingCard(card: _redEight, width: 72)),
            const SizedBox(height: 12),
            Text(
              '还剩 1 张',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 22),
            PressScale(
              child: FilledButton(
                key: const ValueKey('tutorial-uno'),
                style: FilledButton.styleFrom(
                  backgroundColor: cardColor('red'),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(18),
                ),
                onPressed: () => setState(() => _unoCalled = !_unoCalled),
                child: MotionSwitcher(
                  child: Text(
                    _unoCalled ? 'UNO！喊到了' : 'UNO！',
                    key: ValueKey(_unoCalled),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _GuideNote(
              text: _unoCalled ? '记住这个按钮，正式牌局出现时及时点下' : '点一下喊 UNO，这里没有倒计时',
              icon: _unoCalled
                  ? Icons.check_circle_outline_rounded
                  : Icons.touch_app_outlined,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text(
        '出完手牌后等待结算；全员同意「再来一局」后才会继续。\n规则可从牌桌右上角「玩家与规则」查看。',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ],
  );
}

class _GuidePiles extends StatelessWidget {
  final UnoCard card;
  const _GuidePiles({required this.card});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (current, label) in <(UnoCard?, String)>[
        (null, '牌堆'),
        (card, '当前牌'),
      ])
        Expanded(
          child: Column(
            children: [
              MotionSwitcher(
                child: PlayingCard(
                  key: ValueKey(current?.id),
                  card: current,
                  width: 64,
                ),
              ),
              const SizedBox(height: 10),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
    ],
  );
}

class _GuideHand extends StatelessWidget {
  final List<UnoCard> cards;
  final int? selected;
  final bool Function(UnoCard)? playable;
  final ValueChanged<UnoCard>? onTap;
  const _GuideHand({
    required this.cards,
    this.selected,
    this.playable,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 111,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final card in cards)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: AnimatedSlide(
              offset: selected == card.id ? const Offset(0, -.07) : Offset.zero,
              curve: GameMotion.spring,
              duration: GameMotion.duration(context, 280),
              child: Opacity(
                opacity: playable == null || playable!(card) ? 1 : .4,
                child: PlayingCard(
                  key: ValueKey('tutorial-hand-${card.id}'),
                  card: card,
                  width: 54,
                  selected: selected == card.id,
                  onTap: onTap != null && (playable?.call(card) ?? true)
                      ? () => onTap!(card)
                      : null,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _GuideNote extends StatelessWidget {
  final String text;
  final IconData icon;
  const _GuideNote({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
