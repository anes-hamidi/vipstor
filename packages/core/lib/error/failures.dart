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
