import 'package:flutter/material.dart';

/// Tema oscuro profesional de vigilancia.
class VantaTheme {
  static const Color bg = Color(0xFF0B0C0F);
  static const Color surface = Color(0xFF15171C);
  static const Color surfaceHigh = Color(0xFF1D2026);
  static const Color border = Color(0xFF252932);
  static const Color accent = Color(0xFF2F9BFF);
  static const Color textPrimary = Color(0xFFE8EAED);
  static const Color textSecondary = Color(0xFF9AA0A6);

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: accent,
      surface: surface,
      onSurface: textPrimary,
      error: Color(0xFFE5533D),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        labelStyle: const TextStyle(color: textSecondary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(foregroundColor: WidgetStatePropertyAll(textPrimary)),
      ),
      dialogTheme: const DialogThemeData(backgroundColor: surface),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: TextStyle(color: textPrimary),
      ),
      dividerTheme: const DividerThemeData(color: border),
      listTileTheme: const ListTileThemeData(iconColor: textSecondary),
    );
  }

  /// Acción rápida "Pill" para elegir layout (1/4/9/16).
  static Widget layoutPill({
    required String label,
    required bool selected,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent : surfaceHigh,
          borderRadius: BorderRadius.circular(18),
          border: selected ? null : Border.all(color: border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}