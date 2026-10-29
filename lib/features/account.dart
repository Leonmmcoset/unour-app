import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../core/controller.dart';
import '../game/design.dart';
import '../game/motion.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController(),
      _password = TextEditingController();
  bool _register = false, _show = false;
  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await ref
        .read(appProvider)
        .authenticate(_username.text, _password.text, _register);
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Unour',
                                style: Theme.of(
                                  context,
                                ).textTheme.displayMedium,
                              ),
                              const SizedBox(height: 12),
                              const ColorDots(),
                            ],
                          ),
                        ),
                        const Expanded(child: PartyHero(compact: true)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    MotionEntrance(
                      delay: 100,
                      child: GamePanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(value: false, label: Text('登录')),
                                ButtonSegment(value: true, label: Text('注册')),
                              ],
                              selected: {_register},
                              onSelectionChanged: app.busy
                                  ? null
                                  : (v) => setState(() {
                                      _register = v.first;
                                      app.clearError();
                                    }),
                            ),
                            const SizedBox(height: 22),
                            AutofillGroup(
                              child: Column(
                                children: [
                                  TextFormField(
                                    controller: _username,
                                    enabled: !app.busy,
                                    autofillHints: const [
                                      AutofillHints.username,
                                    ],
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: '用户名',
                                      prefixIcon: Icon(Icons.face_rounded),
                                    ),
                                    validator: (s) =>
                                        RegExp(
                                          r'^[\p{Script=Han}A-Za-z0-9_-]{3,24}$',
                                          unicode: true,
                                        ).hasMatch((s ?? '').trim())
                                        ? null
                                        : '请输入 3–24 个汉字、字母、数字、_ 或 -',
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _password,
                                    enabled: !app.busy,
                                    obscureText: !_show,
                                    autofillHints: [
                                      _register
                                          ? AutofillHints.newPassword
                                          : AutofillHints.password,
                                    ],
                                    onFieldSubmitted: (_) => submit(),
                                    decoration: InputDecoration(
                                      labelText: '密码',
                                      helperText: '8–14 个字符，空格也会保留',
                                      prefixIcon: const Icon(
                                        Icons.lock_outline_rounded,
                                      ),
                                      suffixIcon: IconButton(
                                        tooltip: _show ? '隐藏密码' : '显示密码',
                                        onPressed: () =>
                                            setState(() => _show = !_show),
                                        icon: Icon(
                                          _show
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                        ),
                                      ),
                                    ),
                                    validator: (s) =>
                                        (s ?? '').runes.length >= 8 &&
                                            (s ?? '').runes.length <= 14
                                        ? null
                                        : '密码需要 8–14 个字符',
                                  ),
                                ],
                              ),
                            ),
                            ErrorStrip(app.error, onDismiss: app.clearError),
                            const SizedBox(height: 12),
                            PressScale(
                              child: FilledButton(
                                onPressed: app.busy ? null : submit,
                                child: Text(
                                  app.busy
                                      ? '正在连接…'
                                      : _register
                                      ? '注册'
                                      : '登录',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => context.push('/learn'),
                      icon: const Icon(Icons.school_outlined, size: 19),
                      label: const Text('第一次玩？看看怎么玩'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider), user = app.account;
    if (user == null) return const Scaffold(body: Center(child: Text('请先登录')));
    Future<void> upload() async {
      try {
        final image = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 90,
        );
        if (image == null) return;
        final bytes = await image.readAsBytes();
        final png =
            bytes.length > 8 &&
            bytes[0] == 137 &&
            bytes[1] == 80 &&
            bytes[2] == 78 &&
            bytes[3] == 71;
        final jpeg = bytes.length > 3 && bytes[0] == 255 && bytes[1] == 216;
        if (bytes.length > 2 * 1024 * 1024 || (!png && !jpeg)) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('请选择 2 MiB 以内的 PNG 或 JPEG 图片')),
            );
          }
          return;
        }
        await app.uploadAvatar(bytes, png ? 'image/png' : 'image/jpeg');
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('无法打开相册，请检查照片访问权限')));
        }
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('我的玩家卡')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              MotionEntrance(
                child: GamePanel(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      Center(
                        child: ProfileAvatar(
                          name: user.username,
                          url: user.avatarUrl,
                          radius: 56,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        user.username,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              PressScale(
                child: FilledButton.icon(
                  onPressed: app.busy ? null : upload,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('换个头像'),
                ),
              ),
              TextButton(
                onPressed: app.busy || user.avatarUrl.isEmpty
                    ? null
                    : () => app.resetAvatar(),
                child: const Text('恢复默认头像'),
              ),
              ErrorStrip(app.error, onDismiss: app.clearError),
              const SizedBox(height: 30),
              OutlinedButton(
                onPressed: app.busy
                    ? null
                    : () async {
                        if (!await confirm(
                          context,
                          '退出登录？',
                          '关闭应用不会弃权。登录后可通过最近房间恢复牌局。',
                        )) {
                          return;
                        }
                        final ok = await app.logout();
                        if (ok && context.mounted) context.go('/');
                      },
                child: const Text('退出登录'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
