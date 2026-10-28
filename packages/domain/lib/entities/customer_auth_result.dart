/// Result of a customer self-registration.
///
/// [recoveryCode] is displayed once and never returned by the server again.
class CustomerRegistrationResult {
  const CustomerRegistrationResult({
    required this.phone,
    required this.recoveryCode,
  });

  final String phone;
  final String recoveryCode;
}

/// Result of a customer password reset.
class CustomerPasswordResetResult {
  const CustomerPasswordResetResult({
    this.recoveryCode,
    this.warning,
  });

  /// A newly rotated recovery code, or null when rotation failed.
  final String? recoveryCode;

  /// Optional server warning that should be shown to the customer.
  final String? warning;
}
