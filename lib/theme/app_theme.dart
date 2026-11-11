import 'package:flutter/material.dart';

/// Design System institutionnel, sobre et accessible.
/// Conçu pour une application d'orientation scolaire professionnelle, lisible et apaisante.
class AppTheme {
  // Fond principal (Blanc cassé / Slate très léger)
  static const Color background = Color(0xFFF8FAFC);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color cardBgElevated = Color(0xFFF1F5F9);
  static const Color borderColor = Color(0xFFE2E8F0);
  static const Color borderColorSoft = Color(0xFFF1F5F9);

  // Couleur primaire : Bleu marine institutionnel (sérieux, académique, contrasté)
  static const Color primary = Color(0xFF1E3A8A);
  static const Color primaryLight = Color(0xFF2563EB);
  static const Color primarySoft = Color(0xFFEFF6FF);
  static const Color primaryDark = Color(0xFF0F172A);

  // Palette sémantique sobre (validations, alertes, repères)
  static const Color accentEmerald = Color(0xFF059669);
  static const Color accentEmeraldSoft = Color(0xFFECFDF5);

  static const Color accentAmber = Color(0xFFD97706);
  static const Color accentAmberSoft = Color(0xFFFEF3C7);

  static const Color accentCoral = Color(0xFFDC2626);
  static const Color accentCoralSoft = Color(0xFFFEF2F2);

  static const Color accentSky = Color(0xFF0284C7);
  static const Color accentSkySoft = Color(0xFFE0F2FE);

  static const Color accentSlate = Color(0xFF475569);
  static const Color accentSlateSoft = Color(0xFFF1F5F9);

  // Typographie : Slate sombre texturé (excellente lisibilité WCAG AAA)
  static const Color textMain = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textSubtle = Color(0xFF94A3B8);

  // Ombres douces subtiles et contrôlées
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.04),
          blurRadius: 14,
          spreadRadius: 0,
          offset: const Offset(0, 3),
        ),
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.02),
          blurRadius: 4,
          spreadRadius: 0,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get cardElevation => [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.06),
          blurRadius: 18,
          spreadRadius: -2,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.02),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];

  // Dégradés sobres discrets
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF1E3A8A), Color(0xFF1E40AF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient softHeroGradient = LinearGradient(
    colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient softAmberGradient = LinearGradient(
    colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient softEmeraldGradient = LinearGradient(
    colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primary,
      scaffoldBackgroundColor: background,
      canvasColor: cardBg,
      cardColor: cardBg,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: accentEmerald,
        surface: cardBg,
        outline: borderColor,
        onPrimary: Colors.white,
        onSurface: textMain,
        error: accentCoral,
      ),
      fontFamily: '-apple-system',
      textTheme: const TextTheme(
        displayLarge: TextStyle(color: textMain, letterSpacing: -0.6, fontWeight: FontWeight.bold),
        displayMedium: TextStyle(color: textMain, letterSpacing: -0.5, fontWeight: FontWeight.bold),
        displaySmall: TextStyle(color: textMain, fontWeight: FontWeight.w600),
        headlineLarge: TextStyle(color: textMain, fontWeight: FontWeight.bold, letterSpacing: -0.5),
        headlineMedium: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 22, letterSpacing: -0.3),
        headlineSmall: TextStyle(color: textMain, fontWeight: FontWeight.bold, letterSpacing: -0.2),
        titleLarge: TextStyle(color: textMain, fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: -0.2),
        titleMedium: TextStyle(color: textMain, fontSize: 15, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(color: textMuted, fontSize: 14),
        bodyLarge: TextStyle(color: textMain, fontSize: 15, height: 1.5),
        bodyMedium: TextStyle(color: textMain, fontSize: 14, height: 1.45),
        bodySmall: TextStyle(color: textMuted, fontSize: 12),
        labelLarge: TextStyle(color: textMain, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(color: textMuted),
        labelSmall: TextStyle(color: textSubtle),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: textMain),
        titleTextStyle: TextStyle(
          color: textMain,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.3,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(color: textMuted),
        hintStyle: const TextStyle(color: textSubtle),
        floatingLabelStyle: const TextStyle(color: primary, fontWeight: FontWeight.w600),
        prefixIconColor: textMuted,
        suffixIconColor: textMuted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderColor, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderColor, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accentCoral, width: 1.4),
        ),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        textStyle: TextStyle(color: textMain),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: borderColor, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, letterSpacing: -0.1),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: Color(0xFFE2E8F0),
        thumbColor: primary,
        overlayColor: Color(0x1A1E3A8A),
        valueIndicatorColor: primary,
        valueIndicatorTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }
}
