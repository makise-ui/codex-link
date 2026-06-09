import 'dart:ui';

import 'package:flutter/material.dart';

class CodexColors {
  static const ink = Color(0xFF000000);
  static const ink2 = Color(0xFF0B0B0B);
  static const panel = Color(0xD9161618);
  static const panelHigh = Color(0xF0202022);
  static const bubble = Color(0xFF2B2B2D);
  static const composer = Color(0xF01F1F21);
  static const border = Color(0xFF3B3B3D);
  static const borderSoft = Color(0xFF29292B);
  static const text = Color(0xFFFFFFFF);
  static const muted = Color(0xFFA7A7AA);
  static const dim = Color(0xFF77777B);
  static const green = Color(0xFF10A37F);
  static const greenSoft = Color(0xFF19C37D);
  static const blue = Color(0xFF2D8CFF);
  static const amber = Color(0xFFF2C94C);
  static const danger = Color(0xFFFF4A4A);
}

class LightCodexColors {
  static const ink = Color(0xFFF7F7F4);
  static const ink2 = Color(0xFFFFFFFF);
  static const panel = Color(0xEFFFFFFF);
  static const panelHigh = Color(0xFFFFFFFF);
  static const bubble = Color(0xFFE9E9E5);
  static const composer = Color(0xF7FFFFFF);
  static const border = Color(0xFFD2D2CC);
  static const borderSoft = Color(0xFFE5E5DF);
  static const text = Color(0xFF20211F);
  static const muted = Color(0xFF686A66);
  static const dim = Color(0xFF8D908A);
}

class AppSpacing {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 22.0;
}

class AppRadius {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 18.0;
  static const xl = 22.0;
  static const pill = 999.0;
}

class AppMotion {
  static const quick = Duration(milliseconds: 180);
  static const messageEnter = Duration(milliseconds: 240);
  static const scroll = Duration(milliseconds: 460);
  static const pulse = Duration(milliseconds: 1000);
}

class AppOpacity {
  static const hairline = 0.08;
  static const border = 0.12;
  static const panel = 0.74;
  static const glow = 0.22;
}

const accentColorOptions = <String, Color>{
  'neutral': CodexColors.muted,
  'blue': CodexColors.blue,
  'green': CodexColors.greenSoft,
  'violet': Color(0xFF9B8CFF),
  'amber': CodexColors.amber,
};

Color accentColorForName(String name) {
  return accentColorOptions[name] ?? accentColorOptions['neutral']!;
}

String accentLabelForName(String name) {
  return switch (name) {
    'blue' => 'Blue',
    'green' => 'Green',
    'violet' => 'Violet',
    'amber' => 'Amber',
    _ => 'Neutral',
  };
}

ThemeData buildCodexTheme({
  Color accentColor = CodexColors.muted,
  Brightness brightness = Brightness.dark,
}) {
  final light = brightness == Brightness.light;
  final surface = light ? LightCodexColors.ink : CodexColors.ink;
  final text = light ? LightCodexColors.text : CodexColors.text;
  final muted = light ? LightCodexColors.muted : CodexColors.muted;
  final dim = light ? LightCodexColors.dim : CodexColors.dim;
  final composer = light ? LightCodexColors.composer : CodexColors.composer;
  final border = light ? LightCodexColors.border : CodexColors.border;
  final borderSoft = light
      ? LightCodexColors.borderSoft
      : CodexColors.borderSoft;
  final bubble = light ? LightCodexColors.bubble : CodexColors.bubble;
  final scheme = ColorScheme.fromSeed(
    seedColor: accentColor,
    brightness: brightness,
    surface: surface,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme.copyWith(
      primary: text,
      secondary: accentColor,
      surface: surface,
      onSurface: text,
      error: CodexColors.danger,
    ),
    scaffoldBackgroundColor: surface,
    fontFamily: 'Roboto',
    splashFactory: InkSparkle.splashFactory,
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontSize: 27,
        height: 1.08,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        height: 1.12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.45, letterSpacing: 0),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45, letterSpacing: 0),
      labelLarge: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
    ).apply(bodyColor: text, displayColor: text),
    cardTheme: CardThemeData(
      color: light ? LightCodexColors.panel : CodexColors.panel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderSoft),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: text,
      elevation: 0,
      centerTitle: false,
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: Colors.transparent,
      scrimColor: Colors.black54,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: composer,
      labelStyle: TextStyle(color: muted),
      hintStyle: TextStyle(color: dim),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: borderSoft),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: muted, width: 1.2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: text,
        foregroundColor: surface,
        disabledBackgroundColor: bubble,
        disabledForegroundColor: dim,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        side: BorderSide(color: border),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

bool isCodexLight(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light;

Color codexTextColor(BuildContext context) =>
    isCodexLight(context) ? LightCodexColors.text : CodexColors.text;

Color codexMutedColor(BuildContext context) =>
    isCodexLight(context) ? LightCodexColors.muted : CodexColors.muted;

Color codexDimColor(BuildContext context) =>
    isCodexLight(context) ? LightCodexColors.dim : CodexColors.dim;

Color codexComposerColor(BuildContext context) =>
    isCodexLight(context) ? LightCodexColors.composer : CodexColors.composer;

Color codexPanelHighColor(BuildContext context) =>
    isCodexLight(context) ? LightCodexColors.panelHigh : CodexColors.panelHigh;

class AnimatedChatGptBackdrop extends StatelessWidget {
  const AnimatedChatGptBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final light = isCodexLight(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: light ? LightCodexColors.ink : CodexColors.ink2,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: light ? LightCodexColors.ink : CodexColors.ink2,
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
    this.radius = 16,
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
    final light = isCodexLight(context);
    final resolvedColor = color ?? (light ? LightCodexColors.panel : null);
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: resolvedColor ?? CodexColors.panel,
              borderRadius: BorderRadius.circular(radius),
              border: showBorder
                  ? Border.all(
                      color: light
                          ? Colors.black.withValues(alpha: 0.09)
                          : Colors.white.withValues(alpha: 0.11),
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: light ? 0.08 : 0.24),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.025),
                  blurRadius: 0,
                  spreadRadius: 1,
                ),
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
  const SoftPill({
    super.key,
    required this.label,
    this.color = CodexColors.text,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final light = isCodexLight(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (light ? LightCodexColors.panelHigh : CodexColors.panelHigh)
            .withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: (light ? Colors.black : Colors.white).withValues(alpha: 0.11),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class ChatGptCircleButton extends StatelessWidget {
  const ChatGptCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 44,
    this.foreground = CodexColors.text,
    this.background = CodexColors.panelHigh,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final light = isCodexLight(context);
    final resolvedBackground = light ? LightCodexColors.panelHigh : background;
    final resolvedForeground = light && foreground == CodexColors.text
        ? LightCodexColors.text
        : foreground;
    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Material(
            color: resolvedBackground.withValues(alpha: 0.92),
            shape: CircleBorder(
              side: BorderSide(
                color: (light ? Colors.black : Colors.white).withValues(
                  alpha: 0.12,
                ),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              onPressed: onPressed,
              icon: Icon(icon, color: resolvedForeground, size: size * 0.44),
            ),
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
    final light = isCodexLight(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: (light ? LightCodexColors.panelHigh : CodexColors.panelHigh)
                .withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: (light ? Colors.black : Colors.white).withValues(
                alpha: 0.12,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: light ? 0.10 : 0.24),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}
