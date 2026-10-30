import 'dart:convert';

import 'package:core/core.dart';
import 'package:customer_app/features/catalog/catalog_screen.dart';
import 'package:customer_app/features/catalog/widgets/quantity_stepper.dart';
import 'package:customer_app/features/catalog/widgets/quick_reorder_strip.dart';
import 'package:customer_app/features/catalog/widgets/sticky_cart_bar.dart';
import 'package:customer_app/models/customer_models.dart';
import 'package:customer_app/providers/customer_providers.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProductEntity _product({
  required String id,
  required String name,
  required String unit,
  required int price,
  required int available,
  int packSize = 1,
  String category = 'مواد غذائية',
}) {
  return ProductEntity(
    id: id,
    nameAr: name,
    nameFr: name,
    category: category,
    unit: unit,
    packSize: packSize,
    availableQty: available,
    active: true,
    prices: [
      ProductPriceTier(
        id: '${id}_retail',
        tier: PriceTier.retail,
        minQty: 1,
        priceCentimes: price,
      ),
      ProductPriceTier(
        id: '${id}_wholesale',
        tier: PriceTier.wholesale,
        minQty: 1,
        priceCentimes: price - 2000,
      ),
    ],
  );
}

final _products = [
  _product(
    id: 'p1',
    name: 'زيت المائدة 5 لتر',
    unit: 'carton',
    packSize: 12,
    price: 68000,
    available: 3,
  ),
  _product(
    id: 'p2',
    name: 'ماء معدني',
    unit: 'L',
    price: 5000,
    available: 0,
  ),
  _product(
    id: 'p3',
    name: 'سكر أبيض',
    unit: 'kg',
    price: 10000,
    available: 40,
  ),
];

class _FakeCatalogNotifier extends CustomerCatalogNotifier {
  @override
  Future<CatalogSnapshot> build() async {
    return CatalogSnapshot(
      products: _products,
      syncedAt: DateTime(2026, 10, 30, 14, 20),
    );
  }

  @override
  Future<void> refresh({bool silent = false}) async {}
}

class _FakeOrdersNotifier extends CustomerOrdersNotifier {
  @override
  Future<OrdersSnapshot> build() async => const OrdersSnapshot(orders: []);
}

Future<void> _pumpStorefront(
  WidgetTester tester, {
  required Brightness brightness,
  required Size size,
}) async {
  SharedPreferences.setMockInitialValues({
    'customer_profile_v1': jsonEncode({
      'id': 'customer-1',
      'name': 'محمد',
      'phone': '0550000000',
      'priceTier': 'retail',
      'wilaya': 'الجزائر',
      'commune': 'باب الوادي',
      'addressText': 'شارع 1',
    }),
    'customer.cart.v2': jsonEncode([
      {
        'product': productToJson(_products.first),
        'quantity': 2,
        'tier': 'retail',
      },
    ]),
  });
  final prefs = await SharedPreferences.getInstance();

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        customerIsOnlineProvider.overrideWithValue(true),
        customerCatalogProvider.overrideWith(_FakeCatalogNotifier.new),
        customerOrdersProvider.overrideWith(_FakeOrdersNotifier.new),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.createTheme(AppRole.customer, brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child ?? const SizedBox.shrink(),
        ),
        home: const CatalogScreen(),
      ),
    ),
  );

  // Let the fake async notifiers resolve without waiting on skeleton shimmer.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('storefront fits a 320dp phone with large Arabic text',
      (tester) async {
    await _pumpStorefront(
      tester,
      brightness: Brightness.light,
      size: const Size(320, 720),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(CatalogStickyCartBar), findsOneWidget);
    expect(find.byType(CatalogQuantityStepper), findsNothing);
    expect(find.byKey(const ValueKey('catalog-qty-p1')), findsOneWidget);
    expect(find.text('آخر 3'), findsOneWidget);
    expect(find.text('نفذ من المخزون'), findsOneWidget);
  });

  testWidgets('storefront renders in dark mode without layout errors',
      (tester) async {
    await _pumpStorefront(
      tester,
      brightness: Brightness.dark,
      size: const Size(390, 844),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('زيت المائدة 5 لتر'), findsWidgets);
    expect(find.byType(CatalogStickyCartBar), findsOneWidget);
  });

  testWidgets('product and filter sheets stay usable on a small phone',
      (tester) async {
    await _pumpStorefront(
      tester,
      brightness: Brightness.light,
      size: const Size(320, 720),
    );

    await tester.longPress(find.text('زيت المائدة 5 لتر').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('سعر التجزئة'), findsOneWidget);
    expect(find.text('تم'), findsOneWidget);

    await tester.tap(find.text('تم'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    expect(find.text('ترتيب وتصفية'), findsOneWidget);
    expect(find.text('تطبيق'), findsOneWidget);
  });

  testWidgets('tapping a product card adds it to the cart', (tester) async {
    await _pumpStorefront(
      tester,
      brightness: Brightness.light,
      size: const Size(390, 844),
    );

    expect(find.byKey(const ValueKey('catalog-qty-p3')), findsNothing);

    await tester.scrollUntilVisible(
      find.text('سكر أبيض'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('سكر أبيض'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('أضف للطلبية'), findsNothing);
    expect(find.byKey(const ValueKey('catalog-qty-p3')), findsOneWidget);
  });

  testWidgets('long-pressing a card opens the details sheet', (tester) async {
    await _pumpStorefront(
      tester,
      brightness: Brightness.light,
      size: const Size(320, 720),
    );

    await tester.scrollUntilVisible(
      find.text('سكر أبيض'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.longPress(find.text('سكر أبيض'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('أضف للطلبية'), findsOneWidget);

    await tester.tap(find.text('أضف للطلبية'));
    await tester.pumpAndSettle();

    expect(find.text('أضف للطلبية'), findsNothing);
  });

  testWidgets('quick reorder tiles fit a small phone with large text',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.createTheme(AppRole.customer, Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child ?? const SizedBox.shrink(),
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: QuickReorderStrip(products: _products.take(2).toList()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('أعد طلبك المعتاد'), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsNWidgets(2));
  });
}
