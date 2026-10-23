import 'package:core/core.dart';
import 'package:flutter/material.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_spacing.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppLoadingView
// ─────────────────────────────────────────────────────────────────────────────

/// Full-screen loading view with a sweeping gold shimmer ring.
class AppLoadingView extends StatefulWidget {
  final String? message;
  const AppLoadingView({super.key, this.message});

  @override
  State<AppLoadingView> createState() => _AppLoadingViewState();
}

class _AppLoadingViewState extends State<AppLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = context.roleTheme.roleBrandColor;
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Stack(
              alignment: Alignment.center,
              children: [
                // Sweeping role-coloured ring
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      transform: GradientRotation(_ctrl.value * 6.28318),
                      colors: [
                        brand,
                        Color.lerp(brand, Colors.white, 0.45)!,
                        brand,
                        Color.lerp(brand, Colors.black, 0.20)!,
                        brand.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.25, 0.50, 0.75, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: brand.withValues(alpha: isDark ? 0.40 : 0.28),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                // Inner surface circle
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.surfaceContainerLowest,
                    boxShadow: [
                      BoxShadow(
                        color: brand.withValues(alpha: 0.18),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.diamond_outlined,
                    color: brand,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
          if (widget.message != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              widget.message!,
              style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppSkeletonLoader
// ─────────────────────────────────────────────────────────────────────────────

/// In-layout shimmer skeleton for list/grid content placeholders.
class AppSkeletonLoader extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const AppSkeletonLoader({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius,
  });

  @override
  State<AppSkeletonLoader> createState() => _AppSkeletonLoaderState();
}

class _AppSkeletonLoaderState extends State<AppSkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius ?? AppRadius.smAll,
          gradient: LinearGradient(
            colors: isDark
                ? [
                    const Color(0xFF2A2518),
                    const Color(0xFF3A3220),
                    const Color(0xFF2A2518),
                  ]
                : [
                    const Color(0xFFEDE3B8),
                    const Color(0xFFFFFBEE),
                    const Color(0xFFEDE3B8),
                  ],
            stops: const [0.0, 0.5, 1.0],
            begin: Alignment(-1 + _ctrl.value * 2, 0),
            end: Alignment(1 + _ctrl.value * 2, 0),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppEmptyView
// ─────────────────────────────────────────────────────────────────────────────

/// Elegant zero-state with gold icon ring and optional CTA.
class AppEmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppEmptyView({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = context.roleTheme.roleBrandColor;
    final isDark = theme.brightness == Brightness.dark;
    final iconBg = brand.withValues(alpha: isDark ? 0.16 : 0.10);
    final iconColor = brand;

    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: iconBg,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: brand.withValues(alpha: 0.30),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: brand.withValues(alpha: 0.16),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Icon(icon, size: 38, color: iconColor),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  height: 2.5,
                  width: 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        brand.withValues(alpha: 0.0),
                        brand,
                        brand.withValues(alpha: 0.0),
                      ],
                    ),
                    borderRadius: AppRadius.fullAll,
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.add),
                    label: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppErrorView
// ─────────────────────────────────────────────────────────────────────────────

/// Standard error state with icon, friendly message, and Retry CTA.
class AppErrorView extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  const AppErrorView({
    super.key,
    this.title = 'حدث خطأ أثناء تحميل البيانات',
    required this.message,
    this.onRetry,
    this.retryLabel = 'إعادة المحاولة',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.error.withValues(alpha: 0.30),
                    width: 1.5,
                  ),
                ),
                child: Icon(Icons.error_outline_rounded,
                    size: 34, color: theme.colorScheme.error),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.error),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: AppSpacing.xl),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(retryLabel),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppOfflineView
// ─────────────────────────────────────────────────────────────────────────────

/// Connectivity-lost state view.
class AppOfflineView extends StatelessWidget {
  final VoidCallback? onRetry;
  const AppOfflineView({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = context.roleTheme.roleBrandColor;

    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.80),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: brand.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.wifi_off_rounded,
                  size: 38,
                  color: brand,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'لا يوجد اتصال بالإنترنت',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'تحقق من اتصالك وأعد المحاولة',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: AppSpacing.xl),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة الاتصال'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppNoPermissionView
// ─────────────────────────────────────────────────────────────────────────────

/// Role-access-denied state.
class AppNoPermissionView extends StatelessWidget {
  final String? message;
  const AppNoPermissionView({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.40),
                    width: 1.5,
                  ),
                ),
                child: Icon(Icons.lock_outline_rounded,
                    size: 36, color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'غير مصرح لك بالوصول',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message ?? 'ليس لديك صلاحية لعرض هذه الصفحة',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppStates — convenience factory namespace
// ─────────────────────────────────────────────────────────────────────────────

/// Convenience factory for all standard app states.
///
/// ```dart
/// switch (asyncValue) {
///   AsyncLoading() => AppStates.loading(),
///   AsyncError(:final error) => AppStates.error(error.toString(), onRetry: _reload),
///   AsyncData(:final value) when value.isEmpty =>
///       AppStates.empty(title: 'لا توجد منتجات', description: 'أضف منتجاً للبدء'),
///   AsyncData(:final value) => _buildContent(value),
/// }
/// ```
abstract class AppStates {
  static Widget loading({String? message}) => AppLoadingView(message: message);

  static Widget empty({
    IconData icon = Icons.inbox_outlined,
    required String title,
    required String description,
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      AppEmptyView(
        icon: icon,
        title: title,
        description: description,
        actionLabel: actionLabel,
        onAction: onAction,
      );

  static Widget error(
    String message, {
    String title = 'حدث خطأ أثناء تحميل البيانات',
    VoidCallback? onRetry,
    String retryLabel = 'إعادة المحاولة',
  }) =>
      AppErrorView(
          title: title, message: message, onRetry: onRetry, retryLabel: retryLabel);

  static Widget offline({VoidCallback? onRetry}) =>
      AppOfflineView(onRetry: onRetry);

  static Widget noPermission({String? message}) =>
      AppNoPermissionView(message: message);

  /// Inline shimmer skeleton bar — use inside list/grid placeholders.
  static Widget skeleton({
    double width = double.infinity,
    double height = 16,
    BorderRadius? borderRadius,
  }) =>
      AppSkeletonLoader(
          width: width, height: height, borderRadius: borderRadius);
}
