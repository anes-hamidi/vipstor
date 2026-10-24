import 'package:flutter/material.dart';
import 'package:domain/domain.dart';
import '../tokens/app_colors.dart';

/// A shared, responsive screen for OTA application updates.
///
/// Adapts its layout seamlessly for **Mobile**, **Tablet**, and **Desktop** screens.
/// Supports both mandatory/force updates (blocking navigation and interaction)
/// and optional updates (providing a dismissible "Later" option).
class AppUpdateScreen extends StatefulWidget {
  final AppVersionEntity release;
  final String currentVersion;
  final int currentBuild;
  final Future<void> Function(void Function(double progress) onProgress) onDownloadAndInstall;
  final bool force;
  final String? appName;
  final VoidCallback? onLater;
  final bool isFullScreen;

  const AppUpdateScreen({
    super.key,
    required this.release,
    required this.currentVersion,
    required this.currentBuild,
    required this.onDownloadAndInstall,
    this.force = false,
    this.appName,
    this.onLater,
    this.isFullScreen = true,
  });

  /// Displays the update screen as a full-screen route or modal dialog.
  /// When [force] or [release.isForceRequired] is true, the view strictly
  /// enforces update and blocks hardware/gesture pop.
  static Future<void> show(
    BuildContext context, {
    required AppVersionEntity release,
    required String currentVersion,
    required int currentBuild,
    required Future<void> Function(void Function(double progress) onProgress) onDownloadAndInstall,
    bool force = false,
    String? appName,
    bool asDialog = false,
  }) async {
    final isMandatory = force || release.isForceRequired(currentBuild);

    if (asDialog && !isMandatory) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: AppUpdateScreen(
              release: release,
              currentVersion: currentVersion,
              currentBuild: currentBuild,
              onDownloadAndInstall: onDownloadAndInstall,
              force: force,
              appName: appName,
              isFullScreen: false,
              onLater: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
      );
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (ctx) => PopScope(
            canPop: !isMandatory,
            child: AppUpdateScreen(
              release: release,
              currentVersion: currentVersion,
              currentBuild: currentBuild,
              onDownloadAndInstall: onDownloadAndInstall,
              force: force,
              appName: appName,
              isFullScreen: true,
              onLater: isMandatory ? null : () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
      );
    }
  }

  @override
  State<AppUpdateScreen> createState() => _AppUpdateScreenState();
}

class _AppUpdateScreenState extends State<AppUpdateScreen> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _errorMessage;
  bool _installCompleted = false;

  bool get _isMandatory => widget.force || widget.release.isForceRequired(widget.currentBuild);

  Future<void> _startUpdate() async {
    if (_isDownloading) return;
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _errorMessage = null;
      _installCompleted = false;
    });

    try {
      await widget.onDownloadAndInstall((progress) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress;
          });
        }
      });
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _downloadProgress = 1.0;
        _installCompleted = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'فشل تنزيل التحديث: ${e.toString()}';
        });
      }
    }
  }

  String _platformName(String platform) {
    switch (platform.toLowerCase()) {
      case 'android':
        return 'Android (حزمة APK)';
      case 'windows':
        return 'Windows (تطبيق سطح المكتب)';
      case 'ios':
        return 'iOS (حزمة Apple)';
      case 'macos':
        return 'macOS';
      case 'linux':
        return 'Linux';
      case 'web':
        return 'تطبيق الويب (Web)';
      default:
        return platform;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isMandatory = _isMandatory;
    final width = MediaQuery.sizeOf(context).width;

    final Widget content;
    if (width >= 1024) {
      content = _buildDesktopLayout(context, colors, isMandatory);
    } else if (width >= 600) {
      content = _buildTabletLayout(context, colors, isMandatory);
    } else {
      content = _buildMobileLayout(context, colors, isMandatory);
    }

    if (!widget.isFullScreen) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: content,
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: colors.obsidian,
        body: Stack(
          children: [
            // Ambient luxury background glow
            Positioned(
              top: -120,
              right: -80,
              child: Container(
                width: 380,
                height: 380,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (isMandatory ? colors.warning : colors.gold).withValues(alpha: 0.08),
                ),
              ),
            ),
            Positioned(
              bottom: -150,
              left: -100,
              child: Container(
                width: 440,
                height: 440,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.gold.withValues(alpha: 0.05),
                ),
              ),
            ),
            SafeArea(child: Center(child: content)),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // DESKTOP LAYOUT (>= 1024px)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildDesktopLayout(BuildContext context, AppColors colors, bool isMandatory) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 680),
      margin: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: colors.obsidianSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isMandatory ? colors.gold.withValues(alpha: 0.75) : colors.goldBorder,
          width: isMandatory ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.65),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
          if (isMandatory)
            BoxShadow(
              color: colors.gold.withValues(alpha: 0.18),
              blurRadius: 50,
              spreadRadius: 2,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Column 1: Identity, Badges, and Version Specs
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildEmblem(colors, isMandatory, size: 54),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.appName ?? 'منظومة الجملة VIP',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colors.onGold.withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isMandatory ? 'تحديث إجباري للنظام' : 'يتوفر تحديث جديد',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: colors.onGold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildUrgencyChip(colors, isMandatory),
                    const SizedBox(height: 20),
                    Text(
                      isMandatory
                          ? 'يتطلب هذا الإصدار تحديثاً فورياً لتأمين الاتصال، مزامنة قاعدة البيانات، وضمان سلامة واستمرارية العمليات.'
                          : 'يتوفر تحديث جديد يتضمن تحسينات على الأداء، استقرار الاتصال، وإضافات مميزة للمنظومة.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: colors.onGold.withValues(alpha: 0.75),
                      ),
                    ),
                    const Spacer(),
                    _buildVersionComparison(colors),
                    const SizedBox(height: 16),
                    _buildMetadataRow(colors),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: colors.obsidianCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colors.goldBorder.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.verified_user_rounded, color: colors.gold, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'نسخة رسمية وموثوقة من مستودع المنظومة المعتمد',
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.onGold.withValues(alpha: 0.65),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 32),
              VerticalDivider(color: colors.goldBorder.withValues(alpha: 0.4), width: 1),
              const SizedBox(width: 32),

              // Column 2: What's New, Progress, and Action Controls
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'أبرز ما في هذا التحديث:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colors.onGold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _buildReleaseNotes(colors),
                    ),
                    const SizedBox(height: 20),

                    if (_isDownloading)
                      _buildDownloadProgress(colors)
                    else if (_errorMessage != null)
                      _buildErrorBanner(colors)
                    else if (_installCompleted)
                      _buildInstallCompletedBanner(colors),

                    const SizedBox(height: 20),
                    _buildActionButtons(colors, isMandatory),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TABLET LAYOUT (600px - 1023px)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildTabletLayout(BuildContext context, AppColors colors, bool isMandatory) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 720),
      margin: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      decoration: BoxDecoration(
        color: colors.obsidianSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isMandatory ? colors.gold.withValues(alpha: 0.75) : colors.goldBorder,
          width: isMandatory ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 36,
            offset: const Offset(0, 14),
          ),
          if (isMandatory)
            BoxShadow(
              color: colors.gold.withValues(alpha: 0.15),
              blurRadius: 40,
              spreadRadius: 2,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  _buildEmblem(colors, isMandatory, size: 48),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMandatory ? 'تحديث إجباري للنظام' : 'يتوفر تحديث جديد',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: colors.onGold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.appName ?? 'منظومة الجملة VIP',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onGold.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isMandatory && !_isDownloading && widget.onLater != null)
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: colors.onGold.withValues(alpha: 0.5)),
                      onPressed: widget.onLater,
                      tooltip: 'إغلاق',
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _buildUrgencyChip(colors, isMandatory),
              const SizedBox(height: 18),
              _buildVersionComparison(colors),
              const SizedBox(height: 14),
              _buildMetadataRow(colors),
              const SizedBox(height: 20),

              // Release notes
              Text(
                'أبرز ما في هذا التحديث:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: colors.onGold,
                ),
              ),
              const SizedBox(height: 10),
              _buildReleaseNotes(colors, maxHeight: 180),
              const SizedBox(height: 20),

              if (_isDownloading)
                _buildDownloadProgress(colors)
              else if (_errorMessage != null)
                _buildErrorBanner(colors)
              else if (_installCompleted)
                _buildInstallCompletedBanner(colors),

              const SizedBox(height: 20),
              _buildActionButtons(colors, isMandatory),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // MOBILE LAYOUT (< 600px)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildMobileLayout(BuildContext context, AppColors colors, bool isMandatory) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      margin: widget.isFullScreen ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: colors.obsidianSurface,
        borderRadius: BorderRadius.circular(widget.isFullScreen ? 0 : 20),
        border: widget.isFullScreen
            ? null
            : Border.all(
                color: isMandatory ? colors.gold.withValues(alpha: 0.75) : colors.goldBorder,
                width: isMandatory ? 1.5 : 1.0,
              ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top App Bar / Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  _buildEmblem(colors, isMandatory, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMandatory ? 'تحديث إجباري للنظام' : 'يتوفر تحديث جديد',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colors.onGold,
                          ),
                        ),
                        Text(
                          widget.appName ?? 'منظومة الجملة VIP',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onGold.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isMandatory && !_isDownloading && widget.onLater != null)
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: colors.onGold.withValues(alpha: 0.6)),
                      onPressed: widget.onLater,
                      tooltip: 'إغلاق',
                    ),
                ],
              ),
            ),
            Divider(color: colors.goldBorder.withValues(alpha: 0.3), height: 1),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildUrgencyChip(colors, isMandatory),
                    const SizedBox(height: 16),
                    _buildVersionComparison(colors),
                    const SizedBox(height: 12),
                    _buildMetadataRow(colors),
                    const SizedBox(height: 18),

                    Text(
                      'أبرز ما في هذا التحديث:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: colors.onGold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildReleaseNotes(colors, maxHeight: 220),
                    const SizedBox(height: 20),

                    if (_isDownloading)
                      _buildDownloadProgress(colors)
                    else if (_errorMessage != null)
                      _buildErrorBanner(colors)
                    else if (_installCompleted)
                      _buildInstallCompletedBanner(colors),
                  ],
                ),
              ),
            ),

            // Sticky Bottom Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.obsidianCard,
                border: Border(
                  top: BorderSide(color: colors.goldBorder.withValues(alpha: 0.4)),
                ),
              ),
              child: _buildActionButtons(colors, isMandatory, isVertical: !isMandatory),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // REUSABLE COMPONENTS
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildEmblem(AppColors colors, bool isMandatory, {double size = 48}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isMandatory ? colors.gold.withValues(alpha: 0.16) : colors.obsidianCard,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(
          color: isMandatory ? colors.gold.withValues(alpha: 0.6) : colors.goldBorder,
          width: 1.5,
        ),
        boxShadow: isMandatory
            ? [
                BoxShadow(
                  color: colors.gold.withValues(alpha: 0.25),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Center(
        child: Icon(
          isMandatory ? Icons.system_security_update_warning_rounded : Icons.system_update_rounded,
          color: isMandatory ? colors.gold : colors.onObsidian,
          size: size * 0.52,
        ),
      ),
    );
  }

  Widget _buildUrgencyChip(AppColors colors, bool isMandatory) {
    final bg = isMandatory ? colors.gold.withValues(alpha: 0.12) : colors.obsidianCard;
    final border = isMandatory ? colors.gold.withValues(alpha: 0.45) : colors.goldBorder;
    final text = isMandatory ? 'تحديث أمني إلزامي لمتابعة العمل' : 'تحديث اختياري مستحسن للجميع';
    final icon = isMandatory ? Icons.gpp_maybe_rounded : Icons.auto_awesome_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.gold),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.gold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionComparison(AppColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colors.obsidianCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.goldBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الإصدار الحالي المثبت',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onGold.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'v${widget.currentVersion} (${widget.currentBuild})',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.onGold.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colors.gold.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_forward_rounded,
                color: colors.gold,
                size: 18,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'الإصدار الجديد المتاح',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.gold.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'v${widget.release.versionName} (${widget.release.buildNumber})',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colors.gold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataRow(AppColors colors) {
    final platformName = _platformName(widget.release.platform);
    final size = widget.release.formattedFileSize;

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        if (size.isNotEmpty)
          _buildPill(colors, icon: Icons.download_done_rounded, label: 'الحجم: $size'),
        _buildPill(colors, icon: Icons.devices_rounded, label: 'المنصة: $platformName'),
        if (widget.release.isMandatory)
          _buildPill(colors, icon: Icons.lock_outline_rounded, label: 'إلزامي للتشغيل', isGold: true),
      ],
    );
  }

  Widget _buildPill(AppColors colors, {required IconData icon, required String label, bool isGold = false}) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isGold ? colors.gold.withValues(alpha: 0.15) : colors.obsidianCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isGold ? colors.gold.withValues(alpha: 0.4) : colors.goldBorder.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: isGold ? colors.gold : colors.onGold.withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isGold ? FontWeight.bold : FontWeight.normal,
                color: isGold ? colors.gold : colors.onGold.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReleaseNotes(AppColors colors, {double? maxHeight}) {
    final notes = widget.release.releaseNotes?.trim();
    final hasNotes = notes != null && notes.isNotEmpty;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight ?? double.infinity),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.obsidianCard.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.goldBorder.withValues(alpha: 0.5)),
      ),
      child: SingleChildScrollView(
        child: Text(
          hasNotes
              ? notes
              : '• تحسينات عامة في استقرار التطبيق والأداء.\n• تحديث بروتوكولات المزامنة اللحظية.\n• إصلاحات أمنية وتوافق كامل مع أحدث إصدارات النظام.',
          style: TextStyle(
            fontSize: 12.5,
            height: 1.7,
            color: colors.onGold.withValues(alpha: 0.88),
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadProgress(AppColors colors) {
    final pct = (_downloadProgress * 100).toInt();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.obsidianCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.gold.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(colors.gold),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'جاري تحميل التحديث...',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: colors.onGold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$pct%',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: colors.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _downloadProgress > 0 ? _downloadProgress : null,
              minHeight: 8,
              backgroundColor: colors.obsidianSurface,
              valueColor: AlwaysStoppedAnimation<Color>(colors.gold),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'سيتم فتح مثبت التحديث تلقائياً فور اكتمال التنزيل',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: colors.onGold.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(AppColors colors) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: colors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage ?? 'حدث خطأ أثناء تحميل التحديث.',
              style: TextStyle(fontSize: 12, color: colors.error, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstallCompletedBanner(AppColors colors) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.success.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline_rounded, color: colors.success, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'اكتمل التنزيل بنجاح! تم فتح مثبت التحديث في نظامك.',
              style: TextStyle(fontSize: 12, color: colors.success, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    AppColors colors,
    bool isMandatory, {
    bool isVertical = false,
  }) {
    if (_isDownloading) {
      return const SizedBox.shrink();
    }

    final laterButton = (!isMandatory && widget.onLater != null)
        ? OutlinedButton(
            onPressed: widget.onLater,
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.onGold.withValues(alpha: 0.75),
              side: BorderSide(color: colors.goldBorder),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('لاحقاً', style: TextStyle(fontWeight: FontWeight.w600)),
          )
        : null;

    final primaryButton = ElevatedButton.icon(
      onPressed: _startUpdate,
      icon: Icon(
        _errorMessage != null ? Icons.refresh_rounded : Icons.download_rounded,
        size: 20,
      ),
      label: Text(
        _errorMessage != null ? 'إعادة المحاولة' : 'تحديث وتثبيت الآن',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.gold,
        foregroundColor: colors.onGold,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );

    if (isVertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primaryButton,
          if (laterButton != null) ...[
            const SizedBox(height: 10),
            laterButton,
          ],
        ],
      );
    }

    return Row(
      children: [
        if (laterButton != null) ...[
          Expanded(child: laterButton),
          const SizedBox(width: 12),
        ],
        Expanded(
          flex: laterButton != null ? 2 : 1,
          child: primaryButton,
        ),
      ],
    );
  }
}
