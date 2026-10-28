typedef Json = Map<String, dynamic>;

Json object(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Json> objects(dynamic value) =>
    value is List ? value.map(object).toList() : [];
int integer(dynamic value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

class Account {
  final String id, username, avatarUrl;
  const Account({
    required this.id,
    required this.username,
    this.avatarUrl = '',
  });
  factory Account.fromJson(Json json) => Account(
    id: '${json['id'] ?? ''}',
    username: '${json['username'] ?? ''}',
    avatarUrl: '${json['avatar_url'] ?? ''}',
  );
}

class UnoCard {
  final int id, number;
  final String color, kind;
  const UnoCard({
    required this.id,
    required this.color,
    required this.kind,
    this.number = 0,
  });
  factory UnoCard.fromJson(Json j) => UnoCard(
    id: integer(j['id']),
    color: '${j['color']}',
    kind: '${j['kind']}',
    number: integer(j['number']),
  );
  bool get isWild => kind == 'wild' || kind == 'wild_draw_four';
  String get symbol => switch (kind) {
    'number' => '$number',
    'skip' => '⊘',
    'reverse' => '⇄',
    'draw_two' => '+2',
    'wild_draw_four' => '+4',
    'wild' => '✦',
    _ => '?',
  };
  String get label =>
      '${switch (color) {
        'red' => '红色',
        'blue' => '蓝色',
        'green' => '绿色',
        'yellow' => '黄色',
        _ => '万能',
      }}${switch (kind) {
        'number' => '$number',
        'skip' => '跳过',
        'reverse' => '反转',
        'draw_two' => '加二',
        'wild_draw_four' => '加四',
        'wild' => '换色',
        _ => kind,
      }}';
}

class Player {
  final String id, name;
  final int handCount;
  final bool eliminated;
  final List<UnoCard> hand;
  final Json uno;
  final int declared, penalized;
  Player.fromJson(Json j)
    : id = '${j['id']}',
      name = '${j['name']}',
      handCount = integer(j['hand_count']),
      eliminated = j['eliminated'] == true,
      hand = objects(j['hand']).map(UnoCard.fromJson).toList(),
      uno = object(j['uno']),
      declared = integer(j['uno_declared']),
      penalized = integer(j['uno_penalized']);
}

class Room {
  final Json raw, state;
  Room(this.raw) : state = object(raw['state']);
  String get id => '${raw['id'] ?? ''}';
  String get host => '${raw['host_id'] ?? ''}';
  String get role => '${raw['role'] ?? 'player'}';
  String get phase => '${state['phase'] ?? 'lobby'}';
  String get you => '${state['you'] ?? ''}';
  String get turn => '${state['turn'] ?? ''}';
  String get activeColor => '${state['active_color'] ?? 'wild'}';
  int get revision => integer(raw['revision']);
  int get version => integer(state['version']);
  int get round => integer(raw['round'], 1);
  int get rosterVersion => integer(raw['roster_version']);
  List<Player> get players =>
      objects(state['players']).map(Player.fromJson).toList();
  List<Json> get spectators => objects(raw['spectators']);
  List<Json> get actions => objects(state['legal_actions']);
  Player? get me => players.where((p) => p.id == you).firstOrNull;
  UnoCard? get topCard => state['top_card'] is Map
      ? UnoCard.fromJson(object(state['top_card']))
      : null;
  bool get isHost => host == you;
  bool get isSpectator => role == 'spectator';
  List<String> get votes =>
      (raw['rematch_votes'] as List? ?? []).map((v) => '$v').toList();
  List<String> get departed =>
      (raw['departed'] as List? ?? []).map((v) => '$v').toList();
  bool allows(String action) =>
      !isSpectator && actions.any((a) => a['action'] == action);
  List<Json> plays(UnoCard card) => actions
      .where((a) => a['action'] == 'play' && a['card_id'] == card.id)
      .toList();
  String playerName(String id) =>
      players.where((p) => p.id == id).firstOrNull?.name ?? '玩家';
}

class RoomSession {
  final String id, playerId, token;
  const RoomSession({
    required this.id,
    required this.playerId,
    required this.token,
  });
  factory RoomSession.fromJson(Json j) => RoomSession(
    id: '${j['id']}',
    playerId: '${j['player_id']}',
    token: '${j['token']}',
  );
  Json toJson() => {'id': id, 'player_id': playerId, 'token': token};
}

class RuleModule {
  final Json raw;
  RuleModule(this.raw);
  String get name => '${raw['name']}';
  String get title => '${raw['title'] ?? name}';
  bool get required => raw['required'] == true;
  bool get defaultEnabled => raw['default_enabled'] == true;
  List<Json> get options => objects(raw['options']);
  bool get supported =>
      options.every(
        (o) => ['boolean', 'integer', 'select'].contains(o['type']),
      ) &&
      objects(raw['constraints']).every((c) => c['kind'] == 'at_least_one');
}

class RuleSelection {
  final RuleModule module;
  bool enabled;
  final Json values;
  RuleSelection(this.module)
    : enabled = module.required || module.defaultEnabled,
      values = {for (final o in module.options) '${o['key']}': o['default']};
  bool available(Json option) => objects(
    option['depends_on'],
  ).every((d) => values[d['key']] == d['equals']);
  String? get error {
    if (!enabled) return null;
    if (!module.supported) return '规则「${module.title}」需要更新客户端后配置';
    for (final c in objects(module.raw['constraints'])) {
      if (c['kind'] == 'at_least_one' &&
          !(c['fields'] as List).any((key) => values[key] == true)) {
        return '${c['message'] ?? '请至少启用一个选项'}';
      }
    }
    for (final o in module.options.where(available)) {
      final v = values[o['key']];
      if (o['type'] == 'integer' &&
          (v is! int ||
              v < integer(o['min']) ||
              v > integer(o['max'], 999999))) {
        return '${o['label']}超出允许范围';
      }
      if (o['type'] == 'select' &&
          !objects(o['choices']).any((c) => c['value'] == v)) {
        return '${o['label']}选项无效';
      }
    }
    return null;
  }

  Json toJson() => {
    'name': module.name,
    if (module.raw['version'] != null) 'version': module.raw['version'],
    'options': {
      for (final o in module.options)
        '${o['key']}': available(o) ? values[o['key']] : o['default'],
    },
  };
}
