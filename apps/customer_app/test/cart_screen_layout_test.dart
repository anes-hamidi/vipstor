import 'dart:convert';

import 'package:core/core.dart';
import 'package:customer_app/features/cart/cart_screen.dart';
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
}) {
  return ProductEntity(
    id: id,
    nameAr: name,
    nameFr: name,
    category: 'عام',
    unit: unit,
    packSize: unit == 'carton' ? 12 : 1,
    availableQty: 100,
    active: true,
    prices: [
      ProductPriceTier(
        id: '${id}_retail',
        tier: PriceTier.retail,
        minQty: 1,
        priceCentimes: price,
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cart lines stay compact and show the real unit type',
      (tester) async {
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
          'product': productToJson(_product(
            id: 'p1',
            name: 'زيت المائدة 5 لتر',
            unit: 'carton',
            price: 68000,
          )),
          'quantity': 2,
          'tier': 'retail',
        },
        {
          'product': productToJson(_product(
            id: 'p2',
            name: 'سكر أبيض',
            unit: 'kg',
            price: 10000,
          )),
          'quantity': 3,
          'tier': 'retail',
        },
        {
          'product': productToJson(_product(
            id: 'p3',
            name: 'ماء معدني',
            unit: 'L',
            price: 5000,
          )),
          'quantity': 4,
          'tier': 'retail',
        },
      ]),
    });

    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          customerIsOnlineProvider.overrideWithValue(true),
        ],
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
          home: const CartScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('كرتون'), findsWidgets);
    expect(find.textContaining('كغ'), findsWidgets);
    expect(find.textContaining('لتر'), findsWidgets);
    expect(find.textContaining('2 كرتون · 3 كغ · 4 لتر'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
