import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// A deliberately small public view. Never persist a room response, hand,
/// profile, session, legal action, or authentication data in match history.
class RecordedPlayer {
  final String id, name;
  final int count, declared, penalized;
  final bool eliminated, departed;

  const RecordedPlayer({
    required this.id,
    required this.name,
    required this.count,
    this.declared = 0,
    this.penalized = 0,
    this.eliminated = false,
    this.departed = false,
  });

  factory RecordedPlayer.fromJson(Json json) => RecordedPlayer(
    id: '${json['id'] ?? ''}',
    name: '${json['name'] ?? '玩家'}',
    count: integer(json['count']),
    declared: integer(json['declared']),
    penalized: integer(json['penalized']),
    eliminated: json['eliminated'] == true,
    departed: json['departed'] == true,
  );

  Json toJson() => {
    'id': id,
    'name': name,
    'count': count,
    if (declared > 0) 'declared': declared,
    if (penalized > 0) 'penalized': penalized,
    if (eliminated) 'eliminated': true,
    if (departed) 'departed': true,
  };
}

class MatchFrame {
  final DateTime at;
  final int version, direction, pendingDraw;
  final String phase, turn, winner, activeColor;
  final UnoCard? topCard;
  final List<RecordedPlayer> players;
  final bool gapBefore;

  const MatchFrame({
    required this.at,
    required this.version,
    required this.phase,
    required this.turn,
    required this.winner,
    required this.activeColor,
    required this.direction,
    required this.pendingDraw,
    required this.players,
    this.topCard,
    this.gapBefore = false,
  });

  factory MatchFrame.fromRoom(Room room, DateTime at, {bool gap = false}) =>
      MatchFrame(
        at: at,
        version: room.version,
        phase: room.phase,
        turn: room.turn,
        winner: '${room.state['winner'] ?? ''}',
        activeColor: room.activeColor,
        direction: integer(room.state['direction'], 1),
        pendingDraw: integer(room.state['pending_draw']),
        topCard: room.topCard,
        gapBefore: gap,
        players: [
          for (final p in room.players)
            RecordedPlayer(
              id: p.id,
              name: String.fromCharCodes(p.name.runes.take(24)),
              count: p.handCount,
              declared: p.declared,
              penalized: p.penalized,
              eliminated: p.eliminated,
              departed: room.departed.contains(p.id),
            ),
        ],
      );

  factory MatchFrame.fromJson(Json json) {
    final time = DateTime.tryParse('${json['at']}');
    if (time == null || !['playing', 'finished'].contains(json['phase'])) {
      throw const FormatException('Invalid match observation');
    }
    return MatchFrame(
      at: time,
      version: integer(json['version']),
      phase: '${json['phase']}',
      turn: '${json['turn'] ?? ''}',
      winner: '${json['winner'] ?? ''}',
      activeColor: '${json['color'] ?? 'wild'}',
      direction: integer(json['direction'], 1),
      pendingDraw: integer(json['pending']),
      topCard: json['card'] is Map
          ? UnoCard.fromJson(object(json['card']))
          : null,
      players: objects(json['players']).map(RecordedPlayer.fromJson).toList(),
      gapBefore: json['gap'] == true,
    );
  }

  RecordedPlayer? player(String id) =>
      players.where((p) => p.id == id).firstOrNull;
  String playerName(String id) => player(id)?.name ?? '玩家';

  Json toJson() => {
    'at': at.toUtc().toIso8601String(),
    'version': version,
    'phase': phase,
    'turn': turn,
    'winner': winner,
    'color': activeColor,
    'direction': direction,
    'pending': pendingDraw,
    if (topCard case final card?)
      'card': {
        'id': card.id,
        'color': card.color,
        'kind': card.kind,
        'number': card.number,
      },
    'players': players.map((p) => p.toJson()).toList(),
    if (gapBefore) 'gap': true,
  };

  String get signature => jsonEncode(
    toJson()
      ..remove('at')
      ..remove('gap'),
  );

  MatchFrame withGap() => MatchFrame(
    at: at,
    version: version,
    phase: phase,
    turn: turn,
    winner: winner,
    activeColor: activeColor,
    direction: direction,
    pendingDraw: pendingDraw,
    players: players,
    topCard: topCard,
    gapBefore: true,
  );
}

class MatchRecord {
  final String id, roomId, myId;
  final int round;
  final DateTime startedAt;
  final bool hasBots;
  final List<MatchFrame> _frames;
  DateTime? endedAt;
  int omittedFrames, peakPendingDraw, lowestHandCount, observedUno;

  MatchRecord({
    required this.id,
    required this.roomId,
    required this.myId,
    required this.round,
    required this.startedAt,
    required this.hasBots,
    required List<MatchFrame> frames,
    this.endedAt,
    this.omittedFrames = 0,
    this.peakPendingDraw = 0,
    required this.lowestHandCount,
    this.observedUno = 0,
  }) : _frames = frames;

  factory MatchRecord.fromJson(Json json) {
    final frames = objects(json['frames']).map(MatchFrame.fromJson).toList();
    final start = DateTime.tryParse('${json['started']}');
    if (frames.isEmpty || start == null || '${json['id'] ?? ''}'.isEmpty) {
      throw const FormatException('Invalid match record');
    }
    return MatchRecord(
      id: '${json['id']}',
      roomId: '${json['room'] ?? ''}',
      myId: '${json['me'] ?? ''}',
      round: integer(json['round'], 1),
      startedAt: start,
      hasBots: json['bots'] == true,
      frames: frames,
      endedAt: DateTime.tryParse('${json['ended']}'),
      omittedFrames: integer(json['omitted']),
      peakPendingDraw: integer(json['peak_pending']),
      lowestHandCount: integer(json['lowest_hand']),
      observedUno: integer(json['uno']),
    );
  }

  List<MatchFrame> get frames => List.unmodifiable(_frames);
  MatchFrame get latest => _frames.last;
  bool get finished => endedAt != null && latest.phase == 'finished';
  bool get won => finished && latest.winner == myId;
  String get resultLabel => !finished
      ? '未结算'
      : won
      ? '获胜'
      : latest.winner.isEmpty
      ? '无胜者'
      : '未获胜';

  Json toJson() => {
    'id': id,
    'room': roomId,
    'me': myId,
    'round': round,
    'started': startedAt.toUtc().toIso8601String(),
    if (endedAt != null) 'ended': endedAt!.toUtc().toIso8601String(),
    'bots': hasBots,
    'omitted': omittedFrames,
    'peak_pending': peakPendingDraw,
    'lowest_hand': lowestHandCount,
    'uno': observedUno,
    'frames': _frames.map((f) => f.toJson()).toList(),
  };
}

/// Results are authoritative; observations are explicitly incomplete. No game
/// rules or inferred moves are used to determine winners, draws, or penalties.
class MatchHistory extends ChangeNotifier {
  static const maxRecords = 40, maxFrames = 96;
  static const _maxBytes = 2 * 1024 * 1024;
  final SharedPreferences store;
  final DateTime Function() now;
  final List<MatchRecord> _records = [];
  final Set<String> _interrupted = {}, _ignored = {};
  String? _accountId;
  String? storageError;
  Timer? _saveTimer;
  Future<void> _writes = Future.value();
  bool _disposed = false;

  MatchHistory(this.store, {DateTime Function()? now})
    : now = now ?? DateTime.now;

  static String storageKey(String id) =>
      'unour.match_history.v1.${Uri.encodeComponent(id)}';
  static String identity(Room room) => base64Url
      .encode(
        utf8.encode(
          jsonEncode([room.id, room.raw['created_at'], room.round, room.you]),
        ),
      )
      .replaceAll('=', '');

  List<MatchRecord> get records => List.unmodifiable(_records);
  int get completed => _records.where((r) => r.finished).length;
  int get wins => _records.where((r) => r.won).length;
  int get unsettled => _records.where((r) => !r.finished).length;
  int? get winRate => completed == 0 ? null : (100 * wins / completed).round();
  MatchRecord? find(String id) => _records.where((r) => r.id == id).firstOrNull;
  MatchRecord? forRoom(Room room) => find(identity(room));

  void selectAccount(String? id) {
    if (_accountId == id) return;
    unawaited(flush());
    _accountId = id;
    _records.clear();
    _interrupted.clear();
    _ignored.clear();
    storageError = null;
    if (id != null) {
      final saved = store.getString(storageKey(id));
      if (saved != null) {
        try {
          final data = object(jsonDecode(saved));
          if (data['schema'] != 1 || data['records'] is! List) {
            throw const FormatException('Unknown history schema');
          }
          for (final row in objects(data['records'])) {
            try {
              final record = MatchRecord.fromJson(row);
              if (find(record.id) == null) _records.add(record);
            } on Object {
              storageError = '部分本机记录无法读取，其余记录仍可查看';
            }
          }
          _ignored.addAll(
            (data['ignored'] as List? ?? []).whereType<String>().take(100),
          );
          if (_records.length > maxRecords) {
            _records.removeRange(maxRecords, _records.length);
          }
          _interrupted.addAll(
            _records.where((r) => !r.finished).map((r) => r.id),
          );
        } on Object {
          storageError = '无法读取本机记录，新对局仍可继续记录';
        }
      }
    }
    _notify();
  }

  void observe(Room room, RoomSession? session) {
    if (_accountId == null ||
        session?.id != room.id ||
        session?.playerId != room.you ||
        room.me == null ||
        room.isSpectator ||
        !['playing', 'finished'].contains(room.phase)) {
      return;
    }
    final id = identity(room);
    if (_ignored.contains(id)) return;
    var record = find(id);
    // Opening an old result or spectating never manufactures a played match.
    if (record == null && room.phase != 'playing') return;
    final at = now();
    final frame = MatchFrame.fromRoom(room, at);
    if (record == null) {
      record = MatchRecord(
        id: id,
        roomId: room.id,
        myId: room.you,
        round: room.round,
        startedAt: at,
        hasBots: object(room.raw['bots']).isNotEmpty,
        frames: [frame],
        lowestHandCount: room.me!.handCount,
        peakPendingDraw: frame.pendingDraw,
      );
      _records.insert(0, record);
    } else {
      final previous = record.latest;
      if (record.finished || frame.version < previous.version) return;
      if (frame.signature == previous.signature) {
        _interrupted.remove(id);
        return;
      }
      final gap =
          _interrupted.remove(id) || frame.version > previous.version + 1;
      record._frames.add(gap ? frame.withGap() : frame);
      final declared = frame.player(record.myId)?.declared ?? 0;
      if (declared > (previous.player(record.myId)?.declared ?? 0)) {
        // A window ID is an identifier, not a count of declarations.
        record.observedUno++;
      }
      record.peakPendingDraw = frame.pendingDraw > record.peakPendingDraw
          ? frame.pendingDraw
          : record.peakPendingDraw;
      final count = frame.player(record.myId)!.count;
      if (count < record.lowestHandCount) record.lowestHandCount = count;
      if (frame.phase == 'finished') record.endedAt = at;
      if (record._frames.length > maxFrames) {
        record._frames.removeAt(1);
        record._frames[1] = record._frames[1].withGap();
        record.omittedFrames++;
      }
      _records.remove(record);
      _records.insert(0, record);
    }
    if (_records.length > maxRecords) {
      _records.removeRange(maxRecords, _records.length);
    }
    _notify();
    if (record.finished) {
      unawaited(flush());
    } else {
      _saveTimer ??= Timer(const Duration(milliseconds: 700), () {
        unawaited(flush());
      });
    }
  }

  void interrupt() {
    _interrupted.addAll(_records.where((r) => !r.finished).map((r) => r.id));
    unawaited(flush());
  }

  Future<void> clear() {
    _ignored.addAll(_records.where((r) => !r.finished).map((r) => r.id));
    if (_ignored.length > 100) {
      _ignored.removeAll(_ignored.take(_ignored.length - 100).toList());
    }
    _records.clear();
    _interrupted.clear();
    storageError = null;
    _notify();
    return flush();
  }

  Future<void> flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    final account = _accountId;
    if (account == null) return _writes;
    String encode() => jsonEncode({
      'schema': 1,
      'records': _records.map((r) => r.toJson()).toList(),
      'ignored': _ignored.toList(),
    });
    var payload = encode();
    while (_records.length > 1 && utf8.encode(payload).length > _maxBytes) {
      _records.removeLast();
      payload = encode();
    }
    _writes = _writes.then((_) async {
      try {
        if (!await store.setString(storageKey(account), payload)) {
          throw StateError('History write failed');
        }
        if (_accountId == account &&
            !_disposed &&
            storageError == '本机记录暂未保存，稍后可重试') {
          storageError = null;
          _notify();
        }
      } on Object {
        if (_accountId == account && !_disposed) {
          storageError = '本机记录暂未保存，稍后可重试';
          _notify();
        }
      }
    });
    return _writes;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(flush());
    super.dispose();
  }
}
