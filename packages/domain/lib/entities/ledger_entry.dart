import 'package:equatable/equatable.dart';

enum LedgerType { stock, customer, supplier }

class StockLedgerEntry extends Equatable {
  final String id;
  final String productId;
  final String productName;
  final int qtyChange;
  final String reason;
  final String refType;
  final String refId;
  final String userName;
  final DateTime createdAt;

  const StockLedgerEntry({
    required this.id,
    required this.productId,
    required this.productName,
    required this.qtyChange,
    required this.reason,
    required this.refType,
    required this.refId,
    required this.userName,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, productId, productName, qtyChange, reason, refType, refId, userName, createdAt];
}

class CustomerLedgerEntry extends Equatable {
  final String id;
  final String customerId;
  final int amountChangeCentimes; // Positive (+ debt), Negative (- payment)
  final String refType;
  final String refId;
  final String? notes;
  final DateTime createdAt;

  const CustomerLedgerEntry({
    required this.id,
    required this.customerId,
    required this.amountChangeCentimes,
    required this.refType,
    required this.refId,
    this.notes,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, customerId, amountChangeCentimes, refType, refId, notes, createdAt];
}
