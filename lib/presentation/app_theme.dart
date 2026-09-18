import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  /// [seedColor] 只影响 `ColorScheme.fromSeed` 的主色，背景色、卡片色与文字色
  /// 仍由下面的固定值决定。
  static ThemeData light({required Color seedColor}) => _build(
    brightness: Brightness.light,
    seedColor: seedColor,
    background: const Color(0xFFF5F5F3),
    surface: Colors.white,
    text: const Color(0xFF202124),
  );

  static ThemeData dark({required Color seedColor}) => _build(
    brightness: Brightness.dark,
    seedColor: seedColor,
    background: const Color(0xFF111214),
    surface: const Color(0xFF1C1D20),
    text: const Color(0xFFF1F1EF),
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color seedColor,
    required Color background,
    required Color surface,
    required Color text,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      surface: surface,
    );
    final overlayStyle =
        (brightness == Brightness.light
                ? SystemUiOverlayStyle.dark
                : SystemUiOverlayStyle.light)
            .copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: background,
              systemNavigationBarIconBrightness: brightness == Brightness.light
                  ? Brightness.dark
                  : Brightness.light,
            );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: ThemeData(
        brightness: brightness,
      ).textTheme.apply(bodyColor: text, displayColor: text),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: overlayStyle,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
      ),
    );
  }
}
