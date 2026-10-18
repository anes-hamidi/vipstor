import 'package:flutter_test/flutter_test.dart';
import 'package:domain/domain.dart';
import 'package:staff_app/providers/staff_providers.dart';

void main() {
  group('Delivery Driver Wallet & Settlement Domain Tests', () {
    test('DriverSettlementSummaryEntity props and equality', () {
      final now = DateTime.now();
      final summary1 = DriverSettlementSummaryEntity(
        driverId: 'driver-1',
        driverName: 'Mustapha Driver',
        driverPhone: '+213550123456',
        pendingCashCentimes: 4500000,
        unsettledOrdersCount: 5,
        lastDeliveredAt: now,
      );

      final summary2 = DriverSettlementSummaryEntity(
        driverId: 'driver-1',
        driverName: 'Mustapha Driver',
        driverPhone: '+213550123456',
        pendingCashCentimes: 4500000,
        unsettledOrdersCount: 5,
        lastDeliveredAt: now,
      );

      expect(summary1, equals(summary2));
      expect(summary1.pendingCashCentimes, 4500000);
      expect(summary1.unsettledOrdersCount, 5);
      expect(summary1.driverName, 'Mustapha Driver');
    });

    test('SettlementEntity calculation and discrepancy classification', () {
      final now = DateTime.now();
      // 1. Exact match settlement
      final exactSettlement = SettlementEntity(
        id: 'settle-001',
        driverId: 'driver-1',
        driverName: 'Mustapha Driver',
        cashierId: 'cashier-1',
        cashierName: 'Amina Cashier',
        expectedAmountCentimes: 5000000,
        countedAmountCentimes: 5000000,
        differenceCentimes: 0,
        status: 'settled',
        createdAt: now,
      );

      expect(exactSettlement.differenceCentimes, 0);
      expect(exactSettlement.status, 'settled');

      // 2. Shortage settlement
      final shortageSettlement = SettlementEntity(
        id: 'settle-002',
        driverId: 'driver-1',
        driverName: 'Mustapha Driver',
        cashierId: 'cashier-1',
        cashierName: 'Amina Cashier',
        expectedAmountCentimes: 5000000,
        countedAmountCentimes: 4800000,
        differenceCentimes: -200000,
        status: 'discrepancy_flagged',
        notes: 'Driver lost 2000 DZD voucher receipt during transit',
        createdAt: now,
      );

      expect(shortageSettlement.differenceCentimes, -200000);
      expect(shortageSettlement.status, 'discrepancy_flagged');
      expect(shortageSettlement.notes, contains('2000 DZD'));

      // 3. Overage settlement
      final overageSettlement = SettlementEntity(
        id: 'settle-003',
        driverId: 'driver-2',
        driverName: 'Yassine Driver',
        cashierId: 'cashier-1',
        cashierName: 'Amina Cashier',
        expectedAmountCentimes: 3000000,
        countedAmountCentimes: 3200000,
        differenceCentimes: 200000,
        status: 'discrepancy_flagged',
        notes: 'Customer paid extra tip/rounding cash',
        createdAt: now,
      );

      expect(overageSettlement.differenceCentimes, 200000);
      expect(overageSettlement.status, 'discrepancy_flagged');
    });
  });

  group('PosShiftSession Driver Settlement Cash Drawer Tests', () {
    test('Cashier drawer absorbs driver settlement cash accurately into expected balance', () {
      final openedAt = DateTime.now();
      final shift = PosShiftSession(
        id: 'shift-1',
        zReportNumber: 101,
        cashierId: 'cashier-1',
        cashierName: 'Fatima Cashier',
        openingFloatCentimes: 1000000, // 10,000 DZD opening float
        openedAt: openedAt,
      );

      expect(shift.expectedCashInDrawerCentimes, 1000000);

      // Register sales
      final afterSales = shift.copyWith(
        cashSalesCentimes: 2500000, // + 25,000 DZD cash sale
        creditSalesCentimes: 1500000, // on-credit sale (does not affect cash drawer)
      );
      expect(afterSales.expectedCashInDrawerCentimes, 3500000);

      // Settle a delivery driver: Driver hands over 15,000 DZD cash
      final afterDriverSettlement = afterSales.copyWith(
        driverSettlementCashCentimes: 1500000,
      );
      // Expected = 10,000 (float) + 25,000 (cash sales) + 15,000 (driver settlement) = 50,000 DZD (5,000,000 centimes)
      expect(afterDriverSettlement.expectedCashInDrawerCentimes, 5000000);

      // Pay supplier 5,000 DZD from drawer
      final afterSupplierPay = afterDriverSettlement.copyWith(
        supplierPaymentsCashCentimes: 500000,
      );
      // Expected = 50,000 - 5,000 = 45,000 DZD (4,500,000 centimes)
      expect(afterSupplierPay.expectedCashInDrawerCentimes, 4500000);

      // Now close shift with counted cash = 4,500,000 centimes
      final notifier = PosShiftNotifier();
      notifier.openShift(
        cashierId: 'cashier-1',
        cashierName: 'Fatima Cashier',
        openingFloatCentimes: 1000000,
      );
      notifier.registerSale(cashCentimes: 2500000, creditCentimes: 1500000);
      notifier.registerDriverSettlement(cashCentimes: 1500000);
      notifier.registerSupplierCashPayment(cashCentimes: 500000);

      final zSummary = notifier.closeShift(
        countedCashCentimes: 4500000,
        denominations: {2000: 20, 1000: 5},
      );

      expect(zSummary.driverSettlementCashCentimes, 1500000);
      expect(zSummary.openingFloatCentimes, 1000000);
      expect(zSummary.cashSalesCentimes, 2500000);
      expect(zSummary.supplierPaymentsCashCentimes, 500000);
      expect(zSummary.expectedCashCentimes, 4500000);
      expect(zSummary.countedCashCentimes, 4500000);
      expect(zSummary.varianceCentimes, 0);
    });
  });
}
