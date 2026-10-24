import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:domain/domain.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  final testRelease = AppVersionEntity(
    id: 'test-release-1',
    appType: 'customer_app',
    platform: 'android',
    versionName: '2.5.0',
    buildNumber: 25,
    minSupportedBuild: 10,
    downloadUrl: 'https://example.com/app.apk',
    releaseNotes: '• ميزة الدفع السريع\n• تحسين أداء البحث\n• إصلاحات عامة',
    isMandatory: false,
    fileSizeBytes: 45 * 1024 * 1024,
    publishedAt: DateTime(2026, 10, 24),
  );

  final testMandatoryRelease = AppVersionEntity(
    id: 'test-release-mandatory',
    appType: 'staff_app',
    platform: 'windows',
    versionName: '3.0.0',
    buildNumber: 30,
    minSupportedBuild: 30,
    downloadUrl: 'https://example.com/staff_setup.exe',
    releaseNotes: '• تحديث أمني إلزامي لقاعدة البيانات\n• بروتوكول جديد',
    isMandatory: true,
    fileSizeBytes: 62 * 1024 * 1024,
    publishedAt: DateTime(2026, 10, 24),
  );

  Widget createTestWidget({
    required AppVersionEntity release,
    required Size screenSize,
    bool force = false,
    VoidCallback? onLater,
    Future<void> Function(void Function(double))? onInstall,
  }) {
    return MaterialApp(
      theme: AppTheme.createTheme(AppRole.customer, Brightness.dark),
      home: MediaQuery(
        data: MediaQueryData(size: screenSize),
        child: AppUpdateScreen(
          release: release,
          currentVersion: '1.0.0',
          currentBuild: 10,
          onDownloadAndInstall: onInstall ?? (onProgress) async {},
          force: force,
          appName: 'منظومة الجملة VIP',
          onLater: onLater,
        ),
      ),
    );
  }

  group('AppUpdateScreen Responsive Tests', () {
    testWidgets('renders mobile layout (<600px)', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        createTestWidget(
          release: testRelease,
          screenSize: const Size(400, 800),
          onLater: () {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('يتوفر تحديث جديد'), findsOneWidget);
      expect(find.text('تحديث وتثبيت الآن'), findsOneWidget);
      expect(find.text('لاحقاً'), findsOneWidget);
      expect(find.text('v2.5.0 (25)'), findsOneWidget);
    });

    testWidgets('renders tablet layout (600px - 1023px)', (tester) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        createTestWidget(
          release: testRelease,
          screenSize: const Size(768, 1024),
          onLater: () {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('يتوفر تحديث جديد'), findsOneWidget);
      expect(find.text('تحديث وتثبيت الآن'), findsOneWidget);
      expect(find.text('لاحقاً'), findsOneWidget);
      expect(find.text('v2.5.0 (25)'), findsOneWidget);
    });

    testWidgets('renders desktop layout (>=1024px)', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        createTestWidget(
          release: testRelease,
          screenSize: const Size(1280, 800),
          onLater: () {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('يتوفر تحديث جديد'), findsOneWidget);
      expect(find.text('أبرز ما في هذا التحديث:'), findsOneWidget);
      expect(find.text('تحديث وتثبيت الآن'), findsOneWidget);
      expect(find.text('لاحقاً'), findsOneWidget);
    });
  });

  group('AppUpdateScreen Mandatory / Force Mode Tests', () {
    testWidgets('forced update hides "Later" button and shows mandatory badge', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        createTestWidget(
          release: testMandatoryRelease,
          screenSize: const Size(1280, 800),
          force: true,
          onLater: () {},
        ),
      );
      await tester.pumpAndSettle();

      // "لاحقاً" should NOT be displayed when mandatory
      expect(find.text('لاحقاً'), findsNothing);
      expect(find.text('تحديث إجباري للنظام'), findsOneWidget);
      expect(find.text('تحديث أمني إلزامي لمتابعة العمل'), findsOneWidget);
      expect(find.text('تحديث وتثبيت الآن'), findsOneWidget);
    });

    testWidgets('downloading state displays progress indicator', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool installCalled = false;
      await tester.pumpWidget(
        createTestWidget(
          release: testRelease,
          screenSize: const Size(400, 800),
          onInstall: (onProgress) async {
            installCalled = true;
            onProgress(0.5);
            await Future<void>.delayed(const Duration(milliseconds: 100));
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('تحديث وتثبيت الآن'));
      await tester.pump();

      expect(installCalled, isTrue);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
    });
  });
}
