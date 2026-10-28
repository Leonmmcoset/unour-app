import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';

Color cardColor(String color) => switch (color) {
  'red' => const Color(0xffe74e53),
  'blue' => const Color(0xff397de0),
  'green' => const Color(0xff239b76),
  'yellow' => const Color(0xffefb938),
  _ => const Color(0xff51488a),
};

ThemeData partyTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff7653c3),
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark
        ? const Color(0xff191623)
        : const Color(0xfffff8ed),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 54),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.all(18),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

class PlayingCard extends StatelessWidget {
  final UnoCard? card;
  final double width;
  final bool selected, playable;
  final VoidCallback? onTap;
  const PlayingCard({
    super.key,
    this.card,
    this.width = 84,
    this.selected = false,
    this.playable = true,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final background = card == null
        ? const Color(0xff554197)
        : cardColor(card!.color);
    return Semantics(
      label: card?.label ?? '背面纸牌',
      excludeSemantics: true,
      button: onTap != null,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: width,
          height: width * 1.46,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(width * .15),
            border: Border.all(
              color: selected ? const Color(0xffffdf80) : Colors.white,
              width: selected ? 4 : 3,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .18),
                blurRadius: selected ? 16 : 5,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(width * .1),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _CardPainter(card?.isWild ?? false),
                  ),
                ),
                Positioned(
                  top: 5,
                  left: 6,
                  child: Text(
                    card?.symbol ?? 'U',
                    style: TextStyle(
                      fontSize: width * .2,
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Center(
                  child: Transform.rotate(
                    angle: -.15,
                    child: FittedBox(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          card?.symbol ?? 'U',
                          style: TextStyle(
                            fontSize: width * .57,
                            height: 1,
                            color: background,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 5,
                  right: 6,
                  child: RotatedBox(
                    quarterTurns: 2,
                    child: Text(
                      card?.symbol ?? 'U',
                      style: TextStyle(
                        fontSize: width * .2,
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                if (!playable)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: .26),
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

class _CardPainter extends CustomPainter {
  final bool wild;
  _CardPainter(this.wild);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(.32);
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: size.width * .82,
      height: size.height * .76,
    );
    canvas.drawOval(rect, Paint()..color = const Color(0xfffffbf0));
    if (wild) {
      final colors = ['red', 'blue', 'green', 'yellow'];
      for (var i = 0; i < 4; i++) {
        canvas.drawArc(
          rect.deflate(size.width * .1),
          i * math.pi / 2,
          math.pi / 2,
          true,
          Paint()..color = cardColor(colors[i]).withValues(alpha: .3),
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CardPainter oldDelegate) => wild != oldDelegate.wild;
}

class PartyHero extends StatelessWidget {
  final bool compact;
  const PartyHero({super.key, this.compact = false});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: compact ? 140 : 220,
    child: Center(
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Transform.translate(
            offset: const Offset(-54, 9),
            child: Transform.rotate(
              angle: -.28,
              child: PlayingCard(
                width: compact ? 65 : 90,
                card: const UnoCard(id: 1, color: 'red', kind: 'reverse'),
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(54, 9),
            child: Transform.rotate(
              angle: .28,
              child: PlayingCard(
                width: compact ? 65 : 90,
                card: const UnoCard(
                  id: 2,
                  color: 'yellow',
                  kind: 'number',
                  number: 7,
                ),
              ),
            ),
          ),
          Transform.rotate(
            angle: -.04,
            child: PlayingCard(
              width: compact ? 72 : 100,
              card: const UnoCard(id: 3, color: 'blue', kind: 'wild'),
            ),
          ),
        ],
      ),
    ),
  );
}

class ErrorStrip extends StatelessWidget {
  final String? message;
  final VoidCallback? onDismiss;
  const ErrorStrip(this.message, {super.key, this.onDismiss});
  @override
  Widget build(BuildContext context) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Material(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  if (onDismiss != null)
                    IconButton(
                      onPressed: onDismiss,
                      tooltip: '关闭提示',
                      icon: const Icon(Icons.close, size: 18),
                    ),
                ],
              ),
            ),
          ),
        );
}

class ProfileAvatar extends StatelessWidget {
  final String name, url;
  final double radius;
  const ProfileAvatar({
    super.key,
    required this.name,
    this.url = '',
    this.radius = 22,
  });
  @override
  Widget build(BuildContext context) {
    final resolved = url.isEmpty
        ? ''
        : Uri.parse(
            const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: 'https://csac.chat/',
            ),
          ).resolve(url).toString();
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      child: resolved.isEmpty
          ? Text(
              name.characters.firstOrNull ?? '?',
              style: TextStyle(
                fontSize: radius * .8,
                fontWeight: FontWeight.w800,
              ),
            )
          : ClipOval(
              child: Image.network(
                resolved,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stack) =>
                    Icon(Icons.person, size: radius),
              ),
            ),
    );
  }
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    ) ??
    false;
