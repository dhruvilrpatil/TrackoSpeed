import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Application theme configuration
/// Dark  palette: #000000, #282A3A, #735F32, #C69749
/// Light palette: #FFFDF6, #FAF6E9, #DDEB9D, #A0C878
class AppTheme {
  AppTheme._();

  // ── Brand Palette (Dark) ───────────────────────────────────
  static const Color teal = Color(0xFF735F32);       // primary accent (bronze)
  static const Color cyan = Color(0xFFC69749);       // secondary accent (golden)
  static const Color darkBg = Color(0xFF000000);     // pure black background
  static const Color darkSurface = Color(0xFF282A3A); // dark navy surface

  // ── Brand Palette (Light) ──────────────────────────────────
  static const Color lightPeach   = Color(0xFFFFFDF6); // off-white
  static const Color lightCream   = Color(0xFFFAF6E9); // warm cream
  static const Color lightApricot = Color(0xFFDDEB9D); // light green
  static const Color lightTan     = Color(0xFFA0C878); // green

  // Semantic colours (resolved by mode)
  static const Color primaryColor = Color(0xFFC69749);
  static const Color secondaryColor = Color(0xFF735F32);
  static const Color accentColor = Color(0xFFC69749);
  static const Color errorColor = Color(0xFFE53935);
  static const Color warningColor = Color(0xFFFFA726);
  static const Color successColor = Color(0xFF66BB6A);

  // ── Dark‐mode colours ─────────────────────────────────────
  static const Color backgroundColor = Color(0xFF000000);
  static const Color surfaceColor = Color(0xFF282A3A);
  static const Color cardColor = Color(0xFF1A1C2A);

  // ── Light‐mode colours ────────────────────────────────────
  static const Color lightBackground = Color(0xFFFFFDF6);
  static const Color lightSurface = Color(0xFFFAF6E9);
  static const Color lightCard = Color(0xFFDDEB9D);

  static const Color dashboardGradientStart = Color(0xFF000000);
  static const Color dashboardGradientEnd = Color(0xFF282A3A);

  static const Color textPrimary = Color(0xFFEEEEEE);
  static const Color textSecondary = Color(0xFFBBBBBB);
  static const Color textHint = Color(0xFF888888);
  static const Color textDark = Color(0xFF2D3436);

  static const Color speedLow = Color(0xFF66BB6A);
  static const Color speedMedium = Color(0xFFFFA726);
  static const Color speedHigh = Color(0xFFFF4444);

  // Bounding box colors — red palette for vehicle detection
  static const Color boundingBoxPrimary = Color(0xFFFF1744);
  static const Color boundingBoxSecondary = Color(0xFFD50000);
  static const Color boundingBoxTertiary = Color(0xFFFF5252);

  static Color getSpeedColor(double speedKmh) {
    if (speedKmh < 30) return speedLow;
    if (speedKmh < 60) return speedMedium;
    return speedHigh;
  }

  // ═══════════════════════════════════════════════════════════
  //  DARK THEME
  // ═══════════════════════════════════════════════════════════
  static ThemeData get darkTheme {
    final fontFamily = GoogleFonts.notoSans().fontFamily;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: fontFamily,

      colorScheme: const ColorScheme.dark(
        primary: cyan,
        secondary: teal,
        tertiary: cyan,
        error: errorColor,
        surface: surfaceColor,
        onPrimary: Color(0xFF000000),
        onSecondary: Color(0xFF000000),
        onError: Colors.white,
        onSurface: textPrimary,
      ),

      scaffoldBackgroundColor: backgroundColor,

      appBarTheme: AppBarTheme(
        backgroundColor: surfaceColor,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.notoSans(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          decoration: TextDecoration.none,
        ),
      ),

      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFD4A85C),
          foregroundColor: const Color(0xFF1A1A1A),
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.notoSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFFD4A85C),
        foregroundColor: Color(0xFF1A1A1A),
        elevation: 6,
        shape: CircleBorder(),
      ),

      iconTheme: const IconThemeData(color: textPrimary, size: 24),

      textTheme: GoogleFonts.notoSansTextTheme(ThemeData.dark().textTheme),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: teal, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: errorColor, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: textHint),
      ),

      textSelectionTheme: TextSelectionThemeData(
        cursorColor: teal,
        selectionColor: teal.withOpacity(0.3),
        selectionHandleColor: teal,
      ),

      dividerTheme: const DividerThemeData(color: Color(0xFF3A3C4E), thickness: 1),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: cardColor,
        contentTextStyle: const TextStyle(color: textPrimary, decoration: TextDecoration.none),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: cyan,
        linearTrackColor: cardColor,
        circularTrackColor: cardColor,
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: teal,
        inactiveTrackColor: cardColor,
        thumbColor: cyan,
        overlayColor: teal.withOpacity(0.2),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return cyan;
          return textHint;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return teal.withOpacity(0.6);
          return cardColor;
        }),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  LIGHT THEME
  // ═══════════════════════════════════════════════════════════
  static ThemeData get lightTheme {
    final fontFamily = GoogleFonts.notoSans().fontFamily;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: fontFamily,

      colorScheme: const ColorScheme.light(
        primary: lightTan,
        secondary: lightApricot,
        tertiary: lightTan,
        error: errorColor,
        surface: lightSurface,
        onPrimary: Color(0xFF2D3436),
        onSecondary: Color(0xFF2D3436),
        onError: Colors.white,
        onSurface: textDark,
      ),

      scaffoldBackgroundColor: lightBackground,

      appBarTheme: AppBarTheme(
        backgroundColor: lightSurface,
        foregroundColor: textDark,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.notoSans(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textDark,
          decoration: TextDecoration.none,
        ),
      ),

      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFB8D89E),
          foregroundColor: const Color(0xFF2D3436),
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.notoSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFFB8D89E),
        foregroundColor: Color(0xFF2D3436),
        elevation: 6,
        shape: CircleBorder(),
      ),

      iconTheme: const IconThemeData(color: textDark, size: 24),

      textTheme: GoogleFonts.notoSansTextTheme(ThemeData.light().textTheme),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightCard,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: lightTan, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: errorColor, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: textHint),
      ),

      textSelectionTheme: TextSelectionThemeData(
        cursorColor: lightTan,
        selectionColor: lightTan.withOpacity(0.3),
        selectionHandleColor: lightTan,
      ),

      dividerTheme: const DividerThemeData(color: Color(0xFFE0E0E0), thickness: 1),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: lightCard,
        contentTextStyle: const TextStyle(color: textDark, decoration: TextDecoration.none),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: lightTan,
        linearTrackColor: Colors.grey[200],
        circularTrackColor: Colors.grey[200],
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: lightTan,
        inactiveTrackColor: Colors.grey[300],
        thumbColor: lightTan,
        overlayColor: lightTan.withOpacity(0.2),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return lightTan;
          return Colors.grey;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return lightTan.withOpacity(0.4);
          return Colors.grey[300];
        }),
      ),
    );
  }
}

/// Custom widget styles
class AppStyles {
  AppStyles._();

  static const TextStyle speedDisplay = TextStyle(
    fontSize: 72, fontWeight: FontWeight.bold, letterSpacing: -2,
    decoration: TextDecoration.none,
  );

  static const TextStyle speedUnit = TextStyle(
    fontSize: 18, fontWeight: FontWeight.w500, color: AppTheme.textSecondary,
    decoration: TextDecoration.none,
  );

  static const TextStyle plateNumber = TextStyle(
    fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'monospace',
    letterSpacing: 2, color: Colors.white, decoration: TextDecoration.none,
  );

  static const TextStyle infoLabel = TextStyle(
    fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.textHint,
    decoration: TextDecoration.none,
  );

  static const TextStyle infoValue = TextStyle(
    fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary,
    decoration: TextDecoration.none,
  );

  static const LinearGradient captureButtonGradient = LinearGradient(
    colors: [AppTheme.teal, AppTheme.cyan],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );

  static const LinearGradient dashboardGradient = LinearGradient(
    colors: [AppTheme.darkBg, AppTheme.darkSurface],
    begin: Alignment.topCenter, end: Alignment.bottomCenter,
    stops: [0.0, 1.0],
  );

  static const LinearGradient dashboardGradientLight = LinearGradient(
    colors: [AppTheme.lightPeach, AppTheme.lightTan],
    begin: Alignment.topCenter, end: Alignment.bottomCenter,
    stops: [0.0, 1.0],
  );

  static const LinearGradient overlayGradient = LinearGradient(
    colors: [Colors.black54, Colors.transparent, Colors.transparent, Colors.black54],
    stops: [0.0, 0.2, 0.8, 1.0],
    begin: Alignment.topCenter, end: Alignment.bottomCenter,
  );
}
