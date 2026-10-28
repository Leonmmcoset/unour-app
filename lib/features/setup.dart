import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/controller.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../game/design.dart';
import '../game/motion.dart';

class SetupPage extends ConsumerStatefulWidget {
  final String mode;
  const SetupPage({super.key, required this.mode});
  @override
  ConsumerState<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends ConsumerState<SetupPage> {
  final _code = TextEditingController();
  List<RuleSelection> _rules = [];
  String? _catalogRevision, _catalogError;
  bool _loading = false, _custom = false, _spectate = false;
  int _bots = 2;
  String _difficulty = 'normal';
  @override
  void initState() {
    super.initState();
    if (widget.mode != 'join') _loadRules();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _loadRules() async {
    setState(() {
      _loading = true;
      _catalogError = null;
    });
    try {
      final data = await ref.read(appProvider).api.get('rules');
      if (!mounted) return;
      setState(() {
        _rules = objects(
          data['modules'],
        ).map((r) => RuleSelection(RuleModule(r))).toList();
        _catalogRevision = '${data['revision']}';
      });
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _catalogError = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (widget.mode == 'join' && _code.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入朋友分享的房间号')));
      return;
    }
    if (_custom) {
      final problem = _rules
          .map((r) => r.error)
          .whereType<String>()
          .firstOrNull;
      if (_rules.isEmpty || problem != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(problem ?? '请先加载规则目录')));
        return;
      }
    }
    final app = ref.read(appProvider);
    final ok = await app.enter(
      id: widget.mode == 'join' ? _code.text : null,
      solo: widget.mode == 'solo',
      spectate: _spectate,
      botCount: _bots,
      difficulty: _difficulty,
      rules: _custom
          ? _rules.where((r) => r.enabled).map((r) => r.toJson()).toList()
          : null,
      catalogRevision: _catalogRevision,
    );
    if (ok && mounted) context.go('/room');
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final solo = widget.mode == 'solo', join = widget.mode == 'join';
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          join
              ? '加入牌桌'
              : solo
              ? '人机对战'
              : '创建牌桌',
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                MotionEntrance(
                  child: GamePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colors.primaryContainer,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Icon(
                                join
                                    ? Icons.meeting_room_outlined
                                    : solo
                                    ? Icons.smart_toy_outlined
                                    : Icons.celebration_outlined,
                                color: colors.primary,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                join
                                    ? '房间号'
                                    : solo
                                    ? '电脑人数'
                                    : '邀请朋友入座',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            if (solo)
                              MotionSwitcher(
                                child: Text(
                                  '$_bots',
                                  key: ValueKey(_bots),
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(color: colors.primary),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        if (join) ...[
                          TextField(
                            controller: _code,
                            enabled: !app.busy,
                            decoration: const InputDecoration(
                              labelText: '房间号',
                              hintText: '粘贴朋友发来的房间号',
                            ),
                            onSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('我先观战'),
                            subtitle: const Text('也可以预约下一局'),
                            value: _spectate,
                            onChanged: app.busy
                                ? null
                                : (v) => setState(() => _spectate = v),
                          ),
                        ] else if (solo) ...[
                          Slider(
                            value: _bots.toDouble(),
                            min: 1,
                            max: 9,
                            divisions: 8,
                            label: '$_bots 位',
                            onChanged: app.busy
                                ? null
                                : (v) => setState(() => _bots = v.round()),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('1 位', style: theme.textTheme.labelSmall),
                                Text('9 位', style: theme.textTheme.labelSmall),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          DropdownButtonFormField<String>(
                            initialValue: _difficulty,
                            decoration: const InputDecoration(
                              labelText: '对手难度',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'easy',
                                child: Text('简单'),
                              ),
                              DropdownMenuItem(
                                value: 'normal',
                                child: Text('标准'),
                              ),
                              DropdownMenuItem(
                                value: 'hard',
                                child: Text('困难'),
                              ),
                              DropdownMenuItem(
                                value: 'expert',
                                child: Text('专家'),
                              ),
                            ],
                            onChanged: app.busy
                                ? null
                                : (v) => setState(() => _difficulty = v!),
                          ),
                        ] else
                          Text(
                            '创建后分享房间号，至少两人即可发牌。',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!join) ...[
                  const SizedBox(height: 16),
                  MotionEntrance(
                    delay: 100,
                    child: GamePanel(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Column(
                        children: [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('自定义规则'),
                            subtitle: const Text('叠加、反转、手牌上限等'),
                            value: _custom,
                            onChanged: app.busy
                                ? null
                                : (v) => setState(() => _custom = v),
                          ),
                          if (_custom) ...[
                            const Divider(),
                            if (_loading) const LinearProgressIndicator(),
                            if (_catalogError != null) ...[
                              ErrorStrip(_catalogError),
                              TextButton(
                                onPressed: _loadRules,
                                child: const Text('重新加载规则'),
                              ),
                            ],
                            for (final rule in _rules)
                              RuleEditor(
                                rule: rule,
                                locked: app.busy,
                                onChanged: () => setState(() {}),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                ErrorStrip(app.error, onDismiss: app.clearError),
                PressScale(
                  child: FilledButton.icon(
                    onPressed:
                        app.busy ||
                            (_custom && (_loading || _catalogError != null))
                        ? null
                        : _submit,
                    icon: app.busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text(
                      app.busy
                          ? '正在准备牌桌…'
                          : join
                          ? (_spectate ? '观战' : '加入牌桌')
                          : solo
                          ? '发牌！'
                          : '创建牌桌',
                    ),
                  ),
                ),
                if (app.busy)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '若结果不确定，可通过最近房间或房间号恢复。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RuleEditor extends StatelessWidget {
  final RuleSelection rule;
  final bool locked;
  final VoidCallback onChanged;
  const RuleEditor({
    super.key,
    required this.rule,
    required this.locked,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 6),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          SwitchListTile(
            title: Text(rule.module.title),
            subtitle: Text('${rule.module.raw['description'] ?? ''}'),
            value: rule.enabled,
            onChanged: locked || rule.module.required
                ? null
                : (v) {
                    rule.enabled = v;
                    onChanged();
                  },
          ),
          if (rule.enabled) ...[
            if (!rule.module.supported)
              const ListTile(
                leading: Icon(Icons.update),
                title: Text('此规则包含暂不支持的选项，请更新客户端或关闭此规则。'),
              ),
            for (final option in rule.module.options) _option(context, option),
            if (rule.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ErrorStrip(rule.error),
              ),
          ],
        ],
      ),
    ),
  );
  Widget _option(BuildContext context, Json option) {
    final key = '${option['key']}',
        available = rule.available(option) && !locked;
    final title = '${option['label'] ?? key}';
    switch (option['type']) {
      case 'boolean':
        return SwitchListTile(
          title: Text(title),
          subtitle: option['description'] == null
              ? null
              : Text('${option['description']}'),
          value: available
              ? rule.values[key] == true
              : option['default'] == true,
          onChanged: available
              ? (v) {
                  rule.values[key] = v;
                  onChanged();
                }
              : null,
        );
      case 'select':
        return Padding(
          padding: const EdgeInsets.all(16),
          child: DropdownButtonFormField<dynamic>(
            key: ValueKey('${rule.module.name}_$key'),
            initialValue: rule.values[key],
            isExpanded: true,
            decoration: InputDecoration(labelText: title),
            items: objects(option['choices'])
                .map(
                  (c) => DropdownMenuItem<dynamic>(
                    value: c['value'],
                    child: Text('${c['label']}'),
                  ),
                )
                .toList(),
            onChanged: available
                ? (v) {
                    rule.values[key] = v;
                    onChanged();
                  }
                : null,
          ),
        );
      case 'integer':
        return Padding(
          padding: const EdgeInsets.all(16),
          child: TextFormField(
            initialValue: '${rule.values[key]}',
            enabled: available,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: title,
              helperText: '${option['min']}–${option['max']}',
            ),
            onChanged: (v) {
              rule.values[key] = int.tryParse(v);
              onChanged();
            },
          ),
        );
      default:
        return ListTile(title: Text(title), subtitle: const Text('暂不支持此配置类型'));
    }
  }
}
