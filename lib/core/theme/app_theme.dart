import 'package:flutter/material.dart';
import 'design_tokens.dart';

class AppTheme {
  // Backward-compatible getters mapping to DesignTokens for gradual migration
  static const Color primary = DesignTokens.textPrimaryDark;
  static const Color primaryDark = DesignTokens.textPrimaryLight;
  static const Color accent = DesignTokens.textSecondaryDark;
  static const Color bgDark = DesignTokens.bgDark;
  static const Color surfaceDark = DesignTokens.surfaceDark;
  static const Color surfaceLight = DesignTokens.surfaceInputDark;
  static const Color borderDark = DesignTokens.borderDark;
  static const Color textPrimary = DesignTokens.textPrimaryDark;
  static const Color textSecondary = DesignTokens.textSecondaryDark;
  static const Color textMuted = DesignTokens.textSecondaryDark;

  // Status indicators in neutral tones
  static const Color success = DesignTokens.statusSuccessDark;
  static const Color warning = DesignTokens.statusPendingDark;
  static const Color error = DesignTokens.statusErrorDark;
  static const Color toolBadge = DesignTokens.surfaceInputDark;

  /// Builds modern, accessible typography adhering to 5 defined font sizes.
  static TextTheme _buildTextTheme(Color primaryColor, Color secondaryColor) {
    const fallbacks = DesignTokens.sansFallbacks;
    const sans = DesignTokens.fontFamilySans;

    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: sans,
        fontFamilyFallback: fallbacks,
        fontSize: DesignTokens.fontSize2Xl,
        fontWeight: FontWeight.w700,
        color: primaryColor,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        fontFamily: sans,
        fontFamilyFallback: fallbacks,
        fontSize: DesignTokens.fontSizeXl,
        fontWeight: FontWeight.w600,
        color: primaryColor,
        letterSpacing: -0.3,
      ),
      titleMedium: TextStyle(
        fontFamily: sans,
        fontFamilyFallback: fallbacks,
        fontSize: DesignTokens.fontSizeLg,
        fontWeight: FontWeight.w600,
        color: primaryColor,
      ),
      bodyLarge: TextStyle(
        fontFamily: sans,
        fontFamilyFallback: fallbacks,
        fontSize: DesignTokens.fontSizeBase,
        fontWeight: FontWeight.normal,
        color: primaryColor,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontFamily: sans,
        fontFamilyFallback: fallbacks,
        fontSize: DesignTokens.fontSizeSm,
        fontWeight: FontWeight.normal,
        color: secondaryColor,
        height: 1.45,
      ),
      labelSmall: TextStyle(
        fontFamily: sans,
        fontFamilyFallback: fallbacks,
        fontSize: DesignTokens.fontSizeXs,
        fontWeight: FontWeight.w500,
        color: secondaryColor,
      ),
    );
  }

  /// Complete Light Theme (Monochrome)
  static ThemeData get lightTheme {
    final textTheme = _buildTextTheme(
      DesignTokens.textPrimaryLight,
      DesignTokens.textSecondaryLight,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: DesignTokens.bgLight,
      fontFamily: DesignTokens.fontFamilySans,
      fontFamilyFallback: DesignTokens.sansFallbacks,
      textTheme: textTheme,
      colorScheme: const ColorScheme.light(
        primary: DesignTokens.textPrimaryLight,
        onPrimary: DesignTokens.bgLight,
        secondary: DesignTokens.textSecondaryLight,
        onSecondary: DesignTokens.bgLight,
        surface: DesignTokens.surfaceLight,
        onSurface: DesignTokens.textPrimaryLight,
        error: DesignTokens.statusErrorLight,
        onError: DesignTokens.bgLight,
        outline: DesignTokens.borderLight,
      ),
      dividerTheme: const DividerThemeData(
        color: DesignTokens.borderLight,
        thickness: DesignTokens.hairline,
        space: DesignTokens.space16,
      ),
      cardTheme: CardThemeData(
        color: DesignTokens.surfaceLight,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          side: const BorderSide(
            color: DesignTokens.borderLight,
            width: DesignTokens.hairline,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DesignTokens.surfaceInputLight,
        hintStyle: const TextStyle(
          color: DesignTokens.textSecondaryLight,
          fontSize: DesignTokens.fontSizeSm,
          fontFamily: DesignTokens.fontFamilySans,
          fontFamilyFallback: DesignTokens.sansFallbacks,
        ),
        labelStyle: const TextStyle(
          color: DesignTokens.textSecondaryLight,
          fontSize: DesignTokens.fontSizeSm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          borderSide: const BorderSide(
            color: DesignTokens.borderLight,
            width: DesignTokens.hairline,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          borderSide: const BorderSide(
            color: DesignTokens.borderLight,
            width: DesignTokens.hairline,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          borderSide: const BorderSide(
            color: DesignTokens.textPrimaryLight,
            width: DesignTokens.hairlineThick,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.space16,
          vertical: DesignTokens.space12,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DesignTokens.textPrimaryLight,
          foregroundColor: DesignTokens.bgLight,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.space16,
            vertical: DesignTokens.space12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          ),
          textStyle: const TextStyle(
            fontSize: DesignTokens.fontSizeSm,
            fontWeight: FontWeight.w600,
            fontFamily: DesignTokens.fontFamilySans,
            fontFamilyFallback: DesignTokens.sansFallbacks,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: DesignTokens.textPrimaryLight,
          side: const BorderSide(
            color: DesignTokens.borderLight,
            width: DesignTokens.hairline,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.space16,
            vertical: DesignTokens.space12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          ),
          textStyle: const TextStyle(
            fontSize: DesignTokens.fontSizeSm,
            fontWeight: FontWeight.w500,
            fontFamily: DesignTokens.fontFamilySans,
            fontFamilyFallback: DesignTokens.sansFallbacks,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: DesignTokens.textSecondaryLight,
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.space12,
            vertical: DesignTokens.space8,
          ),
          textStyle: const TextStyle(
            fontSize: DesignTokens.fontSizeSm,
            fontFamily: DesignTokens.fontFamilySans,
            fontFamilyFallback: DesignTokens.sansFallbacks,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: DesignTokens.bgLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          side: const BorderSide(
            color: DesignTokens.borderLight,
            width: DesignTokens.hairline,
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: DesignTokens.space12),
        textColor: DesignTokens.textPrimaryLight,
        iconColor: DesignTokens.textSecondaryLight,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: DesignTokens.surfaceLight,
        side: const BorderSide(
          color: DesignTokens.borderLight,
          width: DesignTokens.hairline,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        ),
        labelStyle: const TextStyle(
          fontSize: DesignTokens.fontSizeSm,
          color: DesignTokens.textPrimaryLight,
        ),
      ),
    );
  }

  /// Complete Dark Theme (Monochrome)
  static ThemeData get darkTheme {
    final textTheme = _buildTextTheme(
      DesignTokens.textPrimaryDark,
      DesignTokens.textSecondaryDark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: DesignTokens.bgDark,
      fontFamily: DesignTokens.fontFamilySans,
      fontFamilyFallback: DesignTokens.sansFallbacks,
      textTheme: textTheme,
      colorScheme: const ColorScheme.dark(
        primary: DesignTokens.textPrimaryDark,
        onPrimary: DesignTokens.bgDark,
        secondary: DesignTokens.textSecondaryDark,
        onSecondary: DesignTokens.bgDark,
        surface: DesignTokens.surfaceDark,
        onSurface: DesignTokens.textPrimaryDark,
        error: DesignTokens.statusErrorDark,
        onError: DesignTokens.bgDark,
        outline: DesignTokens.borderDark,
      ),
      dividerTheme: const DividerThemeData(
        color: DesignTokens.borderDark,
        thickness: DesignTokens.hairline,
        space: DesignTokens.space16,
      ),
      cardTheme: CardThemeData(
        color: DesignTokens.surfaceDark,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          side: const BorderSide(
            color: DesignTokens.borderDark,
            width: DesignTokens.hairline,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DesignTokens.surfaceInputDark,
        hintStyle: const TextStyle(
          color: DesignTokens.textSecondaryDark,
          fontSize: DesignTokens.fontSizeSm,
          fontFamily: DesignTokens.fontFamilySans,
          fontFamilyFallback: DesignTokens.sansFallbacks,
        ),
        labelStyle: const TextStyle(
          color: DesignTokens.textSecondaryDark,
          fontSize: DesignTokens.fontSizeSm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          borderSide: const BorderSide(
            color: DesignTokens.borderDark,
            width: DesignTokens.hairline,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          borderSide: const BorderSide(
            color: DesignTokens.borderDark,
            width: DesignTokens.hairline,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          borderSide: const BorderSide(
            color: DesignTokens.textPrimaryDark,
            width: DesignTokens.hairlineThick,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.space16,
          vertical: DesignTokens.space12,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DesignTokens.textPrimaryDark,
          foregroundColor: DesignTokens.bgDark,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.space16,
            vertical: DesignTokens.space12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          ),
          textStyle: const TextStyle(
            fontSize: DesignTokens.fontSizeSm,
            fontWeight: FontWeight.w600,
            fontFamily: DesignTokens.fontFamilySans,
            fontFamilyFallback: DesignTokens.sansFallbacks,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: DesignTokens.textPrimaryDark,
          side: const BorderSide(
            color: DesignTokens.borderDark,
            width: DesignTokens.hairline,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.space16,
            vertical: DesignTokens.space12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          ),
          textStyle: const TextStyle(
            fontSize: DesignTokens.fontSizeSm,
            fontWeight: FontWeight.w500,
            fontFamily: DesignTokens.fontFamilySans,
            fontFamilyFallback: DesignTokens.sansFallbacks,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: DesignTokens.textSecondaryDark,
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.space12,
            vertical: DesignTokens.space8,
          ),
          textStyle: const TextStyle(
            fontSize: DesignTokens.fontSizeSm,
            fontFamily: DesignTokens.fontFamilySans,
            fontFamilyFallback: DesignTokens.sansFallbacks,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: DesignTokens.bgDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          side: const BorderSide(
            color: DesignTokens.borderDark,
            width: DesignTokens.hairline,
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: DesignTokens.space12),
        textColor: DesignTokens.textPrimaryDark,
        iconColor: DesignTokens.textSecondaryDark,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: DesignTokens.surfaceDark,
        side: const BorderSide(
          color: DesignTokens.borderDark,
          width: DesignTokens.hairline,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        ),
        labelStyle: const TextStyle(
          fontSize: DesignTokens.fontSizeSm,
          color: DesignTokens.textPrimaryDark,
        ),
      ),
    );
  }
}
