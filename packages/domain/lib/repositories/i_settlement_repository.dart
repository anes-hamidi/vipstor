import '../entities/wallet_entry.dart';

abstract class ISettlementRepository {
  Future<int> getDriverExpectedWallet(String driverId);
  Future<List<WalletEntry>> getDriverWalletEntries(String driverId);
  Future<SettlementEntity> settleDriverWallet({
    required String cashierId,
    required String driverId,
    required int countedAmountCentimes,
    String? notes,
  });
}
