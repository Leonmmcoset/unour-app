import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

import 'core/api.dart';
import 'core/controller.dart';
import 'core/feedback.dart';
import 'core/preferences.dart';
import 'features/account.dart';
import 'features/home.dart';
import 'features/settings.dart';
import 'features/setup.dart';
import 'game/design.dart';
import 'game/room_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = GamePreferences(await SharedPreferences.getInstance());
  final app = AppController(
    Api(
      const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      ),
    ),
    GameFeedback(prefs),
  );
  runApp(
    ProviderScope(
      overrides: [
        appProvider.overrideWith((ref) => app),
        preferencesProvider.overrideWith((ref) => prefs),
      ],
      child: UnourApp(controller: app),
    ),
  );
  await app.initialize();
}

class UnourApp extends ConsumerStatefulWidget {
  final AppController controller;
  const UnourApp({super.key, required this.controller});
  @override
  ConsumerState<UnourApp> createState() => _UnourAppState();
}

class _UnourAppState extends ConsumerState<UnourApp>
    with WidgetsBindingObserver {
  late final GoRouter router;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    router = GoRouter(
      refreshListenable: widget.controller,
      redirect: (context, state) {
        final app = widget.controller, path = state.uri.path;
        if (app.loading) return path == '/loading' ? null : '/loading';
        if (app.account == null) return path == '/login' ? null : '/login';
        if (path == '/login' || path == '/loading') return '/';
        if (path == '/room' && app.room == null) return '/';
        return null;
      },
      routes: [
        GoRoute(
          path: '/loading',
          builder: (_, state) =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
        ),
        GoRoute(path: '/login', builder: (_, state) => const LoginPage()),
        GoRoute(path: '/', builder: (_, state) => const HomePage()),
        GoRoute(path: '/account', builder: (_, state) => const AccountPage()),
        GoRoute(path: '/settings', builder: (_, state) => const SettingsPage()),
        GoRoute(
          path: '/setup/:mode',
          builder: (_, state) => SetupPage(mode: state.pathParameters['mode']!),
        ),
        GoRoute(path: '/room', builder: (_, state) => const RoomPage()),
      ],
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      widget.controller.setActive(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(preferencesProvider);
    return MaterialApp.router(
      title: 'Unour',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: partyTheme(Brightness.light),
      darkTheme: partyTheme(Brightness.dark),
      themeMode: prefs.theme,
      routerConfig: router,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            disableAnimations: prefs.reduceMotion || media.disableAnimations,
          ),
          child: child!,
        );
      },
    );
  }
}
