import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// Role-aware surface tokens shared by the whole cashier terminal.
///
/// Every token derives from the ambient [ThemeData] and the active
/// [RoleThemeExtension] instead of a fixed gold/obsidian palette, so the POS
/// repaints automatically with the signed-in workspace accent (cobalt for the
/// `cashier` profile, or whatever role opens the terminal from the master
/// portal) and both brightness modes stay balanced.
extension PosThemeTokens on BuildContext {
  /// Active Material colour scheme.
  ColorScheme get posScheme => Theme.of(this).colorScheme;

  /// Whether the active workspace uses the dark palette.
  bool get posIsDark => Theme.of(this).brightness == Brightness.dark;

  /// Accent colour of the signed-in role (cobalt for the cashier profile).
  Color get posBrand => roleTheme.roleBrandColor;

  /// Foreground paired with [posBrand] for text, icons and avatars.
  Color get posOnBrand => posScheme.onPrimary;

  /// Chrome behind the header and the compact bottom action bar.
  Color get posChrome => posScheme.surfaceContainerLow;

  /// Elevated terminal panels: the cart column, modals and search islands.
  Color get posPanel => posScheme.surfaceContainerLowest;

  /// Recessed tiles resting on [posPanel]: product cards and cart lines.
  Color get posTile => posScheme.surfaceContainerLow;

  /// Soft brand tint for pills, hints and hover fills.
  Color get posFill => posBrand.withValues(alpha: posIsDark ? 0.16 : 0.10);

  /// Accent hairline for role-branded borders.
  Color get posHairline => posBrand.withValues(alpha: posIsDark ? 0.34 : 0.26);

  /// Softer hairline used for internal dividers.
  Color get posHairlineSoft =>
      posBrand.withValues(alpha: posIsDark ? 0.18 : 0.12);
}
