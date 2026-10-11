import 'package:flutter/material.dart';

/// Animation motion tokens according to UX/UI Design Rules.
abstract final class AppMotion {
  /// 50 ms - instant toggles
  static const Duration instant = Duration(milliseconds: 50);

  /// 150 ms - hover, press, focus, ripple
  static const Duration fast = Duration(milliseconds: 150);

  /// 250 ms - expand/collapse, fades, tabs
  static const Duration medium = Duration(milliseconds: 250);

  /// 400 ms - page & sheet transitions
  static const Duration slow = Duration(milliseconds: 400);

  // Standard curves
  static const Curve enterCurve = Curves.easeOutCubic;
  static const Curve exitCurve = Curves.easeInCubic;
  static const Curve moveCurve = Curves.easeInOutCubic;
}
