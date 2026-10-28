import 'package:equatable/equatable.dart';

enum UserRole {
  moderator,
  manager,
  cashier,
  driver,
  customer;

  static UserRole fromString(String val) {
    return UserRole.values.firstWhere(
      (e) => e.name == val,
      orElse: () => UserRole.customer,
    );
  }
}

class UserEntity extends Equatable {
  final String id;
  final String phone;
  final String name;
  final UserRole role;
  final bool active;
  final String language;
  final String? pinCode;

  /// When true the temporary/reset PIN must be replaced before the staff
  /// workspace can be used. The router blocks navigation; PIN-checked RPCs
  /// still require the current (temporary) PIN until it is replaced.
  final bool mustChangePin;

  const UserEntity({
    required this.id,
    required this.phone,
    required this.name,
    required this.role,
    required this.active,
    required this.language,
    this.pinCode,
    this.mustChangePin = false,
  });

  UserEntity copyWith({
    String? id,
    String? phone,
    String? name,
    UserRole? role,
    bool? active,
    String? language,
    String? pinCode,
    bool? mustChangePin,
  }) {
    return UserEntity(
      id: id ?? this.id,
      phone: phone ?? this.phone,
      name: name ?? this.name,
      role: role ?? this.role,
      active: active ?? this.active,
      language: language ?? this.language,
      pinCode: pinCode ?? this.pinCode,
      mustChangePin: mustChangePin ?? this.mustChangePin,
    );
  }

  @override
  List<Object?> get props =>
      [id, phone, name, role, active, language, pinCode, mustChangePin];
}
