/// The five operating spaces supported by the unified application core.
///
/// Each role receives a deliberately distinct Material 3 palette and semantic
/// badge treatment. The separation is an operational safety feature: staff
/// should recognise immediately when they have left their own workspace.
enum AppRole {
  /// Public retail and wholesale storefront.
  customer,

  /// Fast checkout point-of-sale terminal.
  cashier,

  /// Warehouse, stock and supplier operations.
  inventory,

  /// Field delivery and order hand-off workspace.
  delivery,

  /// Audit, fraud review and dispute resolution console.
  moderator;

  /// Whether this role belongs to the internal staff application.
  bool get isStaff => this != AppRole.customer;
}
