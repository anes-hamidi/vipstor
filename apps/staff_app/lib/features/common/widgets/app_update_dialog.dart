import 'package:flutter/material.dart';
import 'package:domain/domain.dart';
import 'package:ui_kit/ui_kit.dart';
import '../../../services/app_update_service.dart';

class AppUpdateDialog extends StatefulWidget {
  final AppVersionEntity release;
  final String currentVersion;
  final int currentBuild;
  final AppUpdateService updateService;

  const AppUpdateDialog({
    super.key,
    required this.release,
    required this.currentVersion,
    required this.currentBuild,
    required this.updateService,
  });

  /// Displays the update dialog in either blocking (mandatory) or dismissible mode
  static Future<void> show(
    BuildContext context, {
    required AppVersionEntity release,
    required String currentVersion,
    required int currentBuild,
    required AppUpdateService updateService,
  }) async {
    final isMandatory = release.isForceRequired(currentBuild);

    await showDialog<void>(
      context: context,
      barrierDismissible: !isMandatory,
      builder: (ctx) => PopScope(
        canPop: !isMandatory,
        child: AppUpdateDialog(
          release: release,
          currentVersion: currentVersion,
          currentBuild: currentBuild,
          updateService: updateService,
        ),
      ),
    );
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _errorMessage;

  bool get _isMandatory => widget.release.isForceRequired(widget.currentBuild);

  Future<void> _startUpdate() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _errorMessage = null;
    });

    try {
      await widget.updateService.downloadAndInstall(
        release: widget.release,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'فشل تنزيل التحديث: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isMandatory = _isMandatory;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: colors.obsidianSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isMandatory
                ? colors.gold.withValues(alpha: 0.8)
                : colors.goldBorder,
            width: isMandatory ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
            if (isMandatory)
              BoxShadow(
                color: colors.gold.withValues(alpha: 0.15),
                blurRadius: 40,
                spreadRadius: 2,
              ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Icon and Title
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isMandatory
                          ? colors.gold.withValues(alpha: 0.15)
                          : colors.obsidianCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isMandatory
                            ? colors.gold.withValues(alpha: 0.4)
                            : colors.goldBorder,
                      ),
                    ),
                    child: Icon(
                      isMandatory
                          ? Icons.system_security_update_warning_rounded
                          : Icons.system_update_rounded,
                      color: isMandatory ? colors.gold : colors.onObsidian,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMandatory ? 'تحديث إجباري للنظام' : 'يتوفر إصدار جديد',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: colors.onObsidian,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isMandatory
                            ? 'يجب تحديث التطبيق للمتابعة لضمان سلامة العمليات'
                            : 'يتوفر تحسينات جديدة وإصلاحات للنظام',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onObsidian.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isMandatory && !_isDownloading)
                    IconButton(
                      icon: Icon(Icons.close, color: colors.onObsidian.withValues(alpha: 0.5)),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                ],
              ),

              const SizedBox(height: 20),

              // Version Comparison Chips
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.obsidianCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.goldBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الإصدار الحالي',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onObsidian.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'v${widget.currentVersion} (${widget.currentBuild})',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.onObsidian.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: colors.gold,
                      size: 20,
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'الإصدار الجديد',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.gold.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'v${widget.release.versionName} (${widget.release.buildNumber})',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: colors.gold,
                              ),
                            ),
                            if (widget.release.formattedFileSize.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: colors.gold.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  widget.release.formattedFileSize,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: colors.gold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Release Notes Box
              if (widget.release.releaseNotes != null &&
                  widget.release.releaseNotes!.trim().isNotEmpty) ...[
                Text(
                  'أبرز ما في هذا التحديث:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.onObsidian,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 140),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.obsidianCard.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.goldBorder.withValues(alpha: 0.5)),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      widget.release.releaseNotes!.trim(),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: colors.onObsidian.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Download Progress or Error State
              if (_isDownloading) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'جاري تحميل التحديث...',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onObsidian.withValues(alpha: 0.7),
                          ),
                        ),
                        Text(
                          '${(_downloadProgress * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: colors.gold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: _downloadProgress > 0 ? _downloadProgress : null,
                        minHeight: 8,
                        backgroundColor: colors.obsidianCard,
                        valueColor: AlwaysStoppedAnimation<Color>(colors.gold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'سيتم فتح مثبت التحديث تلقائياً فور اكتمال التنزيل',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onObsidian.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ] else if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: colors.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(fontSize: 11, color: colors.error),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              const SizedBox(height: 8),

              // Action Buttons
              if (!_isDownloading) ...[
                Row(
                  children: [
                    if (!isMandatory) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.onObsidian.withValues(alpha: 0.7),
                            side: BorderSide(color: colors.goldBorder),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('لاحقاً'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _startUpdate,
                        icon: const Icon(Icons.download_rounded, size: 20),
                        label: Text(
                          _errorMessage != null ? 'إعادة المحاولة' : 'تحديث وتثبيت الآن',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.gold,
                          foregroundColor: colors.onGold,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
