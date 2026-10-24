/// Canonical sale units used across the catalogue.
///
/// The database stores a free-form `unit` string (`carton`, `boit`, `pack`,
/// `piece`, `kg`, `l`, …). This enum centralises the parsing so every screen
/// shows the same, correctly translated product type.
enum ProductUnit {
  carton('كرتون', 'Carton', 'Ctn'),
  box('علبة', 'Boîte', 'Bte'),
  pack('طرد', 'Pack', 'Pk'),
  piece('قطعة', 'Pièce', 'Pc'),
  kg('كغ', 'Kg', 'Kg'),
  gram('غ', 'g', 'g'),
  liter('لتر', 'L', 'L');

  final String arabicLabel;
  final String frenchLabel;
  final String shortCode;

  const ProductUnit(this.arabicLabel, this.frenchLabel, this.shortCode);

  /// Compact Arabic label, e.g. `كرتون`.
  String get label => arabicLabel;

  /// Bilingual label used on invoices and order details, e.g. `كرتون (Carton)`.
  String get bilingualLabel => '$arabicLabel ($frenchLabel)';

  /// `2 كرتون`
  String formatQuantity(int quantity) => '$quantity $arabicLabel';

  /// `2 كرتون (Carton)`
  String formatQuantityBilingual(int quantity) => '$quantity $bilingualLabel';

  /// Parses the raw product/order unit into a canonical [ProductUnit].
  ///
  /// Unknown or empty values fall back to [ProductUnit.piece], which matches
  /// the catalogue/database default (`piece`).
  static ProductUnit fromString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return ProductUnit.piece;

    final value = _normalize(raw);

    if (value.contains('carton') || value.contains('كرتون')) {
      return ProductUnit.carton;
    }
    if (value.contains('boit') ||
        value.contains('box') ||
        value.contains('علب') ||
        value.contains('صندوق')) {
      return ProductUnit.box;
    }
    if (value.contains('pack') ||
        value.contains('paquet') ||
        value.contains('طرد') ||
        value.contains('حزم')) {
      return ProductUnit.pack;
    }
    if (value == 'kg' ||
        value.contains('كغ') ||
        value.contains('كيلو') ||
        value.contains('kilogram')) {
      return ProductUnit.kg;
    }
    if (value == 'g' ||
        value == 'غ' ||
        value.contains('غرام') ||
        value.contains('gram')) {
      return ProductUnit.gram;
    }
    if (value == 'l' ||
        value.contains('لتر') ||
        value.contains('litre') ||
        value.contains('liter')) {
      return ProductUnit.liter;
    }
    return ProductUnit.piece;
  }

  static String _normalize(String raw) {
    var value = raw.trim().toLowerCase();
    const replacements = {
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'á': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'í': 'i',
      'ô': 'o',
      'ö': 'o',
      'ó': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ú': 'u',
      'ç': 'c',
    };
    for (final entry in replacements.entries) {
      value = value.replaceAll(entry.key, entry.value);
    }
    return value;
  }
}
