import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/controller.dart';
import '../core/models.dart';
import 'design.dart';
import 'hand_strip.dart';
import 'motion.dart';
import 'table_widgets.dart';

class RoomPage extends ConsumerStatefulWidget {
  const RoomPage({super.key});
  @override
  ConsumerState<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends ConsumerState<RoomPage> {
  int? _selected;
  String? _handScope;
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
                    for (final (index, value) in colors.indexed)
                      MotionEntrance(
                        delay: index * 45,
                        offset: const Offset(0, 12),
                        child: PressScale(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: cardColor(
                                value == 'keep' ? room.activeColor : value,
                              ),
                              foregroundColor:
                                  (value == 'keep'
                                          ? room.activeColor
                                          : value) ==
                                      'yellow'
                                  ? const Color(0xff553812)
                                  : Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 18,
                              ),
                            ),
                            onPressed: () => Navigator.pop(context, value),
                            child: Text(colorName(value)),
                          ),
                        ),
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
    final scope = '${room.id}:${room.round}';
    if (_handScope != scope) {
      _handScope = scope;
      _selected = null;
    }
    final media = MediaQuery.of(context);
    final reduce = prefs.reduceMotion || media.disableAnimations;
    final colors = Theme.of(context).colorScheme;
    return MediaQuery(
      data: media.copyWith(disableAnimations: reduce),
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: math.max(
            60,
            media.textScaler.scale(16) * 1.25 +
                media.textScaler.scale(11) * 1.4 +
                10,
          ),
          leading: IconButton(
            tooltip: '返回首页，保留座位',
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '牌桌 ${room.id}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '第 ${room.round} 局${room.isSpectator ? ' · 观战中' : ''}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '复制房间号',
              onPressed: () => _menu('copy', app),
              icon: const Icon(Icons.copy_rounded, size: 20),
            ),
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
                      color: colors.tertiaryContainer,
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
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: MotionSwitcher(
                        child: Text(
                          app.notice!,
                          key: ValueKey(app.notice),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: MotionEntrance(
                      key: ValueKey('$scope:${room.phase}'),
                      offset: const Offset(0, 12),
                      child: room.phase == 'lobby'
                          ? _lobby(room, app)
                          : room.phase == 'finished'
                          ? _finished(room, app)
                          : _table(room, app, reduce),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _lobby(Room room, AppController app) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
    children: [
      const PartyHero(compact: true),
      Text(
        '等待玩家加入',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 14),
      Center(
        child: ActionChip(
          avatar: const Icon(Icons.copy_rounded, size: 16),
          label: Text(room.id),
          onPressed: () => _menu('copy', app),
        ),
      ),
      const SizedBox(height: 24),
      GamePanel(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            for (final p in room.players)
              ListTile(
                leading: ProfileAvatar(
                  name: p.name,
                  url:
                      '${object(object(room.raw['profiles'])[p.id])['avatar_url'] ?? ''}',
                ),
                title: Text('${p.name}${p.id == room.you ? '（我）' : ''}'),
                trailing: Text(
                  p.id == room.host ? '房主' : '已就位',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      if (room.isSpectator)
        FilledButton.tonalIcon(
          onPressed: app.busy
              ? null
              : () => app.action('participation', {'next_round': true}),
          icon: const Icon(Icons.event_seat_outlined),
          label: const Text('加入这一局'),
        ),
      if (room.isHost && !room.isSpectator)
        PressScale(
          child: FilledButton.icon(
            onPressed: app.busy || room.players.length < 2
                ? null
                : () => app.action('start'),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('发牌！'),
          ),
        ),
      if (!room.isHost)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('等待房主发牌', textAlign: TextAlign.center),
        ),
      TextButton.icon(
        onPressed: () => _details(room),
        icon: const Icon(Icons.info_outline_rounded, size: 18),
        label: const Text('玩家与规则'),
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
    final theme = Theme.of(context), colors = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        SizedBox(
          height: 148,
          child: RoundCelebration(
            key: ValueKey((room.id, room.round, winner)),
            child: Center(
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: cardColor('yellow').withValues(alpha: .14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  winner.isEmpty
                      ? Icons.style_rounded
                      : Icons.emoji_events_rounded,
                  size: 52,
                  color: cardColor('yellow'),
                ),
              ),
            ),
          ),
        ),
        Text(
          winner.isEmpty
              ? '这一局结束啦'
              : won
              ? '你赢了！'
              : '${room.playerName(winner)} 赢啦！',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 24),
        GamePanel(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              for (final p in room.players)
                ListTile(
                  leading: p.id == winner
                      ? Icon(
                          Icons.emoji_events_rounded,
                          color: cardColor('yellow'),
                        )
                      : ProfileAvatar(
                          name: p.name,
                          radius: 18,
                          url:
                              '${object(object(room.raw['profiles'])[p.id])['avatar_url'] ?? ''}',
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
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final s in room.spectators.where(
                (s) => s['next_round'] == true,
              ))
                ListTile(
                  leading: const Icon(Icons.event_seat_outlined),
                  title: Text('${s['name']}'),
                  subtitle: const Text('下局入座'),
                  trailing: Text(
                    room.votes.contains('${s['id']}') ? '已同意' : '等待同意',
                    style: theme.textTheme.labelMedium,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (participant)
          PressScale(
            child: FilledButton.icon(
              onPressed: app.busy
                  ? null
                  : () => app.action('rematch', {
                      'agree': !voted,
                      'round': room.round,
                      'roster_version': room.rosterVersion,
                    }),
              icon: Icon(voted ? Icons.undo_rounded : Icons.replay_rounded),
              label: Text(voted ? '撤回同意' : '再来一局'),
            ),
          ),
        if (room.isSpectator) _reservation(room, app),
        const SizedBox(height: 12),
        Text(
          '全员同意后自动发牌；名单变化时需重新同意。',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
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
    final hand = room.me?.hand ?? <UnoCard>[];
    final selected = hand.where((card) => card.id == _selected).firstOrNull;
    final enabled = !app.busy && app.online && !app.roomUnavailable;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight < 680 || constraints.maxWidth < 350;
        final reservedHeight = room.isSpectator
            ? 110
            : compact
            ? 268
            : 294;
        final arenaHeight =
            (constraints.maxHeight - (compact ? 76 : 88) - reservedHeight - 24)
                .clamp(compact ? 208.0 : 268.0, compact ? 256.0 : 340.0);
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OpponentsStrip(
                  room: room,
                  compact: compact,
                  onDetails: () => _details(room),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                  child: TableArena(
                    room: room,
                    compact: compact,
                    minHeight: arenaHeight,
                    onDraw: enabled && room.allows('draw')
                        ? () => app.action('draw')
                        : null,
                    onPlay:
                        selected != null &&
                            enabled &&
                            room.plays(selected).isNotEmpty
                        ? () => _play(selected)
                        : null,
                  ),
                ),
                if (room.isSpectator)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: Column(
                      children: [
                        const Text('正在观战'),
                        const SizedBox(height: 12),
                        _reservation(room, app),
                      ],
                    ),
                  )
                else
                  _handPanel(room, app, compact, reduce),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _handPanel(Room room, AppController app, bool compact, bool reduce) {
    final hand = room.me?.hand ?? <UnoCard>[];
    final selected = hand.where((card) => card.id == _selected).firstOrNull;
    final mine = room.turn == room.you;
    final enabled = !app.busy && app.online && !app.roomUnavailable;
    final canPlay =
        selected != null && enabled && room.plays(selected).isNotEmpty;
    final colors = Theme.of(context).colorScheme;
    final hint = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        selected != null
            ? '${selected.label} · ${room.plays(selected).isEmpty ? '当前不能出' : '再点一次出牌'}'
            : mine
            ? '轻点选牌，再点一次出牌'
            : '可先选牌，等待你的回合',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: canPlay ? colors.primary : colors.onSurfaceVariant,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: GamePanel(
        padding: EdgeInsets.zero,
        color: colors.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (app.unoAvailable || app.unoSending)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: MotionEntrance(
                  offset: const Offset(0, 8),
                  child: Column(
                    children: [
                      PressScale(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: cardColor('red'),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 50),
                          ),
                          onPressed: app.unoAvailable ? app.declareUno : null,
                          icon: const Icon(Icons.campaign_rounded),
                          label: Text(app.unoSending ? '正在喊 UNO…' : 'UNO！'),
                        ),
                      ),
                      const SizedBox(height: 5),
                      LinearProgressIndicator(
                        value: app.unoProgress,
                        color: cardColor('red'),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: MotionSwitcher(
                      child: Align(
                        key: ValueKey((hand.length, room.me?.eliminated)),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          room.me?.eliminated == true
                              ? '已淘汰 · 继续观战'
                              : '我的手牌 · ${hand.length} 张',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: hand.isEmpty ? null : _showHand,
                    style: TextButton.styleFrom(
                      textStyle: Theme.of(context).textTheme.labelMedium,
                      minimumSize: const Size(48, 40),
                    ),
                    icon: const Icon(Icons.grid_view_rounded, size: 15),
                    label: const Text('全部手牌'),
                  ),
                ],
              ),
            ),
            HandStrip(
              key: ValueKey(_handScope),
              cards: hand,
              selected: _selected,
              cardWidth: compact ? 70 : 82,
              reduceMotion: reduce,
              dimUnavailable: mine,
              isPlayable: (card) => room.plays(card).isNotEmpty,
              onTap: (card) {
                if (_selected == card.id &&
                    enabled &&
                    room.plays(card).isNotEmpty) {
                  _play(card);
                } else {
                  setState(() => _selected = card.id);
                }
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                children: [
                  if (reduce)
                    hint
                  else
                    AnimatedSize(
                      duration: const Duration(milliseconds: 240),
                      curve: GameMotion.settle,
                      child: hint,
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: PressScale(
                          child: FilledButton.icon(
                            key: const ValueKey('play-card'),
                            onPressed: canPlay ? () => _play(selected) : null,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            icon: const Icon(
                              Icons.north_east_rounded,
                              size: 19,
                            ),
                            label: const Text('出牌'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: PressScale(
                          child: FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            onPressed: enabled && room.allows('draw')
                                ? () => app.action('draw')
                                : null,
                            icon: const Icon(Icons.add_rounded, size: 19),
                            label: Text(
                              integer(room.state['pending_draw']) > 0
                                  ? '摸 ${room.state['pending_draw']} 张'
                                  : '摸一张',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (room.allows('pass') || room.allows('challenge')) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        if (room.allows('pass'))
                          TextButton.icon(
                            onPressed: enabled
                                ? () => app.action('pass')
                                : null,
                            icon: const Icon(Icons.skip_next_rounded, size: 18),
                            label: const Text('过牌'),
                          ),
                        if (room.allows('challenge'))
                          TextButton.icon(
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
                            icon: const Icon(
                              Icons.help_outline_rounded,
                              size: 18,
                            ),
                            label: const Text('质疑 +4'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHand() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .72,
        builder: (context, scroll) => Consumer(
          builder: (context, ref, child) {
            final hand = ref.watch(appProvider).room?.me?.hand ?? <UnoCard>[];
            return CustomScrollView(
              controller: scroll,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    child: Text(
                      '全部手牌 · ${hand.length} 张',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  sliver: SliverGrid.builder(
                    itemCount: hand.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: math.max(
                        3,
                        (MediaQuery.sizeOf(context).width / 104).floor(),
                      ),
                      childAspectRatio: .67,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    itemBuilder: (context, index) => FittedBox(
                      child: PlayingCard(
                        card: hand[index],
                        selected: hand[index].id == _selected,
                        onTap: () {
                          setState(() => _selected = hand[index].id);
                          Navigator.pop(context);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
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
