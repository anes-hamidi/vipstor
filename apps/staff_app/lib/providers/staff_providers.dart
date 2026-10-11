import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:core/core.dart';
import '../features/cashier/models/pos_models.dart';

export '../features/cashier/models/pos_models.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SupabaseService(client);
});

final productRepositoryProvider = Provider<IProductRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final service = ref.watch(supabaseServiceProvider);
  return ProductRepositoryImpl(client: client, service: service);
});

final orderRepositoryProvider = Provider<IOrderRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final service = ref.watch(supabaseServiceProvider);
  return OrderRepositoryImpl(client: client, service: service);
});

final purchaseRepositoryProvider = Provider<IPurchaseRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final service = ref.watch(supabaseServiceProvider);
  return PurchaseRepositoryImpl(client: client, service: service);
});

final settlementRepositoryProvider = Provider<ISettlementRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final service = ref.watch(supabaseServiceProvider);
  return SettlementRepositoryImpl(client: client, service: service);
});

final customerRepositoryProvider = Provider<ICustomerRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final service = ref.watch(supabaseServiceProvider);
  return CustomerRepositoryImpl(client: client, service: service);
});

final authRepositoryProvider = Provider<IAuthRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return AuthRepositoryImpl(client: client);
});

final liveStaffUsersProvider = FutureProvider<List<UserEntity>>((ref) async {
  final repo = ref.watch(authRepositoryProvider);
  return repo.getStaffMembers();
});

final staffMembersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('users')
      .select('id, name, phone, role, active, language, created_at')
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(rows as List);
});

// Products provider
final productsSearchQueryProvider = StateProvider<String>((ref) => '');

final liveProductsProvider = FutureProvider<List<ProductEntity>>((ref) async {
  final repo = ref.watch(productRepositoryProvider);
  final query = ref.watch(productsSearchQueryProvider);
  return repo.getProducts(search: query, onlyActive: true);
});

// Active Customer in Cart
final posActiveCustomerProvider = StateProvider<CustomerProfileEntity?>((ref) => null);

// Held Tickets (Suspended Carts)
final posHeldTicketsProvider = StateProvider<List<PosHeldTicket>>((ref) => []);

// Active Cashier Shift Session
class PosShiftNotifier extends StateNotifier<PosShiftSession?> {
  PosShiftNotifier() : super(null);

  void openShift({
    required String cashierId,
    required String cashierName,
    required int openingFloatCentimes,
  }) {
    state = PosShiftSession(
      id: const Uuid().v4(),
      zReportNumber: (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 1000000,
      cashierId: cashierId,
      cashierName: cashierName,
      openingFloatCentimes: openingFloatCentimes,
      openedAt: DateTime.now(),
      isOpen: true,
    );
  }

  void registerSale({required int cashCentimes, required int creditCentimes}) {
    if (state == null) return;
    state = state!.copyWith(
      cashSalesCentimes: state!.cashSalesCentimes + cashCentimes,
      creditSalesCentimes: state!.creditSalesCentimes + creditCentimes,
    );
  }



  void registerReturn({required int refundCentimes}) {
    if (state == null) return;
    state = state!.copyWith(
      returnsCentimes: state!.returnsCentimes + refundCentimes,
    );
  }

  void registerDebtCashPayment({required int cashCentimes}) {
    if (state == null || cashCentimes <= 0) return;
    state = state!.copyWith(
      collectedDebtCashCentimes: state!.collectedDebtCashCentimes + cashCentimes,
    );
  }

  ZReportSummary closeShift({
    required int countedCashCentimes,
    required Map<int, int> denominations,
  }) {
    final current = state!;
    final variance = countedCashCentimes - current.expectedCashInDrawerCentimes;

    final summary = ZReportSummary(
      zNumber: current.zReportNumber,
      cashierName: current.cashierName,
      openedAt: current.openedAt,
      closedAt: DateTime.now(),
      openingFloatCentimes: current.openingFloatCentimes,
      cashSalesCentimes: current.cashSalesCentimes,
      creditSalesCentimes: current.creditSalesCentimes,
      collectedDebtCashCentimes: current.collectedDebtCashCentimes,
      totalSalesCentimes: current.cashSalesCentimes + current.creditSalesCentimes,
      returnsCentimes: current.returnsCentimes,
      expectedCashCentimes: current.expectedCashInDrawerCentimes,
      countedCashCentimes: countedCashCentimes,
      varianceCentimes: variance,
      denominations: denominations,
    );

    state = null; // Shift closed
    return summary;
  }
}

final posActiveShiftProvider = StateNotifierProvider<PosShiftNotifier, PosShiftSession?>((ref) {
  return PosShiftNotifier();
});

// Customer Debt & Ledger Providers
final customerLedgerProvider = FutureProvider.family<List<CustomerLedgerEntryEntity>, String>((ref, customerId) async {
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getCustomerLedger(customerId);
});

final customerUnpaidOrdersProvider = FutureProvider.family<List<CustomerUnpaidOrderEntity>, String>((ref, customerId) async {
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getCustomerUnpaidOrders(customerId);
});

// staffListProvider
/*List<UserEntity> get _availableStaff {
    final currentAuth = ref.read(authStateProvider);
    final list = <UserEntity>[];
    final staffList = ref.read(staffListProvider);
    if (currentAuth != null) {
      list.add(currentAuth);
    }
    for (final staff in staffList) {
      if (!list.any((u) => u.id == staff.id)) {
        list.add(staff);
      }
    }
    return list;
  }
*/
final staffListProvider = FutureProvider<List<UserEntity>>((ref) async {
  final repo = ref.watch(authRepositoryProvider);
  
  return repo.getStaffMembers();
});

// ------------------------------------------------------
// Enterprise POS Cart StateNotifier
// ------------------------------------------------------
class PosCartNotifier extends StateNotifier<List<PosCartItem>> {
  final Ref ref;

  PosCartNotifier(this.ref) : super([]);

  // 1. Add / Merge Product
  void addProduct(ProductEntity product, {int qty = 1, PriceTier? tier}) {
    final activeCustomer = ref.read(posActiveCustomerProvider);
    final effectiveTier = tier ?? activeCustomer?.priceTier ?? PriceTier.wholesale;

    final idx = state.indexWhere((it) => it.productId == product.id && it.unit == PosItemUnit.piece);
    if (idx != -1) {
      final existing = state[idx];
      final newQty = existing.quantity + qty;
      updateQuantity(existing.id, newQty);
    } else {
      final newItem = PosCartItem.fromProduct(product, qty: qty, tier: effectiveTier);
      state = [...state, newItem];
    }
  }

  // 2. Add Custom / Unlisted Item
  void addCustomItem(String name, int priceCentimes, {int qty = 1, PosItemUnit unit = PosItemUnit.piece}) {
    final customItem = PosCartItem.custom(name: name, priceCentimes: priceCentimes, qty: qty, unit: unit);
    state = [...state, customItem];
  }

  // 3. Update Quantity
  Result<void, Failure> updateQuantity(String itemId, int quantity) {
    if (quantity <= 0) {
      removeProduct(itemId);
      return const Success(null);
    }

    final item = state.firstWhere((it) => it.id == itemId);
    if (!item.isCustomItem && (quantity * item.unitMultiplier) > item.availableStock) {
      return FailureResult(InsufficientStockFailure(
        'الكمية المطلوبة ($quantity) تتجاوز المخزون المتاح (${item.availableStock})',
      ));
    }

    state = state.map((it) {
      if (it.id == itemId) {
        return it.copyWith(quantity: quantity);
      }
      return it;
    }).toList();
    return const Success(null);
  }

  // 4. Update Item Unit (Piece vs Carton)
  void setItemUnit(String itemId, PosItemUnit unit) {
    state = state.map((it) {
      if (it.id == itemId) {
        return it.copyWith(unit: unit);
      }
      return it;
    }).toList();
  }

  // 5. Line Item Discount
  void setItemDiscount(String itemId, {double? percent, int? fixedCentimes}) {
    state = state.map((it) {
      if (it.id == itemId) {
        return it.copyWith(
          discountPercent: percent ?? it.discountPercent,
          manualDiscountCentimes: fixedCentimes ?? it.manualDiscountCentimes,
        );
      }
      return it;
    }).toList();
  }

  void removeProduct(String itemId) {
    state = state.where((it) => it.id != itemId).toList();
  }

  void clear() {
    state = [];
    ref.read(posActiveCustomerProvider.notifier).state = null;
  }

  int get totalCentimes => state.fold(0, (sum, item) => sum + item.lineTotalCentimes);

  // 6. Suspend Cart (Hold Ticket)
  String holdCurrentCart() {
    if (state.isEmpty) return '';
    final ticketId = const Uuid().v4();
    final customer = ref.read(posActiveCustomerProvider);
    final label = customer != null
        ? '${customer.name} (#${state.length})'
        : 'زبون مباشر (${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')})';

    final heldTicket = PosHeldTicket(
      id: ticketId,
      label: label,
      customer: customer,
      items: List.from(state),
      heldAt: DateTime.now(),
    );

    ref.read(posHeldTicketsProvider.notifier).update((list) => [...list, heldTicket]);
    clear();
    return ticketId;
  }

  // 7. Resume Held Cart
  void resumeTicket(String ticketId) {
    final heldTickets = ref.read(posHeldTicketsProvider);
    final target = heldTickets.firstWhere((t) => t.id == ticketId);

    state = target.items;
    ref.read(posActiveCustomerProvider.notifier).state = target.customer;
    ref.read(posHeldTicketsProvider.notifier).update((list) => list.where((t) => t.id != ticketId).toList());
  }

  // 8. Checkout Execution with Customer Debt Verification
  Future<Result<String, Failure>> checkout({
    required String cashierId,
    String? customerId,
    required int paidCashCentimes,
    required int onAccountCentimes,
  }) async {
    final customer = ref.read(posActiveCustomerProvider);

    // Debt Limit check
    if (onAccountCentimes > 0) {
      if (customer == null && customerId == null) {
        return const FailureResult(CreditLimitExceededFailure('لا يمكن البيع بالدين بدون حساب زبون مسجل.'));
      }
      if (customer != null && customer.isCreditExceeded(onAccountCentimes)) {
        return FailureResult(CreditLimitExceededFailure(
          'تجاوز سقف الائتمان! السقف: ${DzdFormatter.formatCentimes(customer.creditLimitCentimes)}, الدين الحالي: ${DzdFormatter.formatCentimes(customer.currentDebtCentimes)}',
        ));
      }
    }

    try {
      final orderRepo = ref.read(orderRepositoryProvider);
      final itemsPayload = state.map((it) {
        return {
          'product_id': it.productId,
          'quantity': it.totalPieces,
          'unit_price': (it.effectiveUnitPriceCentimes / it.unitMultiplier).round(),
          'unit_cost': it.unitCostCentimes,
        };
      }).toList();

      final orderId = await orderRepo.createInStoreSale(
        cashierId: cashierId,
        customerId: customer?.id ?? customerId,
        items: itemsPayload,
        paidCashCentimes: paidCashCentimes,
        onAccountCentimes: onAccountCentimes,
      );

      // Register in active shift if present
      ref.read(posActiveShiftProvider.notifier).registerSale(
            cashCentimes: paidCashCentimes,
            creditCentimes: onAccountCentimes,
          );

      clear();
      ref.invalidate(liveProductsProvider);
      return Success(orderId);
    } catch (e) {
      return FailureResult(ServerFailure('تعذر تسجيل عملية البيع: ${e.toString()}'));
    }
  }

  // 9. Process Sales Return
  Future<Result<void, Failure>> processReturn({
    required String originalOrderId,
    required String cashierId,
    required List<Map<String, dynamic>> returnItems,
    required int totalRefundCentimes,
    required String reason,
    required bool restockInventory,
  }) async {
    try {
      final supabaseService = ref.read(supabaseServiceProvider);

      if (restockInventory) {
        for (final item in returnItems) {
          await supabaseService.adjustStock(
            userId: cashierId,
            productId: item['productId'] as String,
            qtyChange: item['qty'] as int,
            reason: 'إرجاع مبيعات: $reason (وصل #$originalOrderId)',
          );
        }
      }

      // Record return against shift
      ref.read(posActiveShiftProvider.notifier).registerReturn(
            refundCentimes: totalRefundCentimes,
          );

      ref.invalidate(liveProductsProvider);
      return const Success(null);
    } catch (e) {
      return FailureResult(ServerFailure('تعذر إتمام عملية الإرجاع: ${e.toString()}'));
    }
  }
}

final posCartProvider = StateNotifierProvider<PosCartNotifier, List<PosCartItem>>((ref) {
  return PosCartNotifier(ref);
});
