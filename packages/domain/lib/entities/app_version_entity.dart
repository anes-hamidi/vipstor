import 'package:equatable/equatable.dart';

/// Represents a published release of the application for private OTA updates.
class AppVersionEntity extends Equatable {
  final String id;
  final String appType; // 'staff_app' | 'customer_app'
  final String platform; // 'android' | 'ios' | 'windows' | 'macos' | 'linux'
  final String versionName; // e.g. '1.1.0'
  final int buildNumber; // e.g. 15
  final int minSupportedBuild; // Minimum version required to continue operating
  final String downloadUrl; // Direct link to APK, MSIX, EXE, ZIP
  final String? manifestUrl; // iOS itms-services manifest.plist link
  final String? releaseNotes; // Markdown or plain text changelog
  final bool isMandatory; // True if this release forces an immediate update
  final int? fileSizeBytes; // Size of the package in bytes
  final DateTime publishedAt;

  const AppVersionEntity({
    required this.id,
    required this.appType,
    required this.platform,
    required this.versionName,
    required this.buildNumber,
    required this.minSupportedBuild,
    required this.downloadUrl,
    this.manifestUrl,
    this.releaseNotes,
    required this.isMandatory,
    this.fileSizeBytes,
    required this.publishedAt,
  });

  /// Checks if this remote version is newer than the locally running build.
  bool hasUpdate(int currentBuildNumber) => buildNumber > currentBuildNumber;

  /// Checks if this update is strictly required (mandatory or below min supported version).
  bool isForceRequired(int currentBuildNumber) =>
      hasUpdate(currentBuildNumber) &&
      (isMandatory || currentBuildNumber < minSupportedBuild);

  /// Human-readable file size formatting (e.g. "45.2 MB")
  String get formattedFileSize {
    if (fileSizeBytes == null || fileSizeBytes! <= 0) return '';
    final mb = fileSizeBytes! / (1024 * 1024);
    if (mb < 1.0) {
      final kb = fileSizeBytes! / 1024;
      return '${kb.toStringAsFixed(1)} KB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  List<Object?> get props => [
        id,
        appType,
        platform,
        versionName,
        buildNumber,
        minSupportedBuild,
        downloadUrl,
        manifestUrl,
        releaseNotes,
        isMandatory,
        fileSizeBytes,
        publishedAt,
      ];
}
