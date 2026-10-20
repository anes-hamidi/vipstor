import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:domain/domain.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateCheckResult {
  final String currentVersion;
  final int currentBuild;
  final AppVersionEntity? newRelease;

  AppUpdateCheckResult({
    required this.currentVersion,
    required this.currentBuild,
    this.newRelease,
  });

  bool get hasUpdate => newRelease != null && newRelease!.hasUpdate(currentBuild);
  bool get isForceUpdate => newRelease != null && newRelease!.isForceRequired(currentBuild);
}

class AppUpdateService {
  final IAppUpdateRepository _repository;
  final String appType;

  AppUpdateService({
    required IAppUpdateRepository repository,
    this.appType = 'customer_app',
  }) : _repository = repository;

  /// Detects the target platform identifier
  String get currentPlatform {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  /// Checks if a newer release is published for the current platform
  Future<AppUpdateCheckResult> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 1;

      final latest = await _repository.getLatestVersion(
        appType: appType,
        platform: currentPlatform,
      );

      if (latest != null && latest.hasUpdate(currentBuild)) {
        return AppUpdateCheckResult(
          currentVersion: currentVersion,
          currentBuild: currentBuild,
          newRelease: latest,
        );
      }

      return AppUpdateCheckResult(
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        newRelease: null,
      );
    } catch (e) {
      debugPrint('[AppUpdateService] Error checking for updates: $e');
      return AppUpdateCheckResult(
        currentVersion: '1.0.0',
        currentBuild: 1,
        newRelease: null,
      );
    }
  }

  /// Downloads and executes installation of the new release
  Future<void> downloadAndInstall({
    required AppVersionEntity release,
    required void Function(double progress) onProgress,
  }) async {
    final platform = currentPlatform;

    if (platform == 'android') {
      await _installAndroid(release, onProgress);
    } else if (platform == 'ios') {
      await _installIOS(release);
    } else if (platform == 'windows') {
      await _installWindows(release, onProgress);
    } else {
      // Web / fallback: open download URL in default browser
      final uri = Uri.parse(release.downloadUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  /// Handles Android APK download with streaming progress & native package install intent
  Future<void> _installAndroid(
    AppVersionEntity release,
    void Function(double) onProgress,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final apkFile = File('${tempDir.path}/update_${release.versionName}_${release.buildNumber}.apk');

    if (await apkFile.exists()) {
      await apkFile.delete();
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(release.downloadUrl));
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        throw Exception('Download failed with HTTP status ${response.statusCode}');
      }

      final totalBytes = response.contentLength > 0
          ? response.contentLength
          : (release.fileSizeBytes ?? -1);

      int receivedBytes = 0;
      final sink = apkFile.openWrite();

      await for (final chunk in response) {
        receivedBytes += chunk.length;
        sink.add(chunk);

        if (totalBytes > 0) {
          onProgress((receivedBytes / totalBytes).clamp(0.0, 1.0));
        }
      }

      await sink.flush();
      await sink.close();

      onProgress(1.0);

      // Trigger OS PackageInstaller via OpenFilex
      final result = await OpenFilex.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );

      debugPrint('[AppUpdateService] OpenFilex result: ${result.type} - ${result.message}');
    } finally {
      client.close();
    }
  }

  /// Handles iOS in-house OTA installation using the itms-services:// protocol
  Future<void> _installIOS(AppVersionEntity release) async {
    final manifestUrl = release.manifestUrl ?? release.downloadUrl;
    final itmsUri = Uri.parse('itms-services://?action=download-manifest&url=$manifestUrl');

    if (await canLaunchUrl(itmsUri)) {
      await launchUrl(itmsUri, mode: LaunchMode.externalApplication);
    } else {
      final fallbackUri = Uri.parse(release.downloadUrl);
      await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
    }
  }

  /// Handles Windows installation
  Future<void> _installWindows(
    AppVersionEntity release,
    void Function(double) onProgress,
  ) async {
    final url = release.downloadUrl.toLowerCase();

    if (url.endsWith('.appinstaller') || url.endsWith('.msix')) {
      final uri = Uri.parse(release.downloadUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    if (url.endsWith('.exe')) {
      final tempDir = await getTemporaryDirectory();
      final exeFile = File('${tempDir.path}/update_${release.versionName}_installer.exe');

      if (await exeFile.exists()) {
        await exeFile.delete();
      }

      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(release.downloadUrl));
        final response = await request.close();

        if (response.statusCode != HttpStatus.ok) {
          throw Exception('Download failed with HTTP status ${response.statusCode}');
        }

        final totalBytes = response.contentLength > 0
            ? response.contentLength
            : (release.fileSizeBytes ?? -1);

        int receivedBytes = 0;
        final sink = exeFile.openWrite();

        await for (final chunk in response) {
          receivedBytes += chunk.length;
          sink.add(chunk);
          if (totalBytes > 0) {
            onProgress((receivedBytes / totalBytes).clamp(0.0, 1.0));
          }
        }

        await sink.flush();
        await sink.close();
        onProgress(1.0);

        await Process.start(exeFile.path, ['/SILENT'], runInShell: true);
        exit(0);
      } finally {
        client.close();
      }
    } else {
      final uri = Uri.parse(release.downloadUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
