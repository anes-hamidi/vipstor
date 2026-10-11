import 'package:equatable/equatable.dart';
import 'product_entity.dart';

class CustomerProfileEntity extends Equatable {
  final String id;
  final String userId;
  final String name;
  final String phone;
  final int creditLimitCentimes;
  final int currentDebtCentimes;
  final PriceTier priceTier;
  final String? wilaya;
  final String? commune;
  final String? addressText;
  final double? latitude;
  final double? longitude;

  const CustomerProfileEntity({
    required this.id,
    required this.userId,
    required this.name,
    required this.phone,
    required this.creditLimitCentimes,
    required this.currentDebtCentimes,
    this.priceTier = PriceTier.wholesale,
    this.wilaya,
    this.commune,
    this.addressText,
    this.latitude,
    this.longitude,
  });

  int get remainingCreditCentimes => creditLimitCentimes - currentDebtCentimes;
  bool isCreditExceeded(int newDebtCentimes) => (currentDebtCentimes + newDebtCentimes) > creditLimitCentimes;

  CustomerProfileEntity copyWith({
    String? id,
    String? userId,
    String? name,
    String? phone,
    int? creditLimitCentimes,
    int? currentDebtCentimes,
    PriceTier? priceTier,
    String? wilaya,
    String? commune,
    String? addressText,
    double? latitude,
    double? longitude,
  }) {
    return CustomerProfileEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      creditLimitCentimes: creditLimitCentimes ?? this.creditLimitCentimes,
      currentDebtCentimes: currentDebtCentimes ?? this.currentDebtCentimes,
      priceTier: priceTier ?? this.priceTier,
      wilaya: wilaya ?? this.wilaya,
      commune: commune ?? this.commune,
      addressText: addressText ?? this.addressText,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        name,
        phone,
        creditLimitCentimes,
        currentDebtCentimes,
        priceTier,
        wilaya,
        commune,
        addressText,
        latitude,
        longitude,
      ];
}
