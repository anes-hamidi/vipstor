import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_role.dart';
import 'role_theme_extension.dart';

/// Role-aware Material 3 theme factory for the five operating spaces.
///
/// Palettes are intentionally separated by hue family:
///
/// * Customer  - boutique teal with warm brass accents.
/// * Cashier   - high-visibility cobalt terminal blue.
/// * Inventory - forest green warehouse control.
/// * Delivery  - road-sign amber and rust for outdoor use.
/// * Moderator - deep plum for investigation and audit work.
///
/// Every role defines a complete light and dark [ColorScheme]. Primary,
/// container and surface pairs are selected to meet WCAG AA body-text
/// contrast, while restrained surfaces keep dense grids and ledgers readable
/// during long shifts.
abstract final class AppTheme {
  /// Builds a complete theme for [role] and [brightness].
  static ThemeData createTheme(AppRole role, Brightness brightness) {
    final _RolePalette palette = _RolePalette.of(role, brightness);
    final ColorScheme scheme = palette.colorScheme;
    final bool isDark = brightness == Brightness.dark;

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
    );
    final TextTheme textTheme = _buildTextTheme(base.textTheme, scheme);

    final RoundedRectangleBorder cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: scheme.outlineVariant),
    );
    final RoundedRectangleBorder controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: scheme.outlineVariant),
    );

    final RoleThemeExtension roleExtension = RoleThemeExtension(
      role: role,
      roleBrandColor: scheme.primary,
      badgeBackground: scheme.primaryContainer,
      badgeText: scheme.onPrimaryContainer,
      roleLabel: palette.label,
    );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      cardColor: scheme.surfaceContainerLow,
      dividerColor: scheme.outlineVariant,
      disabledColor: scheme.onSurface.withValues(alpha: 0.38),
      visualDensity:
          role.isStaff ? VisualDensity.compact : VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      extensions: <ThemeExtension<dynamic>>[roleExtension],
      textTheme: textTheme,
      primaryTextTheme: textTheme.apply(
        bodyColor: scheme.onPrimary,
        displayColor: scheme.onPrimary,
      ),

      // A flat app bar keeps the maximum vertical space available for dense
      // operational content and avoids double elevation against cards.
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        centerTitle: false,
        titleSpacing: 16,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
        actionsIconTheme: IconThemeData(color: scheme.onSurface),
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),

      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shadowColor: scheme.shadow.withValues(alpha: 0.10),
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: cardShape,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: controlShape,
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          elevation: 0,
          shape: controlShape,
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          side: BorderSide(color: scheme.outline),
          shape: controlShape,
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(48, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: controlShape,
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          highlightColor: scheme.primary.withValues(alpha: 0.10),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.primaryContainer,
        disabledColor: scheme.surfaceContainerHighest,
        labelStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onPrimaryContainer,
        ),
        checkmarkColor: scheme.onPrimaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),

      listTileTheme: ListTileThemeData(
        dense: role.isStaff,
        minVerticalPadding: 6,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),

      dataTableTheme: DataTableThemeData(
        headingRowHeight: 40,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 48,
        horizontalMargin: 16,
        columnSpacing: 24,
        headingRowColor: WidgetStatePropertyAll<Color?>(
          scheme.surfaceContainerHigh,
        ),
        headingTextStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
        dataTextStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onSurface,
        ),
        dividerThickness: 1,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surfaceContainerLowest,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color:
                selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          );
        }),
      ),

      navigationRailTheme: NavigationRailThemeData(
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(
          size: 22,
          color: scheme.onPrimaryContainer,
        ),
        unselectedIconTheme: IconThemeData(
          size: 22,
          color: scheme.onSurfaceVariant,
        ),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        dividerColor: scheme.outlineVariant,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
          return states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest;
        }),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll<Color>(scheme.onPrimary),
        side: BorderSide(color: scheme.outline, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.outline;
        }),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: 0.28),
        selectionHandleColor: scheme.primary,
      ),

      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll<Color>(
          scheme.onSurface.withValues(alpha: 0.24),
        ),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll<double>(6),
      ),
    );
  }

  /// Default customer storefront light theme.
  ///
  /// Kept as a convenience for isolated widget previews and backwards
  /// compatibility. Application roots should consume the reactive providers.
  static ThemeData get lightTheme =>
      createTheme(AppRole.customer, Brightness.light);

  /// Default customer storefront dark theme.
  static ThemeData get darkTheme =>
      createTheme(AppRole.customer, Brightness.dark);

  static TextTheme _buildTextTheme(TextTheme base, ColorScheme scheme) {
    final TextTheme themed = base.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    return themed.copyWith(
      displayLarge: themed.displayLarge?.copyWith(
        fontWeight: FontWeight.w300,
        letterSpacing: -0.25,
      ),
      displayMedium: themed.displayMedium?.copyWith(
        fontWeight: FontWeight.w300,
      ),
      headlineLarge: themed.headlineLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: themed.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: themed.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      titleLarge: themed.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      titleMedium: themed.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      titleSmall: themed.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      bodySmall: themed.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: themed.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      labelMedium: themed.labelMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      labelSmall: themed.labelSmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

/// One complete role palette in one brightness mode.
@immutable
class _RolePalette {
  const _RolePalette({
    required this.label,
    required this.colorScheme,
  });

  final String label;
  final ColorScheme colorScheme;

  static _RolePalette of(AppRole role, Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    return switch (role) {
      AppRole.customer => isDark ? _customerDark : _customerLight,
      AppRole.cashier => isDark ? _cashierDark : _cashierLight,
      AppRole.inventory => isDark ? _inventoryDark : _inventoryLight,
      AppRole.delivery => isDark ? _deliveryDark : _deliveryLight,
      AppRole.moderator => isDark ? _moderatorDark : _moderatorLight,
    };
  }

  // ---------------------------------------------------------------------------
  // Customer: Algomend — Digital Systems & Enterprise Solutions.
  // Brand primary: #1DAB61 (Wrench Green), deep: #034F40 (Circuit Teal).
  // ---------------------------------------------------------------------------
  static const _RolePalette _customerLight = _RolePalette(
    label: 'Algomend',
    colorScheme: ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF1DAB61),        // Wrench Green
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFB6F0D2),
      onPrimaryContainer: Color(0xFF003920),
      secondary: Color(0xFF034F40),      // Circuit Teal
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFA8D9CC),
      onSecondaryContainer: Color(0xFF001A13),
      tertiary: Color(0xFF4A6358),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFCCE8DA),
      onTertiaryContainer: Color(0xFF071F17),
      error: Color(0xFFBA1A1A),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: Color(0xFFF6FAF7),
      onSurface: Color(0xFF111111),      // Typography Black
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFEEF5F0),
      surfaceContainer: Color(0xFFE7F0EA),
      surfaceContainerHigh: Color(0xFFDFEBE3),
      surfaceContainerHighest: Color(0xFFD7E5DC),
      onSurfaceVariant: Color(0xFF333333),  // Tagline Gray
      outline: Color(0xFF5A7066),
      outlineVariant: Color(0xFFB2C9BC),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF1E2D26),
      onInverseSurface: Color(0xFFECF4EE),
      inversePrimary: Color(0xFF72DFA0),
      shadow: Color(0xFF000000),
    ),
  );

  static const _RolePalette _customerDark = _RolePalette(
    label: 'Algomend',
    colorScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF72DFA0),        // lighter Wrench Green on dark
      onPrimary: Color(0xFF003920),
      primaryContainer: Color(0xFF005C36),
      onPrimaryContainer: Color(0xFFB6F0D2),
      secondary: Color(0xFF6BBDA8),      // lighter Circuit Teal on dark
      onSecondary: Color(0xFF003829),
      secondaryContainer: Color(0xFF01453A),
      onSecondaryContainer: Color(0xFFA8D9CC),
      tertiary: Color(0xFFB0CCBF),
      onTertiary: Color(0xFF1C352C),
      tertiaryContainer: Color(0xFF334B41),
      onTertiaryContainer: Color(0xFFCCE8DA),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: Color(0xFF0B130F),
      onSurface: Color(0xFFDCE9E1),
      surfaceContainerLowest: Color(0xFF060E09),
      surfaceContainerLow: Color(0xFF131B16),
      surfaceContainer: Color(0xFF171F1A),
      surfaceContainerHigh: Color(0xFF212A24),
      surfaceContainerHighest: Color(0xFF2C352F),
      onSurfaceVariant: Color(0xFFB2C9BC),
      outline: Color(0xFF7D9D8D),
      outlineVariant: Color(0xFF334B41),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFDCE9E1),
      onInverseSurface: Color(0xFF1E2D26),
      inversePrimary: Color(0xFF1DAB61),
      shadow: Color(0xFF000000),
    ),
  );

  // ---------------------------------------------------------------------------
  // Cashier: high-visibility cobalt terminal blue.
  // ---------------------------------------------------------------------------
  static const _RolePalette _cashierLight = _RolePalette(
    label: 'Cashier POS',
    colorScheme: ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF004A9E),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFD9E2FF),
      onPrimaryContainer: Color(0xFF001B3E),
      secondary: Color(0xFF00639B),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFCEE5FF),
      onSecondaryContainer: Color(0xFF001D33),
      tertiary: Color(0xFF4F5F7D),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFD7E3FF),
      onTertiaryContainer: Color(0xFF0A1B36),
      error: Color(0xFFBA1A1A),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: Color(0xFFFAF9FD),
      onSurface: Color(0xFF1A1C1E),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF3F3F7),
      surfaceContainer: Color(0xFFEDEDF1),
      surfaceContainerHigh: Color(0xFFE7E8EB),
      surfaceContainerHighest: Color(0xFFE2E2E6),
      onSurfaceVariant: Color(0xFF43474E),
      outline: Color(0xFF73777F),
      outlineVariant: Color(0xFFC3C6CF),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF2F3033),
      onInverseSurface: Color(0xFFF1F0F4),
      inversePrimary: Color(0xFFADC6FF),
      shadow: Color(0xFF000000),
    ),
  );

  static const _RolePalette _cashierDark = _RolePalette(
    label: 'Cashier POS',
    colorScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFADC6FF),
      onPrimary: Color(0xFF002F65),
      primaryContainer: Color(0xFF00458F),
      onPrimaryContainer: Color(0xFFD9E2FF),
      secondary: Color(0xFF96CCFF),
      onSecondary: Color(0xFF003353),
      secondaryContainer: Color(0xFF004A75),
      onSecondaryContainer: Color(0xFFCEE5FF),
      tertiary: Color(0xFFB6C6E5),
      onTertiary: Color(0xFF20314A),
      tertiaryContainer: Color(0xFF374762),
      onTertiaryContainer: Color(0xFFD7E3FF),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: Color(0xFF111318),
      onSurface: Color(0xFFE2E2E6),
      surfaceContainerLowest: Color(0xFF0C0E12),
      surfaceContainerLow: Color(0xFF191C20),
      surfaceContainer: Color(0xFF1D2024),
      surfaceContainerHigh: Color(0xFF282A2F),
      surfaceContainerHighest: Color(0xFF32353A),
      onSurfaceVariant: Color(0xFFC3C6CF),
      outline: Color(0xFF8D9199),
      outlineVariant: Color(0xFF43474E),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFE2E2E6),
      onInverseSurface: Color(0xFF2F3033),
      inversePrimary: Color(0xFF004A9E),
      shadow: Color(0xFF000000),
    ),
  );

  // ---------------------------------------------------------------------------
  // Inventory: forest green warehouse control.
  // ---------------------------------------------------------------------------
  static const _RolePalette _inventoryLight = _RolePalette(
    label: 'Inventory Control',
    colorScheme: ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF1F6B3B),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFA9F5B7),
      onPrimaryContainer: Color(0xFF00210A),
      secondary: Color(0xFF52634F),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFD5E8D0),
      onSecondaryContainer: Color(0xFF101F0E),
      tertiary: Color(0xFF3A656D),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFBEEAF3),
      onTertiaryContainer: Color(0xFF001F25),
      error: Color(0xFFBA1A1A),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: Color(0xFFF8FAF5),
      onSurface: Color(0xFF191D17),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF2F5EF),
      surfaceContainer: Color(0xFFECEFEA),
      surfaceContainerHigh: Color(0xFFE6E9E3),
      surfaceContainerHighest: Color(0xFFE1E4DE),
      onSurfaceVariant: Color(0xFF40493F),
      outline: Color(0xFF70796E),
      outlineVariant: Color(0xFFC0C9BC),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF2D322C),
      onInverseSurface: Color(0xFFEFF1EB),
      inversePrimary: Color(0xFF8ED6A0),
      shadow: Color(0xFF000000),
    ),
  );

  static const _RolePalette _inventoryDark = _RolePalette(
    label: 'Inventory Control',
    colorScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF8ED6A0),
      onPrimary: Color(0xFF003917),
      primaryContainer: Color(0xFF005226),
      onPrimaryContainer: Color(0xFFA9F5B7),
      secondary: Color(0xFFB9CCB4),
      onSecondary: Color(0xFF253423),
      secondaryContainer: Color(0xFF3B4B39),
      onSecondaryContainer: Color(0xFFD5E8D0),
      tertiary: Color(0xFFA2CED7),
      onTertiary: Color(0xFF00363D),
      tertiaryContainer: Color(0xFF214E55),
      onTertiaryContainer: Color(0xFFBEEAF3),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: Color(0xFF101510),
      onSurface: Color(0xFFE0E4DA),
      surfaceContainerLowest: Color(0xFF0B0F0B),
      surfaceContainerLow: Color(0xFF181D17),
      surfaceContainer: Color(0xFF1C211B),
      surfaceContainerHigh: Color(0xFF262B25),
      surfaceContainerHighest: Color(0xFF31362F),
      onSurfaceVariant: Color(0xFFC0C9BC),
      outline: Color(0xFF8A9386),
      outlineVariant: Color(0xFF40493F),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFE0E4DA),
      onInverseSurface: Color(0xFF2D322C),
      inversePrimary: Color(0xFF1F6B3B),
      shadow: Color(0xFF000000),
    ),
  );

  // ---------------------------------------------------------------------------
  // Delivery: road-sign amber and rust for outdoor visibility.
  // ---------------------------------------------------------------------------
  static const _RolePalette _deliveryLight = _RolePalette(
    label: 'Delivery Dispatch',
    colorScheme: ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF9A4600),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFFFDBC8),
      onPrimaryContainer: Color(0xFF351000),
      secondary: Color(0xFF7A5900),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFFFDF9E),
      onSecondaryContainer: Color(0xFF261A00),
      tertiary: Color(0xFF56624C),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFDAE8CB),
      onTertiaryContainer: Color(0xFF141F0D),
      error: Color(0xFFBA1A1A),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: Color(0xFFFFF8F4),
      onSurface: Color(0xFF221A15),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFFDF1EA),
      surfaceContainer: Color(0xFFF8EBE3),
      surfaceContainerHigh: Color(0xFFF2E5DD),
      surfaceContainerHighest: Color(0xFFEDE0D8),
      onSurfaceVariant: Color(0xFF54433A),
      outline: Color(0xFF877368),
      outlineVariant: Color(0xFFDAC3B7),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF382E29),
      onInverseSurface: Color(0xFFFFEDE5),
      inversePrimary: Color(0xFFFFB688),
      shadow: Color(0xFF000000),
    ),
  );

  static const _RolePalette _deliveryDark = _RolePalette(
    label: 'Delivery Dispatch',
    colorScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFFFB688),
      onPrimary: Color(0xFF532200),
      primaryContainer: Color(0xFF763300),
      onPrimaryContainer: Color(0xFFFFDBC8),
      secondary: Color(0xFFF0C048),
      onSecondary: Color(0xFF3F2E00),
      secondaryContainer: Color(0xFF5C4500),
      onSecondaryContainer: Color(0xFFFFDF9E),
      tertiary: Color(0xFFBECBAD),
      onTertiary: Color(0xFF29341F),
      tertiaryContainer: Color(0xFF3F4B34),
      onTertiaryContainer: Color(0xFFDAE8CB),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: Color(0xFF1A120D),
      onSurface: Color(0xFFF0E0D6),
      surfaceContainerLowest: Color(0xFF120A06),
      surfaceContainerLow: Color(0xFF221A15),
      surfaceContainer: Color(0xFF271F19),
      surfaceContainerHigh: Color(0xFF322923),
      surfaceContainerHighest: Color(0xFF3D342D),
      onSurfaceVariant: Color(0xFFDAC3B7),
      outline: Color(0xFFA38C80),
      outlineVariant: Color(0xFF54433A),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFF0E0D6),
      onInverseSurface: Color(0xFF382E29),
      inversePrimary: Color(0xFF9A4600),
      shadow: Color(0xFF000000),
    ),
  );

  // ---------------------------------------------------------------------------
  // Moderator: deep plum investigation console.
  // ---------------------------------------------------------------------------
  static const _RolePalette _moderatorLight = _RolePalette(
    label: 'Moderator Console',
    colorScheme: ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF6B4A8E),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFEDDCFF),
      onPrimaryContainer: Color(0xFF28104A),
      secondary: Color(0xFF625B71),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFE8DEF8),
      onSecondaryContainer: Color(0xFF1D192B),
      tertiary: Color(0xFF7D5260),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFFFD8E4),
      onTertiaryContainer: Color(0xFF31101D),
      error: Color(0xFFBA1A1A),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: Color(0xFFFBF8FD),
      onSurface: Color(0xFF1C1B1E),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF5F2FA),
      surfaceContainer: Color(0xFFEFECF3),
      surfaceContainerHigh: Color(0xFFE9E6ED),
      surfaceContainerHighest: Color(0xFFE4E1E8),
      onSurfaceVariant: Color(0xFF49454F),
      outline: Color(0xFF79747E),
      outlineVariant: Color(0xFFCAC4D0),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF313033),
      onInverseSurface: Color(0xFFF4EFF4),
      inversePrimary: Color(0xFFD7B8FF),
      shadow: Color(0xFF000000),
    ),
  );

  static const _RolePalette _moderatorDark = _RolePalette(
    label: 'Moderator Console',
    colorScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFD7B8FF),
      onPrimary: Color(0xFF3D2061),
      primaryContainer: Color(0xFF543878),
      onPrimaryContainer: Color(0xFFEDDCFF),
      secondary: Color(0xFFCCC2DC),
      onSecondary: Color(0xFF332D41),
      secondaryContainer: Color(0xFF4A4458),
      onSecondaryContainer: Color(0xFFE8DEF8),
      tertiary: Color(0xFFEFB8C8),
      onTertiary: Color(0xFF492532),
      tertiaryContainer: Color(0xFF633B48),
      onTertiaryContainer: Color(0xFFFFD8E4),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: Color(0xFF151218),
      onSurface: Color(0xFFE6E1E9),
      surfaceContainerLowest: Color(0xFF0F0C12),
      surfaceContainerLow: Color(0xFF1D1A20),
      surfaceContainer: Color(0xFF211E25),
      surfaceContainerHigh: Color(0xFF2C2830),
      surfaceContainerHighest: Color(0xFF37333A),
      onSurfaceVariant: Color(0xFFCAC4D0),
      outline: Color(0xFF948F9A),
      outlineVariant: Color(0xFF49454F),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFE6E1E9),
      onInverseSurface: Color(0xFF313033),
      inversePrimary: Color(0xFF6B4A8E),
      shadow: Color(0xFF000000),
    ),
  );
}
