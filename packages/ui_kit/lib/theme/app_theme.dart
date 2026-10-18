import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_spacing.dart';

/// VIP Gold–Black design system theme.
///
/// Two modes:
///  - [lightTheme] — warm ivory/champagne background, burnished-gold accents.
///  - [darkTheme]  — deep obsidian background, luminous gold accents.
class AppTheme {
  // ── Palette constants ──────────────────────────────────────────────────────
  static const Color primaryColor  = Color(0xFFD4AF37); // Royal Burnished Gold
  static const Color primaryDark   = Color(0xFFC59B27);
  static const Color primaryLight  = Color(0xFFF3D278);
  static const Color accentColor   = Color(0xFFB8962E);

  static const Color warningColor  = Color(0xFFD97706);
  static const Color dangerColor   = Color(0xFFDC2626);
  static const Color infoColor     = Color(0xFF0284C7);

  // ── Light palette ──────────────────────────────────────────────────────────
  static const Color surfaceLight       = Color(0xFFFAF7EE);  // warm ivory
  static const Color cardLight          = Color(0xFFFFFDF8);  // cream white
  static const Color textPrimaryLight   = Color(0xFF1E1B14);
  static const Color textSecondaryLight = Color(0xFF6B5E3E);

  // ── Dark palette (deep obsidian) ───────────────────────────────────────────
  static const Color surfaceDark        = Color(0xFF0E0D0A);  // near-black
  static const Color cardDark           = Color(0xFF1A1814);  // dark charcoal
  static const Color textPrimaryDark    = Color(0xFFFBF8F0);
  static const Color textSecondaryDark  = Color(0xFFB8A882);

  // ── Border constants ───────────────────────────────────────────────────────
  static const Color _borderLight = Color(0x28C59B27);
  static const Color _borderDark  = Color(0x38D4AF37);

  // ────────────────────────────────────────────────────────────────────────────
  //  Light Theme
  // ────────────────────────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    const cs = ColorScheme(
      brightness: Brightness.light,
      primary:               primaryColor,
      onPrimary:             Color(0xFF1E1B14),
      primaryContainer:      Color(0xFFF8EEB8),
      onPrimaryContainer:    Color(0xFF4A3800),
      secondary:             accentColor,
      onSecondary:           Colors.white,
      secondaryContainer:    Color(0xFFEDD98A),
      onSecondaryContainer:  Color(0xFF3A2900),
      tertiary:              Color(0xFF8B6914),
      onTertiary:            Colors.white,
      tertiaryContainer:     Color(0xFFFFE0A0),
      onTertiaryContainer:   Color(0xFF3A2000),
      surface:               surfaceLight,
      onSurface:             textPrimaryLight,
      surfaceContainerLowest: cardLight,
      surfaceContainerLow:   Color(0xFFF3EDD8),
      surfaceContainer:      Color(0xFFEDE5C8),
      surfaceContainerHigh:  Color(0xFFE5DABC),
      surfaceContainerHighest: Color(0xFFDACD9E),
      onSurfaceVariant:      textSecondaryLight,
      error:                 dangerColor,
      onError:               Colors.white,
      errorContainer:        Color(0xFFFFDADA),
      onErrorContainer:      Color(0xFF8B0000),
      outline:               Color(0xFFCBBE8E),
      outlineVariant:        Color(0xFFE4D9B0),
      scrim:                 Color(0xFF1E1B14),
      inverseSurface:        Color(0xFF1E1B14),
      onInverseSurface:      Color(0xFFFBF8F0),
      inversePrimary:        primaryLight,
      shadow:                Color(0xFF1E1B14),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: surfaceLight,
      extensions: const [AppColors.light],

      // Typography
      textTheme: _buildTextTheme(Brightness.light),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: cardLight,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 1,
        shadowColor: primaryColor.withValues(alpha: 0.15),
        elevation: 0,
        titleTextStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: textPrimaryLight,
          letterSpacing: 0.1,
        ),
        iconTheme: const IconThemeData(color: textPrimaryLight),
        actionsIconTheme: const IconThemeData(color: textPrimaryLight),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),

      // Card
      cardTheme: CardThemeData(
        color: cardLight,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: _borderLight, width: 1),
        ),
        shadowColor: primaryColor.withValues(alpha: 0.15),
      ),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF3EDD8),
        selectedColor: primaryColor.withValues(alpha: 0.18),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        side: const BorderSide(color: _borderLight, width: 1),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      ),

      // Input
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: cardLight,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: Color(0xFFCBBE8E), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: Color(0xFFCBBE8E), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: dangerColor, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: dangerColor, width: 2),
        ),
        labelStyle: TextStyle(fontSize: 14, color: textSecondaryLight),
        hintStyle: TextStyle(fontSize: 14, color: Color(0xFF9A8A60)),
        prefixIconColor: Color(0xFF9A8A60),
        suffixIconColor: primaryDark,
      ),

      // Filled / ElevatedButton
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: const Color(0xFF1E1B14),
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.2),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: const Color(0xFF1E1B14),
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.2),
          elevation: 2,
          shadowColor: primaryColor.withValues(alpha: 0.30),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryDark,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          side: const BorderSide(color: primaryColor, width: 1.5),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.2),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryDark,
          minimumSize: const Size(48, 40),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textPrimaryLight,
          highlightColor: primaryColor.withValues(alpha: 0.12),
        ),
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: cardLight,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.xxlAll),
        titleTextStyle: const TextStyle(
          fontSize: 18, fontWeight: FontWeight.bold,
          color: textPrimaryLight, letterSpacing: 0.1,
        ),
        contentTextStyle: const TextStyle(fontSize: 14, color: textSecondaryLight),
        shadowColor: primaryColor.withValues(alpha: 0.20),
      ),

      // BottomSheet
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.topOnly(AppRadius.xxl)),
        showDragHandle: true,
        dragHandleColor: primaryColor.withValues(alpha: 0.40),
      ),

      // Navigation
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardLight,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        indicatorColor: primaryColor.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryDark);
          }
          return const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textSecondaryLight);
        }),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: cardLight,
        indicatorColor: primaryColor.withValues(alpha: 0.18),
        selectedIconTheme: const IconThemeData(color: primaryDark, size: 22),
        unselectedIconTheme: const IconThemeData(color: textSecondaryLight, size: 22),
        selectedLabelTextStyle: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.bold, color: primaryDark,
        ),
        unselectedLabelTextStyle: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w500, color: textSecondaryLight,
        ),
      ),

      // Misc
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE4D9B0), thickness: 1, space: 1,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: primaryDark,
        unselectedLabelColor: textSecondaryLight,
        indicatorColor: primaryColor,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1B14).withValues(alpha: 0.92),
          borderRadius: AppRadius.smAll,
        ),
        textStyle: const TextStyle(fontSize: 12, color: Color(0xFFFBF8F0)),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF1E1B14),
        contentTextStyle: TextStyle(color: Color(0xFFFBF8F0), fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        behavior: SnackBarBehavior.floating,
        actionTextColor: primaryLight,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryColor,
        linearTrackColor: Color(0xFFE4D9B0),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? const Color(0xFF1E1B14) : Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? primaryColor
                : const Color(0xFFCBBE8E)),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? primaryColor : Colors.transparent),
        checkColor: WidgetStateProperty.all(const Color(0xFF1E1B14)),
        side: const BorderSide(color: Color(0xFFCBBE8E), width: 1.5),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.xsAll),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
        titleTextStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimaryLight),
        subtitleTextStyle: TextStyle(fontSize: 12, color: textSecondaryLight),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  //  Dark Theme (Deep Obsidian)
  // ────────────────────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    const cs = ColorScheme(
      brightness: Brightness.dark,
      primary:               primaryLight,
      onPrimary:             Color(0xFF1A1400),
      primaryContainer:      Color(0xFF3A2C00),
      onPrimaryContainer:    Color(0xFFF3D278),
      secondary:             Color(0xFFE8C96A),
      onSecondary:           Color(0xFF3A2900),
      secondaryContainer:    Color(0xFF4A3800),
      onSecondaryContainer:  Color(0xFFFFE5A0),
      tertiary:              Color(0xFFD4A54A),
      onTertiary:            Color(0xFF3A2000),
      tertiaryContainer:     Color(0xFF4A3000),
      onTertiaryContainer:   Color(0xFFFFD580),
      surface:               surfaceDark,
      onSurface:             textPrimaryDark,
      surfaceContainerLowest: Color(0xFF0A0908),
      surfaceContainerLow:   cardDark,
      surfaceContainer:      Color(0xFF232018),
      surfaceContainerHigh:  Color(0xFF2A2720),
      surfaceContainerHighest: Color(0xFF333026),
      onSurfaceVariant:      textSecondaryDark,
      error:                 Color(0xFFF87171),
      onError:               Color(0xFF7F1D1D),
      errorContainer:        Color(0xFF5C1A1A),
      onErrorContainer:      Color(0xFFFECACA),
      outline:               Color(0xFF6B5E3E),
      outlineVariant:        Color(0xFF3D3620),
      scrim:                 Color(0xFF0A0908),
      inverseSurface:        Color(0xFFFBF8F0),
      onInverseSurface:      Color(0xFF1E1B14),
      inversePrimary:        primaryDark,
      shadow:                Color(0xFF000000),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: surfaceDark,
      extensions: const [AppColors.dark],

      textTheme: _buildTextTheme(Brightness.dark),

      appBarTheme: AppBarTheme(
        backgroundColor: cardDark,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.50),
        elevation: 0,
        titleTextStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: textPrimaryDark,
          letterSpacing: 0.1,
        ),
        iconTheme: const IconThemeData(color: textPrimaryDark),
        actionsIconTheme: const IconThemeData(color: textPrimaryDark),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),

      cardTheme: CardThemeData(
        color: cardDark,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: _borderDark, width: 1),
        ),
        shadowColor: Colors.black.withValues(alpha: 0.50),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF232018),
        selectedColor: primaryLight.withValues(alpha: 0.20),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimaryDark),
        side: const BorderSide(color: _borderDark, width: 1),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      ),

      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: cardDark,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: Color(0xFF6B5E3E), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: Color(0xFF6B5E3E), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: primaryLight, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: Color(0xFFF87171), width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: Color(0xFFF87171), width: 2),
        ),
        labelStyle: TextStyle(fontSize: 14, color: textSecondaryDark),
        hintStyle: TextStyle(fontSize: 14, color: Color(0xFF8A7A52)),
        prefixIconColor: textSecondaryDark,
        suffixIconColor: primaryLight,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: const Color(0xFF1A1400),
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.2),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: const Color(0xFF1A1400),
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.2),
          elevation: 4,
          shadowColor: primaryColor.withValues(alpha: 0.40),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryLight,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          side: const BorderSide(color: primaryColor, width: 1.5),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.2),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryLight,
          minimumSize: const Size(48, 40),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textPrimaryDark,
          highlightColor: primaryLight.withValues(alpha: 0.12),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: cardDark,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.xxlAll),
        titleTextStyle: const TextStyle(
          fontSize: 18, fontWeight: FontWeight.bold,
          color: textPrimaryDark, letterSpacing: 0.1,
        ),
        contentTextStyle: const TextStyle(fontSize: 14, color: textSecondaryDark),
        shadowColor: Colors.black.withValues(alpha: 0.60),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.topOnly(AppRadius.xxl)),
        showDragHandle: true,
        dragHandleColor: primaryColor.withValues(alpha: 0.50),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardDark,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryColor.withValues(alpha: 0.22),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryLight);
          }
          return const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textSecondaryDark);
        }),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: cardDark,
        indicatorColor: primaryColor.withValues(alpha: 0.22),
        selectedIconTheme: const IconThemeData(color: primaryLight, size: 22),
        unselectedIconTheme: const IconThemeData(color: textSecondaryDark, size: 22),
        selectedLabelTextStyle: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.bold, color: primaryLight,
        ),
        unselectedLabelTextStyle: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w500, color: textSecondaryDark,
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: Color(0xFF3D3620), thickness: 1, space: 1,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: primaryLight,
        unselectedLabelColor: textSecondaryDark,
        indicatorColor: primaryLight,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF2E2A1A).withValues(alpha: 0.96),
          borderRadius: AppRadius.smAll,
          border: Border.all(color: const Color(0xFF6B5E3E), width: 1),
        ),
        textStyle: const TextStyle(fontSize: 12, color: textPrimaryDark),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF232018),
        contentTextStyle: TextStyle(color: textPrimaryDark, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: _borderDark, width: 1),
        ),
        behavior: SnackBarBehavior.floating,
        actionTextColor: primaryLight,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryLight,
        linearTrackColor: Color(0xFF3D3620),
        refreshBackgroundColor: cardDark,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? const Color(0xFF1A1400) : const Color(0xFF8A7A52)),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? primaryColor : const Color(0xFF3D3620)),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? primaryColor : Colors.transparent),
        checkColor: WidgetStateProperty.all(const Color(0xFF1A1400)),
        side: const BorderSide(color: Color(0xFF6B5E3E), width: 1.5),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.xsAll),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
        titleTextStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimaryDark),
        subtitleTextStyle: TextStyle(fontSize: 12, color: textSecondaryDark),
      ),
    );
  }

  // ── Typography ─────────────────────────────────────────────────────────────
  static TextTheme _buildTextTheme(Brightness brightness) {
    final base = brightness == Brightness.light ? textPrimaryLight : textPrimaryDark;
    final muted = brightness == Brightness.light ? textSecondaryLight : textSecondaryDark;

    return TextTheme(
      displayLarge:  TextStyle(fontSize: 57, fontWeight: FontWeight.w300, color: base,  letterSpacing: -0.25),
      displayMedium: TextStyle(fontSize: 45, fontWeight: FontWeight.w300, color: base),
      displaySmall:  TextStyle(fontSize: 36, fontWeight: FontWeight.w400, color: base),
      headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: base),
      headlineMedium:TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: base),
      headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: base),
      titleLarge:    TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: base,  letterSpacing: 0.0),
      titleMedium:   TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: base,  letterSpacing: 0.1),
      titleSmall:    TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: base,  letterSpacing: 0.1),
      bodyLarge:     TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: base),
      bodyMedium:    TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: base),
      bodySmall:     TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: muted),
      labelLarge:    TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: base,  letterSpacing: 0.1),
      labelMedium:   TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: muted, letterSpacing: 0.5),
      labelSmall:    TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: muted, letterSpacing: 0.5),
    );
  }
}
