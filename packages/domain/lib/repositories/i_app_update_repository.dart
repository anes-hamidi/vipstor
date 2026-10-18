import '../entities/app_version_entity.dart';

abstract class IAppUpdateRepository {
  /// Fetches the latest published release for a specific app and target OS platform.
  Future<AppVersionEntity?> getLatestVersion({
    required String appType,
    required String platform,
  });

  /// Fetches release history for inspection or changelog display.
  Future<List<AppVersionEntity>> getReleaseHistory({
    required String appType,
    required String platform,
    int limit = 10,
  });

  /// Publishes a new release manifest to Supabase (used by admin/moderator).
  Future<AppVersionEntity> publishRelease(AppVersionEntity release);
}
