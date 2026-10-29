import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'controller.dart';
import 'models.dart';
import 'preferences.dart';

final liveTableProvider = ChangeNotifierProvider<LiveTableController>((ref) {
  final live = LiveTableController(
    ref.read(appProvider),
    ref.read(preferencesProvider),
  );
  unawaited(live.initialize());
  return live;
});

String _short(String value, int limit) =>
    String.fromCharCodes(value.runes.take(limit));

/// Public table information only. Neither hand faces nor credentials enter
/// ActivityKit content, notification text, or a deep link.
Json liveTableSnapshot(Room room, DateTime updatedAt, {bool connected = true}) {
  final players = room.players;
  final mine = room.me;
  return {
    'roomId': room.id,
    'round': room.round,
    'revision': room.revision,
    'version': room.version,
    'phase': room.phase,
    'spectator': room.isSpectator,
    'turnName': _short(room.playerName(room.turn), 24),
    'isYourTurn': room.turn == room.you && !room.isSpectator,
    'myCount': mine?.handCount ?? 0,
    'topCard': room.topCard?.label ?? '等待发牌',
    'symbol': room.topCard?.symbol ?? 'U',
    'activeColor': room.activeColor,
    'pendingDraw': integer(room.state['pending_draw']),
    'direction': integer(room.state['direction'], 1),
    'players': players
        .take(10)
        .map(
          (p) =>
              '${_short(p.name, 12)} ${p.eliminated || room.departed.contains(p.id) ? '–' : p.handCount}',
        )
        .join(' · '),
    'connected': connected,
    'updatedAt': updatedAt.millisecondsSinceEpoch / 1000,
  };
}

class LiveTableController extends ChangeNotifier {
  final AppController app;
  final GamePreferences prefs;
  final MethodChannel channel;
  final String registrationPath;
  bool supported = false, allowed = false, realtime = false;
  String platform = '', message = '';
  Json? pendingOpen;
  bool _initialized = false, _disposed = false, _foreground = true;
  bool _dirty = false, _sending = false, _stopped = false;
  String? _lastDigest;
  DateTime? _lastPublished;

  LiveTableController(
    this.app,
    this.prefs, {
    this.channel = const MethodChannel('chat.csac.unour/live_table'),
    this.registrationPath = const String.fromEnvironment(
      'LIVE_ACTIVITY_REGISTRATION_PATH',
    ),
  }) {
    app.addListener(_schedule);
    prefs.addListener(_schedule);
    channel.setMethodCallHandler((call) async {
      if (call.method == 'openTable') {
        pendingOpen = object(call.arguments);
        _notify();
      } else if (call.method == 'pushToken') {
        await _registerPush(object(call.arguments));
      }
    });
  }

  Future<void> initialize() async {
    try {
      final result = object(await channel.invokeMethod('status'));
      supported = result['supported'] == true;
      allowed = result['allowed'] == true;
      realtime = result['realtime'] == true;
      platform = '${result['platform'] ?? ''}';
      if (prefs.liveTable && !allowed && supported) {
        message = '系统已关闭后台牌桌，可在系统设置中重新开启';
      }
      if (result['openTable'] is Map) pendingOpen = object(result['openTable']);
    } on MissingPluginException {
      supported = false;
    } on PlatformException {
      message = '无法读取系统牌桌状态';
    }
    _initialized = true;
    _notify();
    _schedule();
  }

  String get description => !supported
      ? '当前系统暂不支持'
      : platform == 'ios' && !realtime
      ? '显示最近同步的牌况；后台实时更新需要推送支持'
      : '切到后台后，在系统卡片持续查看牌况';

  Future<void> setEnabled(bool value) async {
    message = '';
    if (value) {
      try {
        allowed =
            await channel.invokeMethod<bool>('requestPermission') ?? false;
      } on PlatformException {
        allowed = false;
      } on MissingPluginException {
        allowed = false;
      }
      if (!allowed) {
        message = '未允许显示后台牌桌，可在系统设置中开启';
        _notify();
        return;
      }
    }
    _lastDigest = null;
    await prefs.toggle('live_table', value);
    _notify();
  }

  Future<void> setForeground(bool value) async {
    _foreground = value;
    if (!_initialized || !supported) return;
    final identity = app.account?.id, token = app.session?.token;
    try {
      final result = object(
        await channel.invokeMethod('foreground', {'value': value}),
      );
      final cookies = (result['cookies'] as List? ?? [])
          .whereType<String>()
          .toList();
      if (value && identity == app.account?.id && token == app.session?.token) {
        await app.api.acceptBackgroundCookies(cookies);
      }
    } on PlatformException {
      message = '后台牌桌暂不可用';
      _notify();
    } on MissingPluginException {
      supported = false;
      _notify();
    }
    _schedule();
  }

  void _schedule() {
    if (_disposed || !_initialized || !supported) return;
    _dirty = true;
    if (!_sending) unawaited(_drain());
  }

  Future<void> _drain() async {
    _sending = true;
    while (_dirty && !_disposed) {
      _dirty = false;
      final room = app.room, session = app.session;
      final enabled =
          prefs.liveTable &&
          allowed &&
          app.account != null &&
          !app.roomUnavailable &&
          room != null &&
          session?.id == room.id &&
          ['lobby', 'playing'].contains(room.phase);
      try {
        if (!enabled) {
          if (!_stopped) await channel.invokeMethod('stop');
          _stopped = true;
          _lastDigest = null;
          continue;
        }
        final snapshot = liveTableSnapshot(
          room,
          app.roomUpdatedAt ?? DateTime.now(),
          connected: app.online,
        );
        final connection = app.api.liveTableConnection(session!);
        final digest = jsonEncode([
          {...snapshot}..remove('updatedAt'),
          connection,
          _foreground,
        ]);
        final now = DateTime.now();
        if (digest == _lastDigest &&
            _lastPublished != null &&
            now.difference(_lastPublished!) < const Duration(seconds: 10)) {
          continue;
        }
        await channel.invokeMethod('sync', {
          'snapshot': snapshot,
          'connection': connection,
          'foreground': _foreground,
          'pushEnabled': registrationPath.isNotEmpty,
        });
        _lastDigest = digest;
        _lastPublished = now;
        _stopped = false;
      } on PlatformException {
        message = '后台牌桌暂不可用，回到游戏可重新同步';
        _notify();
      } on MissingPluginException {
        supported = false;
        _notify();
      }
    }
    _sending = false;
  }

  Json? takeOpen() {
    final value = pendingOpen;
    pendingOpen = null;
    return value;
  }

  Future<void> _registerPush(Json token) async {
    final session = app.session, account = app.account;
    if (registrationPath.isEmpty ||
        !prefs.liveTable ||
        session == null ||
        account == null ||
        token['roomId'] != session.id ||
        token['round'] != app.room?.round ||
        '${token['activityId'] ?? ''}'.isEmpty ||
        '${token['pushToken'] ?? ''}'.isEmpty ||
        !allowed) {
      return;
    }
    final path = registrationPath.replaceAll(
      '{roomId}',
      Uri.encodeComponent(session.id),
    );
    final uri = Uri.tryParse(path);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        path.startsWith('/') ||
        uri.pathSegments.contains('..')) {
      return;
    }
    try {
      await app.api.post(path, {
        'activity_id': token['activityId'],
        'push_token': token['pushToken'],
        'attributes_type': 'UnourTableAttributes',
        'round': token['round'],
      }, session.token);
      if (!_disposed &&
          prefs.liveTable &&
          app.account?.id == account.id &&
          app.session?.token == session.token) {
        realtime = true;
        message = '';
        _notify();
      }
    } on Object {
      realtime = false;
      message = '后台推送未连接，将显示最近同步的牌况';
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    app.removeListener(_schedule);
    prefs.removeListener(_schedule);
    channel.setMethodCallHandler(null);
    super.dispose();
  }
}
