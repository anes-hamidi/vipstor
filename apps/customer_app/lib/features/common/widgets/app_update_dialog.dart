import 'package:flutter/material.dart';
import 'package:domain/domain.dart';
import 'package:ui_kit/ui_kit.dart';
import '../../../services/app_update_service.dart';

export 'package:ui_kit/ui_kit.dart' show AppUpdateScreen;

/// Customer App Update Dialog wrapper.
///
/// Delegates to the unified [AppUpdateScreen] in `ui_kit`, providing responsive
/// layouts for Mobile, Tablet, and Desktop, and enforcing mandatory/forced updates.
class AppUpdateDialog extends StatelessWidget {
  final AppVersionEntity release;
  final String currentVersion;
  final int currentBuild;
  final AppUpdateService updateService;
  final bool force;

  const AppUpdateDialog({
    super.key,
    required this.release,
    required this.currentVersion,
    required this.currentBuild,
    required this.updateService,
    this.force = false,
  });

  /// Displays the update screen in either blocking (mandatory) or dismissible mode.
  static Future<void> show(
    BuildContext context, {
    required AppVersionEntity release,
    required String currentVersion,
    required int currentBuild,
    required AppUpdateService updateService,
    bool force = false,
  }) async {
    await AppUpdateScreen.show(
      context,
      release: release,
      currentVersion: currentVersion,
      currentBuild: currentBuild,
      onDownloadAndInstall: (onProgress) => updateService.downloadAndInstall(
        release: release,
        onProgress: onProgress,
      ),
      force: force,
      appName: 'متجر الزبائن VIP',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppUpdateScreen(
      release: release,
      currentVersion: currentVersion,
      currentBuild: currentBuild,
      onDownloadAndInstall: (onProgress) => updateService.downloadAndInstall(
        release: release,
        onProgress: onProgress,
      ),
      force: force,
      appName: 'متجر الزبائن VIP',
      isFullScreen: false,
      onLater: force || release.isForceRequired(currentBuild)
          ? null
          : () => Navigator.of(context).pop(),
    );
  }
}
