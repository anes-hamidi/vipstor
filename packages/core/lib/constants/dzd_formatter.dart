import 'package:intl/intl.dart';

class DzdFormatter {
  static final NumberFormat _formatterWithDecimals = NumberFormat('#,##0.00', 'fr_DZ');
  static final NumberFormat _formatterWhole = NumberFormat('#,##0', 'fr_DZ');

  /// Converts centimes (BIGINT in DB) to formatted DZD string.
  /// Example: 125050 centimes -> "1 250,50 DZD"
  static String formatCentimes(int centimes, {bool showDecimals = true}) {
    final dinars = centimes / 100.0;
    final formatted = showDecimals
        ? _formatterWithDecimals.format(dinars)
        : _formatterWhole.format(dinars.round());
    return '$formatted DZD';
  }

  /// Parses human-entered dinar string (e.g. "1250.50") into integer centimes (125050)
  static int parseDinarsToCentimes(String text) {
    final sanitized = text.replaceAll(',', '.').replaceAll(' ', '').trim();
    if (sanitized.isEmpty) return 0;
    final value = double.tryParse(sanitized) ?? 0.0;
    return (value * 100).round();
  }
}
