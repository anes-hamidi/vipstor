import 'dart:convert';

import 'package:customer_app/models/customer_models.dart';
import 'package:customer_app/providers/customer_providers.dart';
import 'package:domain/domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProductEntity _product() => const ProductEntity(
      id: 'product-1',
      nameAr: 'زيت',
      nameFr: 'Huile',
      category: 'زيوت',
      unit: 'carton',
      packSize: 4,
      availableQty: 50,
      active: true,
      prices: [
        ProductPriceTier(
          id: 'retail-1',
          tier: PriceTier.retail,
          minQty: 1,
          priceCentimes: 10000,
        ),
        ProductPriceTier(
          id: 'wholesale-10',
          tier: PriceTier.wholesale,
          minQty: 10,
          priceCentimes: 8500,
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('restored cart is repriced with the current customer tier', () async {
    SharedPreferences.setMockInitialValues({
      'customer_profile_v1': jsonEncode({
        'id': 'customer-1',
        'name': 'محمد',
        'phone': '0550000000',
        'priceTier': 'wholesale',
        'wilaya': 'الجزائر',
        'commune': 'باب الوادي',
        'addressText': 'شارع 1',
      }),
      'customer.cart.v2': jsonEncode([
        {
          'product': productToJson(_product()),
          'quantity': 2,
          'tier': 'retail',
        },
      ]),
    });

    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    final cart = container.read(customerCartProvider);

    expect(cart, hasLength(1));
    expect(cart.single.tier, PriceTier.wholesale);
    expect(cart.single.unitPrice, 10000);
  });

  test('wholesale quantity threshold reprices the cart line', () async {
    SharedPreferences.setMockInitialValues({
      'customer_profile_v1': jsonEncode({
        'id': 'customer-1',
        'name': 'محمد',
        'phone': '0550000000',
        'priceTier': 'wholesale',
        'wilaya': 'الجزائر',
        'commune': 'باب الوادي',
        'addressText': 'شارع 1',
      }),
      'customer.cart.v2': jsonEncode([
        {
          'product': productToJson(_product()),
          'quantity': 10,
          'tier': 'retail',
        },
      ]),
    });

    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    final cart = container.read(customerCartProvider);

    expect(cart.single.tier, PriceTier.wholesale);
    expect(cart.single.unitPrice, 8500);
    expect(cart.single.lineTotal, 85000);
  });
}
