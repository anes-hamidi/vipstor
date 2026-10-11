import 'package:equatable/equatable.dart';

enum WalletEntryType { collection, handover, shortage, overage, reversal }

class WalletEntry extends Equatable {
  final String id;
  final String driverId;
  final WalletEntryType type;
  final int amountCentimes;
  final String? paymentId;
  final String? settlementId;
  final String? clientId;
  final DateTime createdAt;

  const WalletEntry({
    required this.id,
    required this.driverId,
    required this.type,
    required this.amountCentimes,
    this.paymentId,
    this.settlementId,
    this.clientId,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, driverId, type, amountCentimes, paymentId, settlementId, clientId, createdAt];
}

class SettlementEntity extends Equatable {
  final String id;
  final String driverId;
  final String driverName;
  final String cashierId;
  final String cashierName;
  final int expectedAmountCentimes;
  final int countedAmountCentimes;
  final int differenceCentimes;
  final String status;
  final String? notes;
  final DateTime createdAt;

  const SettlementEntity({
    required this.id,
    required this.driverId,
    required this.driverName,
    required this.cashierId,
    required this.cashierName,
    required this.expectedAmountCentimes,
    required this.countedAmountCentimes,
    required this.differenceCentimes,
    required this.status,
    this.notes,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
        id,
        driverId,
        driverName,
        cashierId,
        cashierName,
        expectedAmountCentimes,
        countedAmountCentimes,
        differenceCentimes,
        status,
        notes,
        createdAt,
      ];
}
