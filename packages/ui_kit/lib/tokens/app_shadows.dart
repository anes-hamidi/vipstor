import 'package:flutter/material.dart';

/// Premium shadow & glow tokens for the VIP Gold–Black design system.
abstract final class AppShadows {
  // ── Gold Glows ─────────────────────────────────────────────────────────────

  /// Subtle gold ambient glow — card hover, selected border states.
  static const BoxShadow goldGlowSm = BoxShadow(
    color: Color(0x28C59B27),
    blurRadius: 8.0,
    spreadRadius: 0.0,
    offset: Offset(0, 2),
  );

  /// Standard gold glow — active buttons, badges, highlighted rows.
  static const BoxShadow goldGlow = BoxShadow(
    color: Color(0x44D4AF37),
    blurRadius: 18.0,
    spreadRadius: 0.0,
    offset: Offset(0, 4),
  );

  /// Intense gold glow — prominent CTAs, focused inputs, floating actions.
  static const BoxShadow goldGlowLg = BoxShadow(
    color: Color(0x66D4AF37),
    blurRadius: 28.0,
    spreadRadius: 2.0,
    offset: Offset(0, 6),
  );

  /// Gold rim — hairline outer ring on gold-bordered surfaces.
  static const BoxShadow goldRim = BoxShadow(
    color: Color(0x30D4AF37),
    blurRadius: 0,
    spreadRadius: 1.0,
    offset: Offset(0, 0),
  );

  // ── Card Shadows ───────────────────────────────────────────────────────────

  /// Soft layered card shadow — light mode.
  static const List<BoxShadow> cardSoftLight = [
    BoxShadow(color: Color(0x08000000), blurRadius: 2.0,  offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0C000000), blurRadius: 8.0,  offset: Offset(0, 4)),
    BoxShadow(color: Color(0x06000000), blurRadius: 20.0, offset: Offset(0, 10)),
  ];

  /// Soft layered card shadow — dark mode with subtle gold edge reflection.
  static const List<BoxShadow> cardSoftDark = [
    BoxShadow(color: Color(0x4A000000), blurRadius: 4.0,  offset: Offset(0, 2)),
    BoxShadow(color: Color(0x30000000), blurRadius: 16.0, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x1AD4AF37), blurRadius: 24.0, offset: Offset(0, 10)),
  ];

  /// Elevated card shadow — light mode (e.g. active cart item, selected card).
  static const List<BoxShadow> cardElevatedLight = [
    BoxShadow(color: Color(0x10000000), blurRadius: 4.0,  offset: Offset(0, 2)),
    BoxShadow(color: Color(0x14000000), blurRadius: 16.0, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x16D4AF37), blurRadius: 24.0, offset: Offset(0, 12)),
  ];

  /// Elevated card shadow — dark mode.
  static const List<BoxShadow> cardElevatedDark = [
    BoxShadow(color: Color(0x60000000), blurRadius: 8.0,  offset: Offset(0, 3)),
    BoxShadow(color: Color(0x40000000), blurRadius: 24.0, offset: Offset(0, 12)),
    BoxShadow(color: Color(0x28D4AF37), blurRadius: 32.0, offset: Offset(0, 14)),
  ];

  // ── Dialog & Sheet Shadows ─────────────────────────────────────────────────

  /// Floating dialog / modal bottom sheet shadow.
  static const List<BoxShadow> dialogLuxury = [
    BoxShadow(color: Color(0x30000000), blurRadius: 40.0, spreadRadius: 2.0, offset: Offset(0, 20)),
    BoxShadow(color: Color(0x22D4AF37), blurRadius: 16.0, offset: Offset(0, 4)),
  ];

  /// Toast / snackbar shadow.
  static const List<BoxShadow> toast = [
    BoxShadow(color: Color(0x30000000), blurRadius: 16.0, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x14D4AF37), blurRadius: 8.0,  offset: Offset(0, 2)),
  ];

  // ── Button Shadows ─────────────────────────────────────────────────────────

  /// Gold button resting state shadow.
  static List<BoxShadow> goldButtonRest = [
    const BoxShadow(color: Color(0x30D4AF37), blurRadius: 8.0,  offset: Offset(0, 3)),
    const BoxShadow(color: Color(0x10000000), blurRadius: 4.0,  offset: Offset(0, 1)),
  ];

  /// Gold button hover/focus state shadow.
  static List<BoxShadow> goldButtonHover = [
    const BoxShadow(color: Color(0x50D4AF37), blurRadius: 16.0, offset: Offset(0, 5)),
    const BoxShadow(color: Color(0x18000000), blurRadius: 6.0,  offset: Offset(0, 2)),
  ];

  // ── Navigation ─────────────────────────────────────────────────────────────

  /// App bar / nav rail dark obsidian shadow.
  static const List<BoxShadow> navDark = [
    BoxShadow(color: Color(0x60000000), blurRadius: 12.0, offset: Offset(2, 0)),
    BoxShadow(color: Color(0x14D4AF37), blurRadius: 24.0, offset: Offset(1, 0)),
  ];

  /// App bar / nav rail light shadow.
  static const List<BoxShadow> navLight = [
    BoxShadow(color: Color(0x10000000), blurRadius: 8.0,  offset: Offset(0, 2)),
    BoxShadow(color: Color(0x0CC59B27), blurRadius: 16.0, offset: Offset(0, 4)),
  ];
}
