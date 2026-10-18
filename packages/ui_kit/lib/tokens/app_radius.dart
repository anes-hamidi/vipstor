import 'package:flutter/material.dart';

/// Corner-radius tokens for the VIP Gold–Black design system.
abstract final class AppRadius {
  // ── Scale ──────────────────────────────────────────────────────────────────
  /// 2 dp — hairline chips, badges
  static const double xs  = 2.0;
  /// 4 dp — compact pills, small chips
  static const double sm  = 4.0;
  /// 8 dp — inputs, icon buttons
  static const double md  = 8.0;
  /// 12 dp — standard cards, action tiles
  static const double lg  = 12.0;
  /// 16 dp — elevated cards, drawers
  static const double xl  = 16.0;
  /// 20 dp — luxury product cards
  static const double xl2 = 20.0;
  /// 24 dp — bottom sheets, dialogs, hero cards
  static const double xxl = 24.0;
  /// 32 dp — extra-large modals
  static const double xxxl= 32.0;
  /// 999 dp — full pill / circle
  static const double pill = 999.0;
  /// Alias: same as [pill]
  static const double full = 999.0;

  // ── BorderRadius (symmetric) ───────────────────────────────────────────────
  static const BorderRadius xsAll   = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smAll   = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll   = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll   = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll   = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius xl2All  = BorderRadius.all(Radius.circular(xl2));
  static const BorderRadius xxlAll  = BorderRadius.all(Radius.circular(xxl));
  static const BorderRadius xxxlAll = BorderRadius.all(Radius.circular(xxxl));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
  static const BorderRadius fullAll = BorderRadius.all(Radius.circular(full));

  // ── BorderRadiusDirectional ────────────────────────────────────────────────
  static const BorderRadiusDirectional xsDirectional   = BorderRadiusDirectional.all(Radius.circular(xs));
  static const BorderRadiusDirectional smDirectional   = BorderRadiusDirectional.all(Radius.circular(sm));
  static const BorderRadiusDirectional mdDirectional   = BorderRadiusDirectional.all(Radius.circular(md));
  static const BorderRadiusDirectional lgDirectional   = BorderRadiusDirectional.all(Radius.circular(lg));
  static const BorderRadiusDirectional xlDirectional   = BorderRadiusDirectional.all(Radius.circular(xl));
  static const BorderRadiusDirectional xxlDirectional  = BorderRadiusDirectional.all(Radius.circular(xxl));
  static const BorderRadiusDirectional pillDirectional = BorderRadiusDirectional.all(Radius.circular(pill));
  static const BorderRadiusDirectional fullDirectional = BorderRadiusDirectional.all(Radius.circular(full));

  // ── Asymmetric helpers ─────────────────────────────────────────────────────
  /// Top corners only — for bottom sheets and stacked cards.
  static BorderRadius topOnly(double r) =>
      BorderRadius.only(topLeft: Radius.circular(r), topRight: Radius.circular(r));

  /// Bottom corners only.
  static BorderRadius bottomOnly(double r) =>
      BorderRadius.only(bottomLeft: Radius.circular(r), bottomRight: Radius.circular(r));
}
