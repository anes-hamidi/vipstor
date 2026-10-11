import 'package:flutter/material.dart';

/// Corner radius tokens according to UX/UI Design Rules.
abstract final class AppRadius {
  /// 2.0 dp
  static const double xs = 2.0;

  /// 4.0 dp
  static const double sm = 4.0;

  /// 8.0 dp
  static const double md = 8.0;

  /// 12.0 dp
  static const double lg = 12.0;

  /// 16.0 dp
  static const double xl = 16.0;

  /// 999.0 dp (Pill shape)
  static const double pill = 999.0;

  // BorderRadius
  static const BorderRadius xsAll = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));

  // Directional BorderRadius
  static const BorderRadiusDirectional xsDirectional = BorderRadiusDirectional.all(Radius.circular(xs));
  static const BorderRadiusDirectional smDirectional = BorderRadiusDirectional.all(Radius.circular(sm));
  static const BorderRadiusDirectional mdDirectional = BorderRadiusDirectional.all(Radius.circular(md));
  static const BorderRadiusDirectional lgDirectional = BorderRadiusDirectional.all(Radius.circular(lg));
  static const BorderRadiusDirectional xlDirectional = BorderRadiusDirectional.all(Radius.circular(xl));
  static const BorderRadiusDirectional pillDirectional = BorderRadiusDirectional.all(Radius.circular(pill));
}
