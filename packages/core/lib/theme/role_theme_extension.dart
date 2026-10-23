import 'package:flutter/material.dart';

import 'app_role.dart';

/// Type-safe semantic tokens that are specific to a workspace role.
///
/// Material 3 already carries the full colour system through [ColorScheme].
/// This extension adds only the pieces that standard Material roles cannot
/// express: the active operating profile, its brand accent, and the badge
/// treatment used by persistent workspace indicators.
@immutable
class RoleThemeExtension extends ThemeExtension<RoleThemeExtension> {
  const RoleThemeExtension({
    required this.role,
    required this.roleBrandColor,
    required this.badgeBackground,
    required this.badgeText,
    required this.roleLabel,
  });

  /// The workspace currently in control of the application shell.
  final AppRole role;

  /// Primary accent reserved for role-level navigation and hero actions.
  final Color roleBrandColor;

  /// Background of the persistent workspace badge.
  final Color badgeBackground;

  /// Foreground of the persistent workspace badge.
  final Color badgeText;

  /// Human-readable workspace name used by badges and operational headers.
  final String roleLabel;

  @override
  RoleThemeExtension copyWith({
    AppRole? role,
    Color? roleBrandColor,
    Color? badgeBackground,
    Color? badgeText,
    String? roleLabel,
  }) {
    return RoleThemeExtension(
      role: role ?? this.role,
      roleBrandColor: roleBrandColor ?? this.roleBrandColor,
      badgeBackground: badgeBackground ?? this.badgeBackground,
      badgeText: badgeText ?? this.badgeText,
      roleLabel: roleLabel ?? this.roleLabel,
    );
  }

  @override
  RoleThemeExtension lerp(ThemeExtension<RoleThemeExtension>? other, double t) {
    if (other is! RoleThemeExtension) {
      return this;
    }
    return RoleThemeExtension(
      role: t < 0.5 ? role : other.role,
      roleBrandColor: Color.lerp(roleBrandColor, other.roleBrandColor, t)!,
      badgeBackground: Color.lerp(badgeBackground, other.badgeBackground, t)!,
      badgeText: Color.lerp(badgeText, other.badgeText, t)!,
      roleLabel: t < 0.5 ? roleLabel : other.roleLabel,
    );
  }
}

/// Convenient, null-safe access to the active role tokens.
extension RoleThemeContext on BuildContext {
  /// Returns the active [RoleThemeExtension].
  ///
  /// Widgets can also be rendered in isolated tests without the full app
  /// theme; in that case a role-neutral fallback is derived from the ambient
  /// Material colour scheme rather than from a hard-coded palette.
  RoleThemeExtension get roleTheme {
    final theme = Theme.of(this);
    return theme.extension<RoleThemeExtension>() ??
        RoleThemeExtension(
          role: AppRole.customer,
          roleBrandColor: theme.colorScheme.primary,
          badgeBackground: theme.colorScheme.primaryContainer,
          badgeText: theme.colorScheme.onPrimaryContainer,
          roleLabel: 'Customer Storefront',
        );
  }
}
