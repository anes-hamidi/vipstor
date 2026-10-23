import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_role.dart';
import 'app_theme.dart';

/// The workspace currently driving the application shell.
///
/// Application roots update this provider when authentication resolves or when
/// an operator switches workspace. Every dependent theme recomputes itself
/// immediately, so no screen has to rebuild its own palette manually.
final StateProvider<AppRole> appRoleProvider =
    StateProvider<AppRole>((ref) => AppRole.customer);

/// User-selected light/dark preference. Defaults to the operating system.
final StateProvider<ThemeMode> themeModeProvider =
    StateProvider<ThemeMode>((ref) => ThemeMode.system);

/// Reactive light theme for the active workspace.
final Provider<ThemeData> lightThemeProvider = Provider<ThemeData>((ref) {
  final AppRole role = ref.watch(appRoleProvider);
  return AppTheme.createTheme(role, Brightness.light);
});

/// Reactive dark theme for the active workspace.
final Provider<ThemeData> darkThemeProvider = Provider<ThemeData>((ref) {
  final AppRole role = ref.watch(appRoleProvider);
  return AppTheme.createTheme(role, Brightness.dark);
});
