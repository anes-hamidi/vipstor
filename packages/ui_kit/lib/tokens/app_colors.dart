import 'package:flutter/material.dart';

/// Semantic color tokens for the VIP Gold-Black luxury design system.
///
/// Two modes:
///  - [light] — Warm ivory/champagne background, burnished-gold accents.
///  - [dark]  — Deep obsidian background, luminous gold accents.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    // ── Status ──────────────────────────────────────────────────────────────
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.error,
    this.onError = Colors.white,
    this.errorContainer = const Color(0xFFFFDADA),
    this.onErrorContainer = const Color(0xFF8B0000),
    // ── Order/document states ────────────────────────────────────────────────
    required this.draft,
    required this.onDraft,
    required this.pending,
    required this.onPending,
    required this.posted,
    required this.onPosted,
    required this.cancelled,
    required this.onCancelled,

    // ── VIP Gold branding ────────────────────────────────────────────────────
    this.gold           = const Color(0xFFD4AF37),
    this.onGold         = const Color(0xFF1E1702),
    this.goldContainer  = const Color(0xFFFBF4DC),
    this.onGoldContainer= const Color(0xFF6E5107),
    this.goldDark       = const Color(0xFF9A7319),
    this.goldLight      = const Color(0xFFF3D278),
    this.goldBorder     = const Color(0x40D4AF37),
    this.goldMuted      = const Color(0x1AD4AF37),
    // ── Obsidian black branding ──────────────────────────────────────────────
    this.obsidian        = const Color(0xFF0E0D0A),
    this.onObsidian      = const Color(0xFFFBF8F0),
    this.obsidianSurface = const Color(0xFF1A1814),
    this.obsidianCard    = const Color(0xFF232018),
    this.obsidianMuted   = const Color(0x2A000000),
    // ── Shine / shimmer ──────────────────────────────────────────────────────
    this.shimmerBase     = const Color(0xFFEDE3B8),
    this.shimmerHighlight= const Color(0xFFFFFBEE),
  });

  // Status
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;
  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;

  // Doc states
  final Color draft;
  final Color onDraft;
  final Color pending;
  final Color onPending;
  final Color posted;
  final Color onPosted;
  final Color cancelled;
  final Color onCancelled;

  // Gold
  final Color gold;
  final Color onGold;
  final Color goldContainer;
  final Color onGoldContainer;
  final Color goldDark;
  final Color goldLight;
  final Color goldBorder;
  final Color goldMuted;

  // Obsidian
  final Color obsidian;
  final Color onObsidian;
  final Color obsidianSurface;
  final Color obsidianCard;
  final Color obsidianMuted;

  // Shimmer
  final Color shimmerBase;
  final Color shimmerHighlight;

  // ── Presets ─────────────────────────────────────────────────────────────────

  /// Derives the legacy semantic token surface from an active role scheme.
  ///
  /// Widgets that still consume gold/obsidian aliases automatically inherit
  /// the current workspace accent instead of falling back to a fixed palette.
  factory AppColors.fromColorScheme(ColorScheme scheme) {
    final AppColors base = scheme.brightness == Brightness.dark
        ? AppColors.dark
        : AppColors.light;
    return base.copyWith(
      gold: scheme.primary,
      onGold: scheme.onPrimary,
      goldContainer: scheme.primaryContainer,
      onGoldContainer: scheme.onPrimaryContainer,
      goldDark: scheme.primary,
      goldLight: scheme.primary,
      goldBorder: scheme.primary.withValues(alpha: 0.28),
      goldMuted: scheme.primary.withValues(alpha: 0.12),
      obsidian: scheme.inverseSurface,
      onObsidian: scheme.onInverseSurface,
      obsidianSurface: scheme.surface,
      obsidianCard: scheme.surfaceContainerLow,
      obsidianMuted: scheme.onSurface.withValues(alpha: 0.08),
      shimmerBase: scheme.surfaceContainerHighest,
      shimmerHighlight: scheme.surfaceContainerLow,
    );
  }

  static const AppColors light = AppColors(
    success:              Color(0xFF059669),
    onSuccess:            Colors.white,
    successContainer:     Color(0xFFD1FAE5),
    onSuccessContainer:   Color(0xFF065F46),
    warning:              Color(0xFFD97706),
    onWarning:            Colors.white,
    warningContainer:     Color(0xFFFEF3C7),
    onWarningContainer:   Color(0xFF92400E),
    info:                 Color(0xFF0284C7),
    onInfo:               Colors.white,
    infoContainer:        Color(0xFFE0F2FE),
    onInfoContainer:      Color(0xFF075985),
    draft:                Color(0xFF64748B),
    onDraft:              Colors.white,
    pending:              Color(0xFFD97706),
    onPending:            Colors.white,
    posted:               Color(0xFF059669),
    onPosted:             Colors.white,
    cancelled:            Color(0xFFDC2626),
    onCancelled:          Colors.white,
    error:                Color(0xFFDC2626),
    onError:              Colors.white,
    errorContainer:       Color(0xFFFFDADA),
    onErrorContainer:     Color(0xFF8B0000),
    gold:                 Color(0xFFC59B27),
    onGold:               Color(0xFF1E1702),
    goldContainer:        Color(0xFFFBF4DC),
    onGoldContainer:      Color(0xFF6E5107),
    goldDark:             Color(0xFF9A7319),
    goldLight:            Color(0xFFF3D278),
    goldBorder:           Color(0x40C59B27),
    goldMuted:            Color(0x14C59B27),
    obsidian:             Color(0xFF0E0D0A),
    onObsidian:           Color(0xFFFBF8F0),
    obsidianSurface:      Color(0xFFF5EDD8),
    obsidianCard:         Color(0xFFFFFDF7),
    obsidianMuted:        Color(0x0A1E1B14),
    shimmerBase:          Color(0xFFEDE3B8),
    shimmerHighlight:     Color(0xFFFFFBEE),
  );

  static const AppColors dark = AppColors(
    success:              Color(0xFF34D399),
    onSuccess:            Color(0xFF064E3B),
    successContainer:     Color(0xFF065F46),
    onSuccessContainer:   Color(0xFFA7F3D0),
    warning:              Color(0xFFFBBF24),
    onWarning:            Color(0xFF78350F),
    warningContainer:     Color(0xFF92400E),
    onWarningContainer:   Color(0xFFFDE68A),
    info:                 Color(0xFF38BDF8),
    onInfo:               Color(0xFF0C4A6E),
    infoContainer:        Color(0xFF075985),
    onInfoContainer:      Color(0xFFBAE6FD),
    draft:                Color(0xFF94A3B8),
    onDraft:              Color(0xFF0F172A),
    pending:              Color(0xFFFBBF24),
    onPending:            Color(0xFF78350F),
    posted:               Color(0xFF34D399),
    onPosted:             Color(0xFF064E3B),
    cancelled:            Color(0xFFF87171),
    onCancelled:          Color(0xFF7F1D1D),
    error:                Color(0xFFF87171),
    onError:              Color(0xFF7F1D1D),
    errorContainer:       Color(0xFF5C1A1A),
    onErrorContainer:     Color(0xFFFECACA),
    gold:                 Color(0xFFE8C547),
    onGold:               Color(0xFF1A1400),
    goldContainer:        Color(0xFF2E2508),
    onGoldContainer:      Color(0xFFFEE8A2),
    goldDark:             Color(0xFFC59B27),
    goldLight:            Color(0xFFFFF0BF),
    goldBorder:           Color(0x40E8C547),
    goldMuted:            Color(0x18E8C547),
    obsidian:             Color(0xFF0A0908),
    onObsidian:           Color(0xFFFBF8F0),
    obsidianSurface:      Color(0xFF12110D),
    obsidianCard:         Color(0xFF1E1B14),
    obsidianMuted:        Color(0x18FFFFFF),
    shimmerBase:          Color(0xFF2E2A1A),
    shimmerHighlight:     Color(0xFF4A4228),
  );

  // ── ThemeExtension ───────────────────────────────────────────────────────────

  @override
  AppColors copyWith({
    Color? success, Color? onSuccess, Color? successContainer, Color? onSuccessContainer,
    Color? warning, Color? onWarning, Color? warningContainer, Color? onWarningContainer,
    Color? info, Color? onInfo, Color? infoContainer, Color? onInfoContainer,
    Color? error, Color? onError, Color? errorContainer, Color? onErrorContainer,
    Color? draft, Color? onDraft, Color? pending, Color? onPending,
    Color? posted, Color? onPosted, Color? cancelled, Color? onCancelled,
    Color? gold, Color? onGold, Color? goldContainer, Color? onGoldContainer,
    Color? goldDark, Color? goldLight, Color? goldBorder, Color? goldMuted,
    Color? obsidian, Color? onObsidian, Color? obsidianSurface, Color? obsidianCard,
    Color? obsidianMuted, Color? shimmerBase, Color? shimmerHighlight,
  }) =>
      AppColors(
        success: success ?? this.success,
        onSuccess: onSuccess ?? this.onSuccess,
        successContainer: successContainer ?? this.successContainer,
        onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
        warning: warning ?? this.warning,
        onWarning: onWarning ?? this.onWarning,
        warningContainer: warningContainer ?? this.warningContainer,
        onWarningContainer: onWarningContainer ?? this.onWarningContainer,
        info: info ?? this.info,
        onInfo: onInfo ?? this.onInfo,
        infoContainer: infoContainer ?? this.infoContainer,
        onInfoContainer: onInfoContainer ?? this.onInfoContainer,
        error: error ?? this.error,
        onError: onError ?? this.onError,
        errorContainer: errorContainer ?? this.errorContainer,
        onErrorContainer: onErrorContainer ?? this.onErrorContainer,
        draft: draft ?? this.draft,
        onDraft: onDraft ?? this.onDraft,
        pending: pending ?? this.pending,
        onPending: onPending ?? this.onPending,
        posted: posted ?? this.posted,
        onPosted: onPosted ?? this.onPosted,
        cancelled: cancelled ?? this.cancelled,
        onCancelled: onCancelled ?? this.onCancelled,
        gold: gold ?? this.gold,
        onGold: onGold ?? this.onGold,
        goldContainer: goldContainer ?? this.goldContainer,
        onGoldContainer: onGoldContainer ?? this.onGoldContainer,
        goldDark: goldDark ?? this.goldDark,
        goldLight: goldLight ?? this.goldLight,
        goldBorder: goldBorder ?? this.goldBorder,
        goldMuted: goldMuted ?? this.goldMuted,
        obsidian: obsidian ?? this.obsidian,
        onObsidian: onObsidian ?? this.onObsidian,
        obsidianSurface: obsidianSurface ?? this.obsidianSurface,
        obsidianCard: obsidianCard ?? this.obsidianCard,
        obsidianMuted: obsidianMuted ?? this.obsidianMuted,
        shimmerBase: shimmerBase ?? this.shimmerBase,
        shimmerHighlight: shimmerHighlight ?? this.shimmerHighlight,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer: Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer: Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
      error: Color.lerp(error, other.error, t)!,
      onError: Color.lerp(onError, other.onError, t)!,
      errorContainer: Color.lerp(errorContainer, other.errorContainer, t)!,
      onErrorContainer: Color.lerp(onErrorContainer, other.onErrorContainer, t)!,
      draft: Color.lerp(draft, other.draft, t)!,
      onDraft: Color.lerp(onDraft, other.onDraft, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
      onPending: Color.lerp(onPending, other.onPending, t)!,
      posted: Color.lerp(posted, other.posted, t)!,
      onPosted: Color.lerp(onPosted, other.onPosted, t)!,
      cancelled: Color.lerp(cancelled, other.cancelled, t)!,
      onCancelled: Color.lerp(onCancelled, other.onCancelled, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      onGold: Color.lerp(onGold, other.onGold, t)!,
      goldContainer: Color.lerp(goldContainer, other.goldContainer, t)!,
      onGoldContainer: Color.lerp(onGoldContainer, other.onGoldContainer, t)!,
      goldDark: Color.lerp(goldDark, other.goldDark, t)!,
      goldLight: Color.lerp(goldLight, other.goldLight, t)!,
      goldBorder: Color.lerp(goldBorder, other.goldBorder, t)!,
      goldMuted: Color.lerp(goldMuted, other.goldMuted, t)!,
      obsidian: Color.lerp(obsidian, other.obsidian, t)!,
      onObsidian: Color.lerp(onObsidian, other.onObsidian, t)!,
      obsidianSurface: Color.lerp(obsidianSurface, other.obsidianSurface, t)!,
      obsidianCard: Color.lerp(obsidianCard, other.obsidianCard, t)!,
      obsidianMuted: Color.lerp(obsidianMuted, other.obsidianMuted, t)!,
      shimmerBase: Color.lerp(shimmerBase, other.shimmerBase, t)!,
      shimmerHighlight: Color.lerp(shimmerHighlight, other.shimmerHighlight, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get appColors {
    final ThemeData theme = Theme.of(this);
    return theme.extension<AppColors>() ??
        AppColors.fromColorScheme(theme.colorScheme);
  }
}
