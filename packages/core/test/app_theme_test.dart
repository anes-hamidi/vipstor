import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTheme.createTheme', () {
    test('applies Material 3 and the role extension for every role', () {
      for (final role in AppRole.values) {
        for (final brightness in Brightness.values) {
          final theme = AppTheme.createTheme(role, brightness);
          expect(theme.useMaterial3, isTrue);
          expect(theme.brightness, brightness);

          final extension = theme.extension<RoleThemeExtension>();
          expect(extension, isNotNull);
          expect(extension!.role, role);
          expect(extension.roleBrandColor, theme.colorScheme.primary);
          expect(extension.badgeBackground, theme.colorScheme.primaryContainer);
          expect(extension.roleLabel, isNotEmpty);
        }
      }
    });

    test('gives each role a distinct brand color', () {
      final primaries = AppRole.values
          .map((role) => AppTheme.createTheme(role, Brightness.light))
          .map((theme) => theme.colorScheme.primary)
          .toSet();
      expect(primaries.length, AppRole.values.length);
    });

    test('keeps flat app bars and compact staff density', () {
      final staff = AppTheme.createTheme(AppRole.cashier, Brightness.light);
      expect(staff.appBarTheme.elevation, 0);
      expect(staff.cardTheme.elevation, 0);
      expect(staff.visualDensity, VisualDensity.compact);

      final customer = AppTheme.createTheme(AppRole.customer, Brightness.light);
      expect(customer.visualDensity, VisualDensity.standard);
    });

    test('preserves the customer compatibility getters', () {
      expect(
        AppTheme.lightTheme.colorScheme.primary,
        AppTheme.createTheme(AppRole.customer, Brightness.light)
            .colorScheme
            .primary,
      );
      expect(
        AppTheme.darkTheme.colorScheme.primary,
        AppTheme.createTheme(AppRole.customer, Brightness.dark)
            .colorScheme
            .primary,
      );
    });
  });

  group('RoleThemeExtension', () {
    test('copyWith overrides only the provided fields', () {
      final original = AppTheme.createTheme(AppRole.delivery, Brightness.light)
          .extension<RoleThemeExtension>()!;
      final copy = original.copyWith(roleLabel: 'Route Dispatch');

      expect(copy.roleLabel, 'Route Dispatch');
      expect(copy.role, original.role);
      expect(copy.roleBrandColor, original.roleBrandColor);
      expect(copy.badgeBackground, original.badgeBackground);
    });

    test('lerp blends colors and snaps discrete fields', () {
      final light = AppTheme.createTheme(AppRole.inventory, Brightness.light)
          .extension<RoleThemeExtension>()!;
      final dark = AppTheme.createTheme(AppRole.inventory, Brightness.dark)
          .extension<RoleThemeExtension>()!;

      final midpoint = light.lerp(dark, 0.5);
      expect(midpoint.role, AppRole.inventory);
      expect(midpoint.roleBrandColor,
          Color.lerp(light.roleBrandColor, dark.roleBrandColor, 0.5));

      expect(light.lerp(dark, 0.25).roleLabel, light.roleLabel);
      expect(light.lerp(dark, 0.75).roleLabel, dark.roleLabel);
    });
  });

  group('appTheme providers', () {
    test('light and dark themes follow the active role', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container
            .read(lightThemeProvider)
            .extension<RoleThemeExtension>()!
            .role,
        AppRole.customer,
      );

      container.read(appRoleProvider.notifier).state = AppRole.moderator;

      expect(
        container
            .read(lightThemeProvider)
            .extension<RoleThemeExtension>()!
            .role,
        AppRole.moderator,
      );
      expect(
        container.read(darkThemeProvider).extension<RoleThemeExtension>()!.role,
        AppRole.moderator,
      );
      expect(
        container.read(lightThemeProvider).colorScheme.primary,
        AppTheme.createTheme(AppRole.moderator, Brightness.light)
            .colorScheme
            .primary,
      );
    });
  });
}
