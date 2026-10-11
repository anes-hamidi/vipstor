import 'package:flutter/material.dart';

/// Responsive window size classes according to Section 2.1 of UX/UI Design Rules.
enum WindowClass {
  /// 0 – 599 logical px (phones portrait)
  compact,

  /// 600 – 839 logical px (tablets portrait, foldables, phones landscape)
  medium,

  /// 840 – 1199 logical px (tablets landscape, small windows)
  expanded,

  /// 1200 – 1599 logical px (laptops, desktop windows)
  large,

  /// ≥ 1600 logical px (big monitors, TV)
  extraLarge,
}

WindowClass windowClassOf(double width) {
  if (width < 600) return WindowClass.compact;
  if (width < 840) return WindowClass.medium;
  if (width < 1200) return WindowClass.expanded;
  if (width < 1600) return WindowClass.large;
  return WindowClass.extraLarge;
}

extension ResponsiveContext on BuildContext {
  /// Returns the current WindowClass based on MediaQuery.sizeOf(this).width
  WindowClass get windowClass => windowClassOf(MediaQuery.sizeOf(this).width);

  /// True if compact window (< 600 dp)
  bool get isCompact => windowClass == WindowClass.compact;

  /// True if medium window (600 – 839 dp)
  bool get isMedium => windowClass == WindowClass.medium;

  /// True if expanded window (840 – 1199 dp)
  bool get isExpanded => windowClass == WindowClass.expanded;

  /// True if large window (1200 – 1599 dp)
  bool get isLarge => windowClass == WindowClass.large;

  /// True if extraLarge window (≥ 1600 dp)
  bool get isExtraLarge => windowClass == WindowClass.extraLarge;

  /// True if width >= 600 dp
  bool get isMediumOrLarger => MediaQuery.sizeOf(this).width >= 600;

  /// True if width >= 840 dp
  bool get isExpandedOrLarger => MediaQuery.sizeOf(this).width >= 840;

  /// True if width >= 1200 dp
  bool get isDesktopOrLarge => MediaQuery.sizeOf(this).width >= 1200;
}
