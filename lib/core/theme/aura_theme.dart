import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Font families bundled in assets/fonts (both SIL OFL).
class AuraFonts {
  static const manuscript = 'Newsreader';
  static const ui = 'InstrumentSans';
}

/// Brand colors by role, not by value: widgets ask for `context.aura.text`
/// and get the tinta (dark) or papel (light) value. Hex values and the
/// measured contrast ratios are in design/brand.html.
@immutable
class AuraColors extends ThemeExtension<AuraColors> {
  final Color bg;
  final Color surface;
  final Color surfaceHigh;
  final Color line;
  final Color text;
  final Color textDim;
  final Color textFaint;

  /// Fills (buttons, progress, the logo ring).
  final Color accent;

  /// Accent for text and icons on [bg]: lighter than [accent] on tinta so it
  /// keeps 4.5:1, the same as [accent] on papel.
  final Color accentText;

  /// Text on top of an [accent] fill. Dark on tinta: light text on the lacre
  /// fill only reaches 3.0:1.
  final Color onAccent;
  final Color danger;

  const AuraColors({
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.line,
    required this.text,
    required this.textDim,
    required this.textFaint,
    required this.accent,
    required this.accentText,
    required this.onAccent,
    required this.danger,
  });

  static const tinta = AuraColors(
    bg: Color(0xFF110C09),
    surface: Color(0xFF1A1511),
    surfaceHigh: Color(0xFF26201C),
    line: Color(0xFF38322D),
    text: Color(0xFFEFEBE2),
    textDim: Color(0xFFA9A49B),
    textFaint: Color(0xFF7A746B),
    accent: Color(0xFFD86258),
    accentText: Color(0xFFEF7F74),
    onAccent: Color(0xFF110C09),
    danger: Color(0xFFEF7F74),
  );

  static const papel = AuraColors(
    bg: Color(0xFFF6F3EC),
    surface: Color(0xFFEDE9E1),
    surfaceHigh: Color(0xFFE4DFD5),
    line: Color(0xFFD9D3C8),
    text: Color(0xFF1F1915),
    textDim: Color(0xFF5A544D),
    textFaint: Color(0xFF8A8379),
    accent: Color(0xFFA83630),
    accentText: Color(0xFFA83630),
    onAccent: Color(0xFFF6F3EC),
    danger: Color(0xFFA83630),
  );

  @override
  AuraColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceHigh,
    Color? line,
    Color? text,
    Color? textDim,
    Color? textFaint,
    Color? accent,
    Color? accentText,
    Color? onAccent,
    Color? danger,
  }) =>
      AuraColors(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surfaceHigh: surfaceHigh ?? this.surfaceHigh,
        line: line ?? this.line,
        text: text ?? this.text,
        textDim: textDim ?? this.textDim,
        textFaint: textFaint ?? this.textFaint,
        accent: accent ?? this.accent,
        accentText: accentText ?? this.accentText,
        onAccent: onAccent ?? this.onAccent,
        danger: danger ?? this.danger,
      );

  @override
  AuraColors lerp(ThemeExtension<AuraColors>? other, double t) {
    if (other is! AuraColors) return this;
    return AuraColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      line: Color.lerp(line, other.line, t)!,
      text: Color.lerp(text, other.text, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

extension AuraContext on BuildContext {
  AuraColors get aura => Theme.of(this).extension<AuraColors>() ?? AuraColors.tinta;
}

class AuraTheme {
  static ThemeData get dark => _build(AuraColors.tinta, Brightness.dark);
  static ThemeData get light => _build(AuraColors.papel, Brightness.light);

  static ThemeData _build(AuraColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      secondary: c.accentText,
      onSecondary: c.onAccent,
      error: c.danger,
      onError: c.onAccent,
      surface: c.surface,
      onSurface: c.text,
      surfaceContainerHighest: c.surfaceHigh,
      outline: c.line,
      outlineVariant: c.line,
    );

    final base = ThemeData(brightness: brightness, useMaterial3: true, fontFamily: AuraFonts.ui);
    final text = base.textTheme.apply(bodyColor: c.text, displayColor: c.text).copyWith(
          headlineSmall: base.textTheme.headlineSmall?.copyWith(fontFamily: AuraFonts.manuscript, color: c.text),
          titleLarge: base.textTheme.titleLarge?.copyWith(fontFamily: AuraFonts.manuscript, color: c.text),
        );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      textTheme: text,
      extensions: [c],
      dividerColor: c.line,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(fontFamily: AuraFonts.manuscript, fontSize: 22, color: c.text),
      ),
      drawerTheme: DrawerThemeData(backgroundColor: c.surface),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        titleTextStyle: TextStyle(fontFamily: AuraFonts.manuscript, fontSize: 20, color: c.text),
      ),
      cardTheme: CardThemeData(color: c.surface, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      inputDecorationTheme: InputDecorationTheme(
        labelStyle: TextStyle(color: c.textDim),
        helperStyle: TextStyle(color: c.textFaint),
        hintStyle: TextStyle(color: c.textFaint),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.line)),
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.accentText, width: 2)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.onAccent, shape: const StadiumBorder()),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: c.accentText)),
      floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: c.accent, foregroundColor: c.onAccent),
      snackBarTheme: SnackBarThemeData(backgroundColor: c.surfaceHigh, contentTextStyle: TextStyle(color: c.text)),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
