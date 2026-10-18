import 'package:domain/domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../datasources/remote/supabase_service.dart';

class AppUpdateRepositoryImpl implements IAppUpdateRepository {
  final SupabaseClient client;
  final SupabaseService service;

  AppUpdateRepositoryImpl({required this.client, required this.service});

  @override
  Future<AppVersionEntity?> getLatestVersion({
    required String appType,
    required String platform,
  }) async {
    try {
      final rows = await client
          .from('app_versions')
          .select()
          .eq('app_type', appType)
          .eq('platform', platform)
          .order('build_number', ascending: false)
          .limit(1);

      if ((rows as List).isEmpty) {
        return null;
      }

      final data = rows.first;
      return _mapToEntity(data);
    } catch (_) {
      // Offline fallback or error handling
      return null;
    }
  }

  @override
  Future<List<AppVersionEntity>> getReleaseHistory({
    required String appType,
    required String platform,
    int limit = 10,
  }) async {
    try {
      final rows = await client
          .from('app_versions')
          .select()
          .eq('app_type', appType)
          .eq('platform', platform)
          .order('build_number', ascending: false)
          .limit(limit);

      return (rows as List)
          .map((row) => _mapToEntity(row as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<AppVersionEntity> publishRelease(AppVersionEntity release) async {
    final payload = {
      'app_type': release.appType,
      'platform': release.platform,
      'version_name': release.versionName,
      'build_number': release.buildNumber,
      'min_supported_build': release.minSupportedBuild,
      'download_url': release.downloadUrl,
      'manifest_url': release.manifestUrl,
      'release_notes': release.releaseNotes,
      'is_mandatory': release.isMandatory,
      'file_size_bytes': release.fileSizeBytes,
      'published_at': release.publishedAt.toIso8601String(),
    };

    final res = await client.from('app_versions').insert(payload).select().single();
    return _mapToEntity(res);
  }

  AppVersionEntity _mapToEntity(Map<String, dynamic> map) {
    return AppVersionEntity(
      id: map['id']?.toString() ?? '',
      appType: map['app_type']?.toString() ?? 'staff_app',
      platform: map['platform']?.toString() ?? 'android',
      versionName: map['version_name']?.toString() ?? '1.0.0',
      buildNumber: (map['build_number'] as num?)?.toInt() ?? 1,
      minSupportedBuild: (map['min_supported_build'] as num?)?.toInt() ?? 1,
      downloadUrl: map['download_url']?.toString() ?? '',
      manifestUrl: map['manifest_url']?.toString(),
      releaseNotes: map['release_notes']?.toString(),
      isMandatory: map['is_mandatory'] as bool? ?? false,
      fileSizeBytes: (map['file_size_bytes'] as num?)?.toInt(),
      publishedAt: map['published_at'] != null
          ? DateTime.tryParse(map['published_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
