import 'package:flutter/material.dart';

/// 4-pt based grid spacing tokens according to UX/UI Design Rules.
abstract final class AppSpacing {
  /// 2.0 dp
  static const double xxs = 2.0;

  /// 4.0 dp
  static const double xs = 4.0;

  /// 8.0 dp
  static const double sm = 8.0;

  /// 12.0 dp
  static const double md = 12.0;

  /// 16.0 dp
  static const double lg = 16.0;

  /// 24.0 dp
  static const double xl = 24.0;

  /// 32.0 dp
  static const double xxl = 32.0;

  /// 48.0 dp
  static const double xxxl = 48.0;

  /// 64.0 dp
  static const double huge = 64.0;

  // Directional EdgeInsets
  static const EdgeInsetsDirectional pXxs = EdgeInsetsDirectional.all(xxs);
  static const EdgeInsetsDirectional pXs = EdgeInsetsDirectional.all(xs);
  static const EdgeInsetsDirectional pSm = EdgeInsetsDirectional.all(sm);
  static const EdgeInsetsDirectional pMd = EdgeInsetsDirectional.all(md);
  static const EdgeInsetsDirectional pLg = EdgeInsetsDirectional.all(lg);
  static const EdgeInsetsDirectional pXl = EdgeInsetsDirectional.all(xl);
  static const EdgeInsetsDirectional pXxl = EdgeInsetsDirectional.all(xxl);

  // Horizontal Directional Padding
  static const EdgeInsetsDirectional hSm = EdgeInsetsDirectional.symmetric(horizontal: sm);
  static const EdgeInsetsDirectional hMd = EdgeInsetsDirectional.symmetric(horizontal: md);
  static const EdgeInsetsDirectional hLg = EdgeInsetsDirectional.symmetric(horizontal: lg);
  static const EdgeInsetsDirectional hXl = EdgeInsetsDirectional.symmetric(horizontal: xl);
  static const EdgeInsetsDirectional hXxl = EdgeInsetsDirectional.symmetric(horizontal: xxl);

  // Vertical Directional Padding
  static const EdgeInsetsDirectional vSm = EdgeInsetsDirectional.symmetric(vertical: sm);
  static const EdgeInsetsDirectional vMd = EdgeInsetsDirectional.symmetric(vertical: md);
  static const EdgeInsetsDirectional vLg = EdgeInsetsDirectional.symmetric(vertical: lg);
  static const EdgeInsetsDirectional vXl = EdgeInsetsDirectional.symmetric(vertical: xl);

  // Gaps
  static const SizedBox gapXxs = SizedBox(width: xxs, height: xxs);
  static const SizedBox gapXs = SizedBox(width: xs, height: xs);
  static const SizedBox gapSm = SizedBox(width: sm, height: sm);
  static const SizedBox gapMd = SizedBox(width: md, height: md);
  static const SizedBox gapLg = SizedBox(width: lg, height: lg);
  static const SizedBox gapXl = SizedBox(width: xl, height: xl);
  static const SizedBox gapXxl = SizedBox(width: xxl, height: xxl);
  static const SizedBox gapXxxl = SizedBox(width: xxxl, height: xxxl);
}
