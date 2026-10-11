import 'package:equatable/equatable.dart';

class CustomerLedgerEntryEntity extends Equatable {
  final String id;
  final String customerId;
  final int amountChangeCentimes; // Positive = debt added, Negative = payment/reduction
  final String refType; // 'order_credit', 'payment', 'return_refund', 'manual_adjustment'
  final String refId;
  final String? notes;
  final DateTime createdAt;

  const CustomerLedgerEntryEntity({
    required this.id,
    required this.customerId,
    required this.amountChangeCentimes,
    required this.refType,
    required this.refId,
    this.notes,
    required this.createdAt,
  });

  bool get isDebtIncrease => amountChangeCentimes > 0;
  bool get isDebtPayment => amountChangeCentimes < 0;

  @override
  List<Object?> get props => [
        id,
        customerId,
        amountChangeCentimes,
        refType,
        refId,
        notes,
        createdAt,
      ];
}

class CustomerUnpaidOrderEntity extends Equatable {
  final String orderId;
  final DateTime orderDate;
  final int totalAmountCentimes;
  final int paidAmountCentimes;
  final int remainingDebtCentimes;
  final List<String> itemsSummary;

  const CustomerUnpaidOrderEntity({
    required this.orderId,
    required this.orderDate,
    required this.totalAmountCentimes,
    required this.paidAmountCentimes,
    required this.remainingDebtCentimes,
    this.itemsSummary = const [],
  });

  @override
  List<Object?> get props => [
        orderId,
        orderDate,
        totalAmountCentimes,
        paidAmountCentimes,
        remainingDebtCentimes,
        itemsSummary,
      ];
}

class CustomerDebtPaymentResult extends Equatable {
  final String paymentId;
  final String customerId;
  final int paidAmountCentimes;
  final int previousBalanceCentimes;
  final int remainingBalanceCentimes;
  final String paymentMethod;
  final DateTime timestamp;
  final String? notes;

  const CustomerDebtPaymentResult({
    required this.paymentId,
    required this.customerId,
    required this.paidAmountCentimes,
    required this.previousBalanceCentimes,
    required this.remainingBalanceCentimes,
    required this.paymentMethod,
    required this.timestamp,
    this.notes,
  });

  @override
  List<Object?> get props => [
        paymentId,
        customerId,
        paidAmountCentimes,
        previousBalanceCentimes,
        remainingBalanceCentimes,
        paymentMethod,
        timestamp,
        notes,
      ];
}
