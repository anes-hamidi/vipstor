import 'package:flutter/material.dart';

/// Semantic colors theme extension according to UX/UI Design Rules Section 3.1.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.draft,
    required this.onDraft,
    required this.pending,
    required this.onPending,
    required this.posted,
    required this.onPosted,
    required this.cancelled,
    required this.onCancelled,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;

  final Color draft;
  final Color onDraft;
  final Color pending;
  final Color onPending;
  final Color posted;
  final Color onPosted;
  final Color cancelled;
  final Color onCancelled;

  static const AppColors light = AppColors(
    success: Color(0xFF059669),
    onSuccess: Colors.white,
    successContainer: Color(0xFFD1FAE5),
    onSuccessContainer: Color(0xFF065F46),
    warning: Color(0xFFD97706),
    onWarning: Colors.white,
    warningContainer: Color(0xFFFEF3C7),
    onWarningContainer: Color(0xFF92400E),
    info: Color(0xFF0284C7),
    onInfo: Colors.white,
    infoContainer: Color(0xFFE0F2FE),
    onInfoContainer: Color(0xFF075985),
    draft: Color(0xFF64748B),
    onDraft: Colors.white,
    pending: Color(0xFFD97706),
    onPending: Colors.white,
    posted: Color(0xFF059669),
    onPosted: Colors.white,
    cancelled: Color(0xFFDC2626),
    onCancelled: Colors.white,
  );

  static const AppColors dark = AppColors(
    success: Color(0xFF34D399),
    onSuccess: Color(0xFF064E3B),
    successContainer: Color(0xFF065F46),
    onSuccessContainer: Color(0xFFA7F3D0),
    warning: Color(0xFFFBBF24),
    onWarning: Color(0xFF78350F),
    warningContainer: Color(0xFF92400E),
    onWarningContainer: Color(0xFFFDE68A),
    info: Color(0xFF38BDF8),
    onInfo: Color(0xFF0C4A6E),
    infoContainer: Color(0xFF075985),
    onInfoContainer: Color(0xFFBAE6FD),
    draft: Color(0xFF94A3B8),
    onDraft: Color(0xFF0F172A),
    pending: Color(0xFFFBBF24),
    onPending: Color(0xFF78350F),
    posted: Color(0xFF34D399),
    onPosted: Color(0xFF064E3B),
    cancelled: Color(0xFFF87171),
    onCancelled: Color(0xFF7F1D1D),
  );

  @override
  AppColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? draft,
    Color? onDraft,
    Color? pending,
    Color? onPending,
    Color? posted,
    Color? onPosted,
    Color? cancelled,
    Color? onCancelled,
  }) {
    return AppColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      draft: draft ?? this.draft,
      onDraft: onDraft ?? this.onDraft,
      pending: pending ?? this.pending,
      onPending: onPending ?? this.onPending,
      posted: posted ?? this.posted,
      onPosted: onPosted ?? this.onPosted,
      cancelled: cancelled ?? this.cancelled,
      onCancelled: onCancelled ?? this.onCancelled,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer: Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer: Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
      draft: Color.lerp(draft, other.draft, t)!,
      onDraft: Color.lerp(onDraft, other.onDraft, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
      onPending: Color.lerp(onPending, other.onPending, t)!,
      posted: Color.lerp(posted, other.posted, t)!,
      onPosted: Color.lerp(onPosted, other.onPosted, t)!,
      cancelled: Color.lerp(cancelled, other.cancelled, t)!,
      onCancelled: Color.lerp(onCancelled, other.onCancelled, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>() ?? AppColors.light;
}
