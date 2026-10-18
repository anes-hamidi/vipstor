import '../entities/wallet_entry.dart';
import '../entities/order_entity.dart';

abstract class ISettlementRepository {
  Future<int> getDriverExpectedWallet(String driverId);
  Future<List<WalletEntry>> getDriverWalletEntries(String driverId);
  Future<List<DriverSettlementSummaryEntity>> getPendingDriverSettlements();
  Future<List<SettlementEntity>> getRecentSettlements({String? driverId, int limit = 30});
  Future<List<OrderEntity>> getDriverUnsettledOrders(String driverId);
  Future<SettlementEntity> settleDriverWallet({
    required String cashierId,
    required String driverId,
    required int countedAmountCentimes,
    String? notes,
  });
}
