import 'dart:ui';

import 'package:flutter/material.dart';

class CodexColors {
  static const ink = Color(0xFF000000);
  static const ink2 = Color(0xFF0B0B0B);
  static const panel = Color(0xD91D1D1F);
  static const panelHigh = Color(0xF0272729);
  static const bubble = Color(0xFF2F2F2F);
  static const composer = Color(0xEB222224);
  static const border = Color(0xFF454547);
  static const borderSoft = Color(0xFF2D2D2F);
  static const text = Color(0xFFFFFFFF);
  static const muted = Color(0xFFB4B4B4);
  static const dim = Color(0xFF7D7D7D);
  static const green = Color(0xFF10A37F);
  static const greenSoft = Color(0xFF19C37D);
  static const blue = Color(0xFF2D8CFF);
  static const amber = Color(0xFFF2C94C);
  static const danger = Color(0xFFFF4A4A);
}

ThemeData buildCodexTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: CodexColors.green,
    brightness: Brightness.dark,
    surface: CodexColors.ink,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme.copyWith(
      primary: CodexColors.text,
      secondary: CodexColors.green,
      surface: CodexColors.ink,
      error: CodexColors.danger,
    ),
    scaffoldBackgroundColor: CodexColors.ink,
    fontFamily: 'Roboto',
    splashFactory: InkSparkle.splashFactory,
    textTheme: const TextTheme(
      headlineMedium: TextStyle(fontSize: 34, height: 1.04, fontWeight: FontWeight.w800, letterSpacing: -1.15),
      headlineSmall: TextStyle(fontSize: 28, height: 1.08, fontWeight: FontWeight.w700, letterSpacing: -0.8),
      titleLarge: TextStyle(fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -0.45),
      titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.25),
      bodyLarge: TextStyle(fontSize: 18, height: 1.45, letterSpacing: -0.1),
      bodyMedium: TextStyle(fontSize: 16, height: 1.45, letterSpacing: -0.05),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.05),
    ).apply(bodyColor: CodexColors.text, displayColor: CodexColors.text),
    cardTheme: CardThemeData(
      color: CodexColors.panel,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26), side: const BorderSide(color: CodexColors.borderSoft)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: CodexColors.text,
      elevation: 0,
      centerTitle: false,
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: CodexColors.ink, scrimColor: Colors.black54),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: CodexColors.composer,
      labelStyle: const TextStyle(color: CodexColors.muted),
      hintStyle: const TextStyle(color: CodexColors.dim),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: CodexColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: CodexColors.borderSoft)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: CodexColors.muted, width: 1.2)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: CodexColors.text,
        foregroundColor: CodexColors.ink,
        disabledBackgroundColor: CodexColors.bubble,
        disabledForegroundColor: CodexColors.dim,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: CodexColors.text,
        side: const BorderSide(color: CodexColors.border),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class AnimatedChatGptBackdrop extends StatelessWidget {
  const AnimatedChatGptBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: CodexColors.ink),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.86, -1.06),
                radius: 0.9,
                colors: [Color(0x22252528), Color(0x00000000)],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x12000000), Color(0xFF000000)],
                stops: [0.0, 0.76],
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.radius = 26,
    this.color,
    this.showBorder = true,
    this.blur = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color? color;
  final bool showBorder;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: color ?? CodexColors.panel,
              borderRadius: BorderRadius.circular(radius),
              border: showBorder ? Border.all(color: Colors.white.withValues(alpha: 0.11)) : null,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.30), blurRadius: 22, offset: const Offset(0, 12)),
                BoxShadow(color: Colors.white.withValues(alpha: 0.025), blurRadius: 0, spreadRadius: 1),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class SoftPill extends StatelessWidget {
  const SoftPill({super.key, required this.label, this.color = CodexColors.text, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: CodexColors.panelHigh.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 15, color: color), const SizedBox(width: 7)],
          Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color)),
        ],
      ),
    );
  }
}

class ChatGptCircleButton extends StatelessWidget {
  const ChatGptCircleButton({super.key, required this.icon, required this.onPressed, this.size = 58, this.foreground = CodexColors.text, this.background = CodexColors.panelHigh});

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Material(
            color: background.withValues(alpha: 0.92),
            shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
            clipBehavior: Clip.antiAlias,
            child: IconButton(onPressed: onPressed, icon: Icon(icon, color: foreground, size: size * 0.44)),
          ),
        ),
      ),
    );
  }
}

class ChatGptActionPill extends StatelessWidget {
  const ChatGptActionPill({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: CodexColors.panelHigh.withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 22, offset: const Offset(0, 10))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}
