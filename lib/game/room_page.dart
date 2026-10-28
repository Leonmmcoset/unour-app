import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/controller.dart';
import '../core/models.dart';
import 'design.dart';

class RoomPage extends ConsumerStatefulWidget {
  const RoomPage({super.key});
  @override
  ConsumerState<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends ConsumerState<RoomPage> {
  int? _selected;
  Future<void> _play(UnoCard card) async {
    final app = ref.read(appProvider), room = ref.read(appProvider).room!;
    final plays = room.plays(card);
    if (app.busy || !app.online || roomUnavailable(app) || plays.isEmpty) {
      return;
    }
    String? color;
    if (card.isWild) {
      final colors = plays
          .map((a) => '${a['color']}')
          .where((c) => ['red', 'blue', 'green', 'yellow', 'keep'].contains(c))
          .toSet()
          .toList();
      if (colors.isEmpty) return;
      color = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '下一张，什么颜色？',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final value in colors)
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: cardColor(
                            value == 'keep' ? room.activeColor : value,
                          ),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(context, value),
                        child: Text(colorName(value)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      );
      if (color == null) return;
      // A poll may have changed the turn while the color sheet was open.
      if (app.room?.version != room.version) {
        app.error = '牌桌已变化，请重新选择要出的牌';
        app.changed();
        return;
      }
    }
    final ok = await app.action('play', {
      'card_id': card.id,
      if (color != null) 'color': color,
    });
    if (ok && mounted) setState(() => _selected = null);
  }

  bool roomUnavailable(AppController app) =>
      app.roomUnavailable || app.room?.phase != 'playing';
  void _details(Room room) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .65,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(24),
          children: [
            Text('这桌的朋友', style: Theme.of(context).textTheme.headlineSmall),
            for (final p in room.players)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ProfileAvatar(
                  name: p.name,
                  url:
                      '${object(object(room.raw['profiles'])[p.id])['avatar_url'] ?? ''}',
                ),
                title: Text('${p.name}${p.id == room.you ? '（我）' : ''}'),
                subtitle: Text(
                  [
                    if (p.id == room.host) '房主',
                    if (object(room.raw['bots']).containsKey(p.id)) '电脑',
                    if (p.eliminated) '已淘汰',
                    if (room.departed.contains(p.id)) '已离开',
                    '${p.handCount} 张牌',
                  ].join(' · '),
                ),
              ),
            if (room.spectators.isNotEmpty) ...[
              const Divider(),
              const Text('观战席'),
              for (final s in room.spectators)
                ListTile(
                  title: Text('${s['name']}'),
                  trailing: Text(s['next_round'] == true ? '预约下局' : '观战'),
                ),
            ],
            const Divider(),
            Text('本桌规则', style: Theme.of(context).textTheme.titleLarge),
            for (final rule in objects(room.raw['rule_descriptions']))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${rule['title'] ?? rule['name']}'),
                subtitle: Text((rule['text'] as List? ?? []).join('\n')),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _menu(String value, AppController app) async {
    if (value == 'copy') {
      await Clipboard.setData(ClipboardData(text: app.room!.id));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('房间号已复制，发给朋友来玩')));
      }
    } else if (value == 'details') {
      _details(app.room!);
    } else if (value == 'settings') {
      context.push('/settings');
    } else if (value == 'home') {
      context.go('/');
    } else {
      final dissolve = value == 'dissolve';
      if (!await confirm(
        context,
        dissolve ? '解散这张牌桌？' : '离开牌桌？',
        dissolve ? '所有玩家都将离开这张牌桌。' : '局中退出会按弃权处理。只想暂时离开可返回首页，保留当前座位。',
      )) {
        return;
      }
      final ok = await app.exitRoom(dissolve: dissolve);
      if (ok && mounted) context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider), room = app.room;
    final prefs = ref.watch(preferencesProvider);
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('牌桌')),
        body: Center(
          child: FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('回首页'),
          ),
        ),
      );
    }
    final reduce =
        prefs.reduceMotion || MediaQuery.of(context).disableAnimations;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回首页，保留座位',
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '牌桌 ${room.id}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            Text(
              '第 ${room.round} 局${room.isSpectator ? ' · 观战中' : ''}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: '牌桌选项',
            onSelected: (v) => _menu(v, app),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'copy', child: Text('复制房间号')),
              const PopupMenuItem(value: 'details', child: Text('玩家与规则')),
              const PopupMenuItem(value: 'settings', child: Text('声音与外观')),
              const PopupMenuItem(value: 'home', child: Text('返回首页，保留座位')),
              const PopupMenuItem(value: 'leave', child: Text('退出房间')),
              if (room.isHost)
                const PopupMenuItem(value: 'dissolve', child: Text('解散房间')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              children: [
                if (!app.online)
                  Material(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.wifi_off_rounded, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              app.roomUnavailable ? '连接不可用' : '正在重新连接，暂时不能出牌',
                            ),
                          ),
                          TextButton(
                            onPressed: app.roomUnavailable
                                ? () => context.go('/')
                                : app.refresh,
                            child: Text(app.roomUnavailable ? '回首页' : '重试'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (app.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ErrorStrip(app.error, onDismiss: app.clearError),
                  ),
                if (app.notice != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 3,
                    ),
                    child: Text(
                      app.notice!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                Expanded(
                  child: room.phase == 'lobby'
                      ? _lobby(room, app)
                      : room.phase == 'finished'
                      ? _finished(room, app)
                      : _table(room, app, reduce),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _lobby(Room room, AppController app) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const PartyHero(compact: true),
      Text(
        '等待玩家加入',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 16),
      Center(
        child: ActionChip(
          avatar: const Icon(Icons.copy, size: 16),
          label: Text(room.id),
          onPressed: () => _menu('copy', app),
        ),
      ),
      const SizedBox(height: 16),
      for (final p in room.players)
        Card(
          child: ListTile(
            leading: ProfileAvatar(
              name: p.name,
              url:
                  '${object(object(room.raw['profiles'])[p.id])['avatar_url'] ?? ''}',
            ),
            title: Text('${p.name}${p.id == room.you ? '（我）' : ''}'),
            trailing: Text(p.id == room.host ? '房主' : '已就位'),
          ),
        ),
      const SizedBox(height: 16),
      if (room.isSpectator)
        FilledButton.tonal(
          onPressed: app.busy
              ? null
              : () => app.action('participation', {'next_round': true}),
          child: const Text('我也要入座'),
        ),
      if (room.isHost && !room.isSpectator)
        FilledButton.icon(
          onPressed: app.busy || room.players.length < 2
              ? null
              : () => app.action('start'),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('人齐了，发牌！'),
        ),
      if (!room.isHost) const Text('等待房主发牌', textAlign: TextAlign.center),
      TextButton(
        onPressed: () => _details(room),
        child: const Text('看看这桌的规则与观众'),
      ),
    ],
  );

  Widget _finished(Room room, AppController app) {
    final winner = '${room.state['winner'] ?? ''}', won = winner == room.you;
    final voted = room.votes.contains(room.you);
    final reserved = room.spectators.any(
      (s) => s['id'] == room.you && s['next_round'] == true,
    );
    final participant =
        (!room.isSpectator && !room.departed.contains(room.you)) || reserved;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(
          winner.isEmpty ? Icons.style_rounded : Icons.emoji_events_rounded,
          size: 84,
          color: const Color(0xffefb938),
        ),
        const SizedBox(height: 14),
        Text(
          winner.isEmpty
              ? '这一局结束啦'
              : won
              ? '你赢了！'
              : '${room.playerName(winner)} 赢啦！',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 24),
        for (final p in room.players)
          Card(
            child: ListTile(
              leading: Icon(
                p.id == winner
                    ? Icons.emoji_events_rounded
                    : Icons.person_outline,
              ),
              title: Text('${p.name}${p.id == room.you ? '（我）' : ''}'),
              subtitle: Text(
                room.departed.contains(p.id)
                    ? '已离开'
                    : p.eliminated
                    ? '已淘汰'
                    : '剩余 ${p.handCount} 张',
              ),
              trailing: Text(
                room.departed.contains(p.id)
                    ? '不参加下局'
                    : room.votes.contains(p.id) ||
                          object(room.raw['bots']).containsKey(p.id)
                    ? '已同意'
                    : '等待同意',
              ),
            ),
          ),
        for (final s in room.spectators.where((s) => s['next_round'] == true))
          ListTile(
            title: Text('${s['name']}'),
            subtitle: const Text('下局入座'),
            trailing: Text(room.votes.contains('${s['id']}') ? '已同意' : '等待同意'),
          ),
        const SizedBox(height: 16),
        if (participant)
          FilledButton(
            onPressed: app.busy
                ? null
                : () => app.action('rematch', {
                    'agree': !voted,
                    'round': room.round,
                    'roster_version': room.rosterVersion,
                  }),
            child: Text(voted ? '撤回同意' : '再来一局'),
          ),
        if (room.isSpectator) _reservation(room, app),
        const SizedBox(height: 8),
        const Text(
          '所有仍参赛的真人与预约玩家同意后，自动发牌。名单变化时需要重新同意。',
          textAlign: TextAlign.center,
        ),
        TextButton(
          onPressed: () => _menu('leave', app),
          child: const Text('离开牌桌'),
        ),
      ],
    );
  }

  Widget _reservation(Room room, AppController app) {
    final reserved = room.spectators.any(
      (s) => s['id'] == room.you && s['next_round'] == true,
    );
    return FilledButton.tonalIcon(
      onPressed: app.busy
          ? null
          : () => app.action('participation', {'next_round': !reserved}),
      icon: const Icon(Icons.event_seat_outlined),
      label: Text(reserved ? '取消下局预约' : '预约下一局'),
    );
  }

  Widget _table(Room room, AppController app, bool reduce) {
    final opponents = room.players.where((p) => p.id != room.you).toList();
    final hand = room.me?.hand ?? <UnoCard>[];
    final selected = hand.where((c) => c.id == _selected).firstOrNull;
    final mine = room.turn == room.you && !room.isSpectator;
    final enabled = !app.busy && app.online && !app.roomUnavailable;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 550;
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  height: compact ? 88 : 112,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: opponents.length,
                    separatorBuilder: (_, index) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final p = opponents[index], current = p.id == room.turn;
                      return AnimatedContainer(
                        duration: Duration(milliseconds: reduce ? 0 : 200),
                        width: 88,
                        decoration: BoxDecoration(
                          color: current
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: current
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (!compact)
                              ProfileAvatar(
                                name: p.name,
                                radius: 16,
                                url:
                                    '${object(object(room.raw['profiles'])[p.id])['avatar_url'] ?? ''}',
                              ),
                            Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              p.eliminated
                                  ? '已淘汰'
                                  : room.departed.contains(p.id)
                                  ? '已离开'
                                  : '${p.handCount} 张',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: p.handCount == 1
                                    ? cardColor('red')
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 6,
                  ),
                  child: Column(
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        alignment: WrapAlignment.center,
                        children: [
                          Chip(
                            avatar: Icon(
                              integer(room.state['direction'], 1) == 1
                                  ? Icons.rotate_right
                                  : Icons.rotate_left,
                              size: 18,
                            ),
                            label: const Text('出牌方向'),
                          ),
                          Chip(
                            avatar: Icon(
                              Icons.circle,
                              color: cardColor(room.activeColor),
                              size: 16,
                            ),
                            label: Text(colorName(room.activeColor)),
                          ),
                          if (integer(room.state['pending_draw']) > 0)
                            Chip(
                              label: Text('罚牌池 +${room.state['pending_draw']}'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        room.state['finishing_player'] != null
                            ? '等待最后一张 +4 结算'
                            : mine
                            ? '轮到你出牌'
                            : '等待 ${room.playerName(room.turn)} 出牌',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Column(
                            children: [
                              PlayingCard(
                                width: compact ? 64 : 80,
                                onTap: enabled && room.allows('draw')
                                    ? () => app.action('draw')
                                    : null,
                                playable: room.allows('draw'),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '牌堆 ${integer(room.state['draw_pile_count'])}',
                              ),
                            ],
                          ),
                          const SizedBox(width: 38),
                          Column(
                            children: [
                              AnimatedSwitcher(
                                duration: Duration(
                                  milliseconds: reduce ? 0 : 230,
                                ),
                                transitionBuilder: (child, animation) =>
                                    ScaleTransition(
                                      scale: animation,
                                      child: FadeTransition(
                                        opacity: animation,
                                        child: child,
                                      ),
                                    ),
                                child: PlayingCard(
                                  key: ValueKey(room.topCard?.id),
                                  card: room.topCard,
                                  width: compact ? 72 : 88,
                                  onTap:
                                      selected != null &&
                                          enabled &&
                                          room.plays(selected).isNotEmpty
                                      ? () => _play(selected)
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text('当前出牌'),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (room.isSpectator)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Text('正在观战'),
                        const SizedBox(height: 12),
                        _reservation(room, app),
                      ],
                    ),
                  )
                else
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (app.unoAvailable || app.unoSending)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 4,
                          ),
                          child: Column(
                            children: [
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: cardColor('red'),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 52),
                                ),
                                onPressed: app.unoAvailable
                                    ? app.declareUno
                                    : null,
                                icon: const Icon(Icons.campaign_rounded),
                                label: Text(
                                  app.unoSending ? '正在喊 UNO…' : 'UNO！就剩一张！',
                                ),
                              ),
                              const SizedBox(height: 4),
                              LinearProgressIndicator(
                                value: app.unoProgress,
                                color: cardColor('red'),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                room.me?.eliminated == true
                                    ? '你已淘汰，继续观战吧'
                                    : '我的手牌 · ${hand.length} 张',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: hand.isEmpty
                                  ? null
                                  : () => _showHand(hand),
                              child: const Text('全部手牌'),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: compact ? 128 : 156,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
                          itemCount: hand.length,
                          itemBuilder: (context, i) {
                            final card = hand[i], active = card.id == _selected;
                            final playable = room.plays(card).isNotEmpty;
                            final tilt = ((i % 5) - 2) * .025;
                            return SizedBox(
                              width: compact ? 53 : 60,
                              child: OverflowBox(
                                maxWidth: compact ? 68 : 78,
                                alignment: Alignment.centerLeft,
                                child: AnimatedContainer(
                                  duration: Duration(
                                    milliseconds: reduce ? 0 : 170,
                                  ),
                                  transform: Matrix4.translationValues(
                                    0,
                                    active ? -14 : 0,
                                    0,
                                  ),
                                  child: Transform.rotate(
                                    angle: active ? 0 : tilt,
                                    child: PlayingCard(
                                      card: card,
                                      width: active
                                          ? (compact ? 72 : 84)
                                          : (compact ? 66 : 76),
                                      selected: active,
                                      playable: playable || !mine,
                                      onTap: () {
                                        if (active && playable && enabled) {
                                          _play(card);
                                        } else {
                                          setState(() => _selected = card.id);
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Column(
                          children: [
                            if (selected != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  '${selected.label}${room.plays(selected).isEmpty ? ' · 当前不能出这张牌' : ' · 再点一次出牌'}',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                FilledButton(
                                  onPressed:
                                      selected != null &&
                                          enabled &&
                                          room.plays(selected).isNotEmpty
                                      ? () => _play(selected)
                                      : null,
                                  child: const Text('出牌'),
                                ),
                                FilledButton.tonal(
                                  onPressed: enabled && room.allows('draw')
                                      ? () => app.action('draw')
                                      : null,
                                  child: Text(
                                    integer(room.state['pending_draw']) > 0
                                        ? '承受 +${room.state['pending_draw']}'
                                        : '摸一张',
                                  ),
                                ),
                                if (room.allows('pass'))
                                  OutlinedButton(
                                    onPressed: enabled
                                        ? () => app.action('pass')
                                        : null,
                                    child: const Text('不出，过'),
                                  ),
                                if (room.allows('challenge'))
                                  OutlinedButton(
                                    onPressed: enabled
                                        ? () async {
                                            if (await confirm(
                                              context,
                                              '质疑这张 +4？',
                                              '若对方出牌前持有当前颜色，质疑成功；失败则按本桌规则承担额外罚牌。',
                                            )) {
                                              app.action('challenge');
                                            }
                                          }
                                        : null,
                                    child: const Text('质疑 +4'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showHand(List<UnoCard> hand) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        builder: (context, scroll) => GridView.builder(
          controller: scroll,
          padding: const EdgeInsets.all(20),
          itemCount: hand.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: math.max(
              3,
              (MediaQuery.sizeOf(context).width / 100).floor(),
            ),
            childAspectRatio: .67,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) => FittedBox(
            child: PlayingCard(
              card: hand[index],
              onTap: () {
                setState(() => _selected = hand[index].id);
                Navigator.pop(context);
              },
            ),
          ),
        ),
      ),
    );
  }
}

String colorName(String color) => switch (color) {
  'red' => '红色',
  'blue' => '蓝色',
  'green' => '绿色',
  'yellow' => '黄色',
  'keep' => '保持当前色',
  _ => '万能',
};
