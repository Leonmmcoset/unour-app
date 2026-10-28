import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api.dart';
import 'feedback.dart';
import 'models.dart';
import 'preferences.dart';

final appProvider = ChangeNotifierProvider<AppController>((ref) => throw UnimplementedError());
final preferencesProvider = ChangeNotifierProvider<GamePreferences>((ref) => throw UnimplementedError());

bool acceptsSnapshot(Room? current, Room next) => current == null || current.id != next.id ||
  (next.revision >= current.revision && next.version >= current.version);

class AppController extends ChangeNotifier {
  final Api api;
  final GameFeedback feedback;
  Account? account;
  Room? room;
  RoomSession? session;
  List<RoomSession> recent = [];
  bool loading = true, busy = false, syncing = false, online = true, roomUnavailable = false;
  String? error, notice;
  bool _active = true, _disposed = false, _reading = false, _unoSending = false;
  int _epoch = 0, _failures = 0, _window = 0;
  Timer? _poll, _unoTimer, _countdown;
  DateTime? _observedUno;
  final Map<String, int> _declared = {}, _penalized = {};
  AppController(this.api, this.feedback);
  String roomPath(String suffix) => 'rooms/${Uri.encodeComponent(session!.id)}${suffix.isEmpty ? '' : '/$suffix'}';
  double get unoProgress => _observedUno == null ? 0 : (1 - DateTime.now().difference(_observedUno!).inMilliseconds / 2000).clamp(0.0, 1.0);
  bool get unoAvailable => _window != 0 && room?.me?.uno['id'] == _window && !_unoSending;
  bool get unoSending => _unoSending;
  void changed() { if (!_disposed) notifyListeners(); }
  void clearError() { error = null; notice = null; changed(); }

  Future<void> initialize() async {
    try {
      await api.restore();
      account = Account.fromJson(object((await api.get('account'))['user']));
      api.accountId = account!.id;
      await _loadRecent();
    } on ApiFailure catch (e) {
      if (e.status != 401) error = e.message;
    } catch (_) { error = '无法读取安全存储，请检查设备设置后重试'; }
    loading = false; changed();
  }
  Future<void> _loadRecent() async {
    final saved = await api.storage.read(key: 'rooms_${account!.id}');
    try { recent = saved == null ? [] : (jsonDecode(saved) as List).map((v) => RoomSession.fromJson(object(v))).toList(); }
    catch (_) { recent = []; }
  }
  Future<void> _saveRecent() async {
    if (account != null) await api.storage.write(key: 'rooms_${account!.id}', value: jsonEncode(recent.map((s) => s.toJson()).toList()));
  }
  Future<bool> task(Future<void> Function() work) async {
    if (busy) return false;
    busy = true; error = null; notice = null; changed();
    try { await work(); return true; }
    on ApiFailure catch (e) { error = e.message; return false; }
    catch (_) { error = '操作未完成，请重试'; return false; }
    finally { busy = false; changed(); }
  }
  Future<bool> authenticate(String username, String password, bool register) => task(() async {
    api.accountId = null;
    final response = await api.post('auth/${register ? 'register' : 'login'}', {'username': username.trim(), 'password': password});
    account = Account.fromJson(object(response['user'])); api.accountId = account!.id;
    await _loadRecent();
  });
  Future<bool> logout() => task(() async {
    await api.post('auth/logout');
    closeTable(); await api.clearCookies(); account = null; recent = [];
  });
  Future<bool> uploadAvatar(List<int> bytes, String type) => task(() async {
    final data = await api.request('account/avatar', method: 'PUT', data: Stream.value(bytes), contentType: type);
    account = Account.fromJson(object(object(data)['user']));
  });
  Future<bool> resetAvatar() => task(() async {
    final data = await api.request('account/avatar', method: 'DELETE');
    account = Account.fromJson(object(object(data)['user']));
  });
  Future<void> _remember(RoomSession value) async {
    recent.removeWhere((s) => s.id == value.id); recent.insert(0, value);
    if (recent.length > 20) recent.removeRange(20, recent.length);
    await _saveRecent();
  }
  Future<bool> forget(String id) => task(() async { recent.removeWhere((s) => s.id == id); await _saveRecent(); });

  Future<bool> enter({String? id, bool spectate = false, bool solo = false, int botCount = 2, String difficulty = 'normal', List<Json>? rules, String? catalogRevision}) => task(() async {
    Json result;
    final config = {if (rules != null) 'rules': rules, if (rules != null && catalogRevision != null) 'catalog_revision': catalogRevision};
    if (solo) {
      result = await api.post('solo', {'bot_count': botCount, 'difficulty': difficulty, ...config});
    } else {
      var roomId = id?.trim() ?? '';
      if (roomId.isEmpty) {
        final created = await api.post('rooms', config);
        roomId = '${created['id'] ?? object(created['room'])['id'] ?? ''}';
        if (roomId.isEmpty) throw const ApiFailure('invalid_room', '创建房间的响应缺少房间号');
      }
      result = await api.post('rooms/${Uri.encodeComponent(roomId)}/${spectate ? 'spectators' : 'players'}');
    }
    final nextRoom = Room(object(result['room']));
    if (nextRoom.id.isEmpty || result['token'] == null) throw const ApiFailure('invalid_room', '无法识别房间数据，请重试加入');
    closeTable();
    session = RoomSession(id: nextRoom.id, playerId: '${result['player_id']}', token: '${result['token']}');
    await _remember(session!);
    roomUnavailable = false; _failures = 0; online = true;
    _accept(nextRoom, baseline: true);
    feedback.play('deal'); _schedule();
  });

  void _accept(Room next, {bool baseline = false}) {
    if (!acceptsSnapshot(room, next)) return;
    final previous = room;
    room = next;
    if (baseline || previous?.round != next.round) { _declared.clear(); _penalized.clear(); }
    for (final p in next.players) {
      if (!baseline && p.declared > (_declared[p.id] ?? 0)) { notice = '${p.name}：UNO!'; feedback.play('uno'); }
      if (!baseline && p.penalized > (_penalized[p.id] ?? 0)) notice = '${p.name} 漏喊 UNO，罚摸一张';
      _declared[p.id] = p.declared; _penalized[p.id] = p.penalized;
    }
    if (!baseline && previous != null) {
      if (next.phase == 'finished' && previous.phase != 'finished') feedback.play('win');
      else if (next.turn == next.you && previous.turn != next.you) feedback.play('turn');
      else if (next.topCard?.id != previous.topCard?.id) feedback.play('play', vibrate: false);
    }
    _syncUno(); changed();
  }
  void _schedule() {
    _poll?.cancel();
    if (!_active || session == null || roomUnavailable || account == null) return;
    final delay = _failures > 0 ? Duration(seconds: (1 << _failures.clamp(0, 4))) :
      Duration(milliseconds: room?.phase == 'playing' ? 500 : 1000);
    _poll = Timer(delay, () async { await refresh(); _schedule(); });
  }
  Future<void> refresh() async {
    if (_reading || session == null || !_active || roomUnavailable) return;
    final epoch = _epoch, currentSession = session!;
    _reading = true; syncing = true;
    try {
      final result = await api.get(roomPath(''), token: currentSession.token);
      if (epoch != _epoch) return;
      _failures = 0; online = true; _accept(Room(result));
    } on ApiFailure catch (e) {
      if (epoch != _epoch) return;
      _failures++; online = false;
      if (e.status == 404) {
        roomUnavailable = true; error = '这个房间已解散或不存在了';
        recent.removeWhere((s) => s.id == currentSession.id); await _saveRecent();
      } else if (e.status == 401) {
        _poll?.cancel(); _unoTimer?.cancel(); roomUnavailable = true;
        try {
          await api.get('account');
          error = '房间凭证已失效，请返回首页重新加入以恢复座位';
        } on ApiFailure catch (authError) {
          if (authError.status == 401) { closeTable(); account = null; api.accountId = null; error = '登录已过期，请重新登录'; }
          else { roomUnavailable = false; error = authError.message; }
        }
      }
    } catch (_) { if (epoch == _epoch) { online = false; _failures++; } }
    finally { _reading = false; syncing = false; changed(); }
  }
  Future<bool> action(String action, [Json payload = const {}]) async {
    if (session == null || room == null || roomUnavailable || !online) return false;
    final epoch = _epoch, current = room!, token = session!.token;
    return task(() async {
      try {
        final response = await api.post(roomPath(action), {
          ...payload,
          if (!['participation', 'rematch'].contains(action)) 'expected_version': current.version,
        }, token);
        if (epoch != _epoch) return;
        final value = response['room'] is Map ? object(response['room']) : response;
        _accept(Room(value));
      } on ApiFailure catch (e) {
        await refresh();
        if (e.code == 'version_conflict') throw const ApiFailure('version_conflict', '牌桌刚刚有了变化，请看清最新状态后再操作', 409);
        if (e.code == 'roster_changed') throw const ApiFailure('roster_changed', '参赛名单已变化，请查看新名单后重新同意', 409);
        rethrow;
      }
    });
  }
  Future<bool> exitRoom({bool dissolve = false}) => task(() async {
    if (session == null) return;
    final id = session!.id;
    if (!roomUnavailable) {
      if (dissolve) { await api.request(roomPath(''), method: 'DELETE', token: session!.token); }
      else { await api.post(roomPath('leave'), {}, session!.token); }
    }
    closeTable(); recent.removeWhere((s) => s.id == id); await _saveRecent();
  });

  void _syncUno() {
    final id = integer(room?.me?.uno['id']);
    if (id == 0 || room?.isSpectator == true) { _cancelUno(); return; }
    if (!_active || roomUnavailable) return;
    if (_window == id && _unoTimer != null) return;
    _cancelUno(); _window = id; _observedUno = DateTime.now();
    _countdown = Timer.periodic(const Duration(milliseconds: 100), (_) => changed());
    _unoTimer = Timer(const Duration(milliseconds: 2100), () => _penalize(id));
  }
  Future<void> declareUno() async {
    if (!unoAvailable || session == null) return;
    _unoSending = true; final id = _window, epoch = _epoch; changed();
    try {
      final result = await api.post(roomPath('uno'), {'window_id': id}, session!.token);
      if (epoch == _epoch) { _accept(Room(object(result['room']))); notice = 'UNO！喊到了'; }
    } on ApiFailure catch (e) { if (epoch == _epoch) { error = e.message; await refresh(); } }
    finally { _unoSending = false; changed(); }
  }
  Future<void> _penalize(int id) async {
    if (!_active || session == null || _window != id || roomUnavailable) return;
    final epoch = _epoch;
    try {
      final result = await api.post(roomPath('uno-penalty'), {'window_id': id}, session!.token);
      if (epoch == _epoch) _accept(Room(object(result['room'])));
    } on ApiFailure catch (e) {
      if (epoch != _epoch) return;
      if (e.code == 'uno_too_early' || e.uncertain || e.status == 503) {
        _unoTimer = Timer(const Duration(milliseconds: 700), () => _penalize(id));
      } else { await refresh(); }
    }
  }
  void _cancelUno() {
    _unoTimer?.cancel(); _countdown?.cancel(); _unoTimer = null; _countdown = null; _window = 0; _observedUno = null;
  }
  void setActive(bool value) {
    _active = value; _poll?.cancel(); _cancelUno();
    if (value) { refresh().then((_) { _syncUno(); _schedule(); }); }
  }
  void closeTable() {
    _epoch++; _poll?.cancel(); _cancelUno(); room = null; session = null;
    roomUnavailable = false; _declared.clear(); _penalized.clear(); changed();
  }
  @override
  void dispose() { _disposed = true; _poll?.cancel(); _cancelUno(); feedback.dispose(); super.dispose(); }
}
