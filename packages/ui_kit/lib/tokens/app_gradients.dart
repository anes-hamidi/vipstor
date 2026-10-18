import 'package:flutter/material.dart';

/// Luxury gradient tokens for the VIP Gold–Black design system.
///
/// Usage: `decoration: BoxDecoration(gradient: AppGradients.gold)`
abstract final class AppGradients {
  // ── Gold Gradients ─────────────────────────────────────────────────────────

  /// Royal Metallic Gold — deep burnished gold to bright luminous gold.
  /// Use for primary CTAs, highlight borders, VIP badges.
  static const LinearGradient gold = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: [
      Color(0xFFEDD066), // champagne highlight
      Color(0xFFD4AF37), // burnished gold
      Color(0xFFC59B27), // mid gold
      Color(0xFFA67C1E), // deep amber
    ],
    stops: [0.0, 0.35, 0.70, 1.0],
  );

  /// Luminous Gold — bright champagne to warm gold.
  /// Use for button hover/focus states and glow rings.
  static const LinearGradient goldLuminous = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: [
      Color(0xFFFFF5CC),
      Color(0xFFF5CE60),
      Color(0xFFD4AF37),
    ],
  );

  /// Gold Foil — four-stop metallic sheen with a bright mid-flash.
  /// Use for luxury card top-edge accents and progress bars.
  static const LinearGradient goldFoil = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFFA67C1E),
      Color(0xFFD4AF37),
      Color(0xFFFFF0A0),
      Color(0xFFD4AF37),
      Color(0xFF9A7319),
    ],
    stops: [0.0, 0.25, 0.50, 0.75, 1.0],
  );

  /// Subtle Champagne — soft ambient tint for luxury card surfaces (light mode).
  static const LinearGradient goldSubtleLight = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: [
      Color(0xFFFFFDF9),
      Color(0xFFFBF6E9),
      Color(0xFFF3E8C8),
    ],
  );

  /// Hairline Gold Border — subtle metallic sheen for decorative borders.
  static const LinearGradient goldBorder = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: [
      Color(0x90D4AF37),
      Color(0x40C59B27),
      Color(0x70D4AF37),
    ],
  );

  // ── Obsidian / Dark Gradients ──────────────────────────────────────────────

  /// Deep Obsidian — pitch-black to dark charcoal.
  /// Use for dark-mode scaffold backgrounds and premium panels.
  static const LinearGradient obsidian = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF0A0908),
      Color(0xFF141210),
      Color(0xFF1A1814),
    ],
  );

  /// Obsidian Gold Rim — dark surface with a gold edge reflection.
  /// Use for dark-mode card backgrounds.
  static const LinearGradient obsidianGold = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: [
      Color(0xFF252018),
      Color(0xFF1A1814),
      Color(0xFF12110D),
    ],
  );

  /// Obsidian Hero — deep dark with a subtle warm gold ambient at top.
  /// Use for hero sections, app bar, and side rail backgrounds.
  static const LinearGradient obsidianHero = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF1E1B11),
      Color(0xFF131210),
      Color(0xFF0A0908),
    ],
    stops: [0.0, 0.45, 1.0],
  );

  // ── Glass Gradients ────────────────────────────────────────────────────────

  /// Dark Glass — onyx glassmorphism with a warm amber ambient.
  /// Use for modal overlays and drawer backgrounds in dark mode.
  static const LinearGradient darkGlass = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: [
      Color(0x3C2D2718),
      Color(0x1F1A1C22),
    ],
  );

  /// Light Glass — translucent pearl / champagne glass.
  /// Use for modal overlays and drawer backgrounds in light mode.
  static const LinearGradient lightGlass = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: [
      Color(0x90FFFFFF),
      Color(0x5CFDF9EE),
    ],
  );

  // ── Accent / Semantic Gradients ────────────────────────────────────────────

  /// Emerald Success — for success banners and indicators.
  static const LinearGradient emeraldSuccess = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF059669), Color(0xFF047857)],
  );

  /// Amber Warning — for warning banners.
  static const LinearGradient amberWarning = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
  );

  /// Crimson Danger — for error/danger banners.
  static const LinearGradient crimsonDanger = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
  );

  /// Sapphire Info — for info banners.
  static const LinearGradient sapphireInfo = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0EA5E9), Color(0xFF0284C7)],
  );
}
