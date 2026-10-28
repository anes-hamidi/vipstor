import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  testWidgets('staff widgets receive the reactive role theme',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, child) {
            final theme = ref.watch(lightThemeProvider);
            final role = theme.extension<RoleThemeExtension>()!;
            return MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Center(child: GoldBadge(label: role.roleLabel)),
              ),
            );
          },
        ),
      ),
    );

    // The default staff sign-in state uses the neutral customer palette, and
    // shared widgets must paint themselves from that scheme, not from a fixed
    // gold palette.
    final expectedTheme =
        AppTheme.createTheme(AppRole.customer, Brightness.light);
    final expected = expectedTheme.colorScheme.primaryContainer;
    final expectedLabel =
        expectedTheme.extension<RoleThemeExtension>()!.roleLabel;
    final badge = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(GoldBadge),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect((badge.decoration as BoxDecoration).color, expected);
    expect(find.text(expectedLabel), findsOneWidget);
  });
}
