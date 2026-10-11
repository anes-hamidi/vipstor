library;

import 'package:flutter/material.dart';

class AppLocalizationHelper {
  static const List<Locale> supportedLocales = [
    Locale('ar', ''),
    Locale('fr', ''),
  ];

  static bool isRTL(BuildContext context) {
    return Directionality.of(context) == TextDirection.rtl;
  }
}
