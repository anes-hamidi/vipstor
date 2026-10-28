import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  final String message;
  const Failure(this.message);

  @override
  List<Object?> get props => [message];
}

class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Server connection error']);
}

class InsufficientStockFailure extends Failure {
  const InsufficientStockFailure([super.message = 'Insufficient stock available']);
}

class CreditLimitExceededFailure extends Failure {
  const CreditLimitExceededFailure([super.message = 'Customer credit limit exceeded']);
}

class OfflineSyncFailure extends Failure {
  const OfflineSyncFailure([super.message = 'Failed to sync offline queue']);
}

class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Authentication failed']);
}

class PinLockedFailure extends Failure {
  const PinLockedFailure([super.message = 'Account locked due to too many failed PIN attempts']);
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Network unreachable']);
}

class NotFoundFailure extends Failure {
  const NotFoundFailure([super.message = 'Resource not found']);
}

class PermissionFailure extends Failure {
  const PermissionFailure([super.message = 'Permission denied']);
}
