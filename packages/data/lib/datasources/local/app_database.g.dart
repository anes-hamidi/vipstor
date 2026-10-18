// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CachedProductsTable extends CachedProducts
    with TableInfo<$CachedProductsTable, CachedProduct> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameArMeta = const VerificationMeta('nameAr');
  @override
  late final GeneratedColumn<String> nameAr = GeneratedColumn<String>(
      'name_ar', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameFrMeta = const VerificationMeta('nameFr');
  @override
  late final GeneratedColumn<String> nameFr = GeneratedColumn<String>(
      'name_fr', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
      'unit', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _packSizeMeta =
      const VerificationMeta('packSize');
  @override
  late final GeneratedColumn<int> packSize = GeneratedColumn<int>(
      'pack_size', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _lastUnitCostCentimesMeta =
      const VerificationMeta('lastUnitCostCentimes');
  @override
  late final GeneratedColumn<int> lastUnitCostCentimes = GeneratedColumn<int>(
      'last_unit_cost_centimes', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _onHandQtyMeta =
      const VerificationMeta('onHandQty');
  @override
  late final GeneratedColumn<int> onHandQty = GeneratedColumn<int>(
      'on_hand_qty', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _availableQtyMeta =
      const VerificationMeta('availableQty');
  @override
  late final GeneratedColumn<int> availableQty = GeneratedColumn<int>(
      'available_qty', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
      'active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("active" IN (0, 1))'));
  static const VerificationMeta _photoUrlMeta =
      const VerificationMeta('photoUrl');
  @override
  late final GeneratedColumn<String> photoUrl = GeneratedColumn<String>(
      'photo_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _pricesJsonMeta =
      const VerificationMeta('pricesJson');
  @override
  late final GeneratedColumn<String> pricesJson = GeneratedColumn<String>(
      'prices_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _barcodesJsonMeta =
      const VerificationMeta('barcodesJson');
  @override
  late final GeneratedColumn<String> barcodesJson = GeneratedColumn<String>(
      'barcodes_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _syncedAtMeta =
      const VerificationMeta('syncedAt');
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
      'synced_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        nameAr,
        nameFr,
        category,
        unit,
        packSize,
        lastUnitCostCentimes,
        onHandQty,
        availableQty,
        active,
        photoUrl,
        pricesJson,
        barcodesJson,
        syncedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_products';
  @override
  VerificationContext validateIntegrity(Insertable<CachedProduct> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name_ar')) {
      context.handle(_nameArMeta,
          nameAr.isAcceptableOrUnknown(data['name_ar']!, _nameArMeta));
    } else if (isInserting) {
      context.missing(_nameArMeta);
    }
    if (data.containsKey('name_fr')) {
      context.handle(_nameFrMeta,
          nameFr.isAcceptableOrUnknown(data['name_fr']!, _nameFrMeta));
    } else if (isInserting) {
      context.missing(_nameFrMeta);
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('unit')) {
      context.handle(
          _unitMeta, unit.isAcceptableOrUnknown(data['unit']!, _unitMeta));
    } else if (isInserting) {
      context.missing(_unitMeta);
    }
    if (data.containsKey('pack_size')) {
      context.handle(_packSizeMeta,
          packSize.isAcceptableOrUnknown(data['pack_size']!, _packSizeMeta));
    } else if (isInserting) {
      context.missing(_packSizeMeta);
    }
    if (data.containsKey('last_unit_cost_centimes')) {
      context.handle(
          _lastUnitCostCentimesMeta,
          lastUnitCostCentimes.isAcceptableOrUnknown(
              data['last_unit_cost_centimes']!, _lastUnitCostCentimesMeta));
    } else if (isInserting) {
      context.missing(_lastUnitCostCentimesMeta);
    }
    if (data.containsKey('on_hand_qty')) {
      context.handle(
          _onHandQtyMeta,
          onHandQty.isAcceptableOrUnknown(
              data['on_hand_qty']!, _onHandQtyMeta));
    } else if (isInserting) {
      context.missing(_onHandQtyMeta);
    }
    if (data.containsKey('available_qty')) {
      context.handle(
          _availableQtyMeta,
          availableQty.isAcceptableOrUnknown(
              data['available_qty']!, _availableQtyMeta));
    } else if (isInserting) {
      context.missing(_availableQtyMeta);
    }
    if (data.containsKey('active')) {
      context.handle(_activeMeta,
          active.isAcceptableOrUnknown(data['active']!, _activeMeta));
    } else if (isInserting) {
      context.missing(_activeMeta);
    }
    if (data.containsKey('photo_url')) {
      context.handle(_photoUrlMeta,
          photoUrl.isAcceptableOrUnknown(data['photo_url']!, _photoUrlMeta));
    }
    if (data.containsKey('prices_json')) {
      context.handle(
          _pricesJsonMeta,
          pricesJson.isAcceptableOrUnknown(
              data['prices_json']!, _pricesJsonMeta));
    } else if (isInserting) {
      context.missing(_pricesJsonMeta);
    }
    if (data.containsKey('barcodes_json')) {
      context.handle(
          _barcodesJsonMeta,
          barcodesJson.isAcceptableOrUnknown(
              data['barcodes_json']!, _barcodesJsonMeta));
    } else if (isInserting) {
      context.missing(_barcodesJsonMeta);
    }
    if (data.containsKey('synced_at')) {
      context.handle(_syncedAtMeta,
          syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta));
    } else if (isInserting) {
      context.missing(_syncedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedProduct map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedProduct(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      nameAr: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name_ar'])!,
      nameFr: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name_fr'])!,
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category'])!,
      unit: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}unit'])!,
      packSize: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}pack_size'])!,
      lastUnitCostCentimes: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}last_unit_cost_centimes'])!,
      onHandQty: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}on_hand_qty'])!,
      availableQty: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}available_qty'])!,
      active: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}active'])!,
      photoUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}photo_url']),
      pricesJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}prices_json'])!,
      barcodesJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}barcodes_json'])!,
      syncedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}synced_at'])!,
    );
  }

  @override
  $CachedProductsTable createAlias(String alias) {
    return $CachedProductsTable(attachedDatabase, alias);
  }
}

class CachedProduct extends DataClass implements Insertable<CachedProduct> {
  final String id;
  final String nameAr;
  final String nameFr;
  final String category;
  final String unit;
  final int packSize;
  final int lastUnitCostCentimes;
  final int onHandQty;
  final int availableQty;
  final bool active;
  final String? photoUrl;

  /// JSON-encoded List<{id,tier,min_qty,price}>
  final String pricesJson;

  /// JSON-encoded List<String>
  final String barcodesJson;
  final DateTime syncedAt;
  const CachedProduct(
      {required this.id,
      required this.nameAr,
      required this.nameFr,
      required this.category,
      required this.unit,
      required this.packSize,
      required this.lastUnitCostCentimes,
      required this.onHandQty,
      required this.availableQty,
      required this.active,
      this.photoUrl,
      required this.pricesJson,
      required this.barcodesJson,
      required this.syncedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name_ar'] = Variable<String>(nameAr);
    map['name_fr'] = Variable<String>(nameFr);
    map['category'] = Variable<String>(category);
    map['unit'] = Variable<String>(unit);
    map['pack_size'] = Variable<int>(packSize);
    map['last_unit_cost_centimes'] = Variable<int>(lastUnitCostCentimes);
    map['on_hand_qty'] = Variable<int>(onHandQty);
    map['available_qty'] = Variable<int>(availableQty);
    map['active'] = Variable<bool>(active);
    if (!nullToAbsent || photoUrl != null) {
      map['photo_url'] = Variable<String>(photoUrl);
    }
    map['prices_json'] = Variable<String>(pricesJson);
    map['barcodes_json'] = Variable<String>(barcodesJson);
    map['synced_at'] = Variable<DateTime>(syncedAt);
    return map;
  }

  CachedProductsCompanion toCompanion(bool nullToAbsent) {
    return CachedProductsCompanion(
      id: Value(id),
      nameAr: Value(nameAr),
      nameFr: Value(nameFr),
      category: Value(category),
      unit: Value(unit),
      packSize: Value(packSize),
      lastUnitCostCentimes: Value(lastUnitCostCentimes),
      onHandQty: Value(onHandQty),
      availableQty: Value(availableQty),
      active: Value(active),
      photoUrl: photoUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(photoUrl),
      pricesJson: Value(pricesJson),
      barcodesJson: Value(barcodesJson),
      syncedAt: Value(syncedAt),
    );
  }

  factory CachedProduct.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedProduct(
      id: serializer.fromJson<String>(json['id']),
      nameAr: serializer.fromJson<String>(json['nameAr']),
      nameFr: serializer.fromJson<String>(json['nameFr']),
      category: serializer.fromJson<String>(json['category']),
      unit: serializer.fromJson<String>(json['unit']),
      packSize: serializer.fromJson<int>(json['packSize']),
      lastUnitCostCentimes:
          serializer.fromJson<int>(json['lastUnitCostCentimes']),
      onHandQty: serializer.fromJson<int>(json['onHandQty']),
      availableQty: serializer.fromJson<int>(json['availableQty']),
      active: serializer.fromJson<bool>(json['active']),
      photoUrl: serializer.fromJson<String?>(json['photoUrl']),
      pricesJson: serializer.fromJson<String>(json['pricesJson']),
      barcodesJson: serializer.fromJson<String>(json['barcodesJson']),
      syncedAt: serializer.fromJson<DateTime>(json['syncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'nameAr': serializer.toJson<String>(nameAr),
      'nameFr': serializer.toJson<String>(nameFr),
      'category': serializer.toJson<String>(category),
      'unit': serializer.toJson<String>(unit),
      'packSize': serializer.toJson<int>(packSize),
      'lastUnitCostCentimes': serializer.toJson<int>(lastUnitCostCentimes),
      'onHandQty': serializer.toJson<int>(onHandQty),
      'availableQty': serializer.toJson<int>(availableQty),
      'active': serializer.toJson<bool>(active),
      'photoUrl': serializer.toJson<String?>(photoUrl),
      'pricesJson': serializer.toJson<String>(pricesJson),
      'barcodesJson': serializer.toJson<String>(barcodesJson),
      'syncedAt': serializer.toJson<DateTime>(syncedAt),
    };
  }

  CachedProduct copyWith(
          {String? id,
          String? nameAr,
          String? nameFr,
          String? category,
          String? unit,
          int? packSize,
          int? lastUnitCostCentimes,
          int? onHandQty,
          int? availableQty,
          bool? active,
          Value<String?> photoUrl = const Value.absent(),
          String? pricesJson,
          String? barcodesJson,
          DateTime? syncedAt}) =>
      CachedProduct(
        id: id ?? this.id,
        nameAr: nameAr ?? this.nameAr,
        nameFr: nameFr ?? this.nameFr,
        category: category ?? this.category,
        unit: unit ?? this.unit,
        packSize: packSize ?? this.packSize,
        lastUnitCostCentimes: lastUnitCostCentimes ?? this.lastUnitCostCentimes,
        onHandQty: onHandQty ?? this.onHandQty,
        availableQty: availableQty ?? this.availableQty,
        active: active ?? this.active,
        photoUrl: photoUrl.present ? photoUrl.value : this.photoUrl,
        pricesJson: pricesJson ?? this.pricesJson,
        barcodesJson: barcodesJson ?? this.barcodesJson,
        syncedAt: syncedAt ?? this.syncedAt,
      );
  CachedProduct copyWithCompanion(CachedProductsCompanion data) {
    return CachedProduct(
      id: data.id.present ? data.id.value : this.id,
      nameAr: data.nameAr.present ? data.nameAr.value : this.nameAr,
      nameFr: data.nameFr.present ? data.nameFr.value : this.nameFr,
      category: data.category.present ? data.category.value : this.category,
      unit: data.unit.present ? data.unit.value : this.unit,
      packSize: data.packSize.present ? data.packSize.value : this.packSize,
      lastUnitCostCentimes: data.lastUnitCostCentimes.present
          ? data.lastUnitCostCentimes.value
          : this.lastUnitCostCentimes,
      onHandQty: data.onHandQty.present ? data.onHandQty.value : this.onHandQty,
      availableQty: data.availableQty.present
          ? data.availableQty.value
          : this.availableQty,
      active: data.active.present ? data.active.value : this.active,
      photoUrl: data.photoUrl.present ? data.photoUrl.value : this.photoUrl,
      pricesJson:
          data.pricesJson.present ? data.pricesJson.value : this.pricesJson,
      barcodesJson: data.barcodesJson.present
          ? data.barcodesJson.value
          : this.barcodesJson,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedProduct(')
          ..write('id: $id, ')
          ..write('nameAr: $nameAr, ')
          ..write('nameFr: $nameFr, ')
          ..write('category: $category, ')
          ..write('unit: $unit, ')
          ..write('packSize: $packSize, ')
          ..write('lastUnitCostCentimes: $lastUnitCostCentimes, ')
          ..write('onHandQty: $onHandQty, ')
          ..write('availableQty: $availableQty, ')
          ..write('active: $active, ')
          ..write('photoUrl: $photoUrl, ')
          ..write('pricesJson: $pricesJson, ')
          ..write('barcodesJson: $barcodesJson, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      nameAr,
      nameFr,
      category,
      unit,
      packSize,
      lastUnitCostCentimes,
      onHandQty,
      availableQty,
      active,
      photoUrl,
      pricesJson,
      barcodesJson,
      syncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedProduct &&
          other.id == this.id &&
          other.nameAr == this.nameAr &&
          other.nameFr == this.nameFr &&
          other.category == this.category &&
          other.unit == this.unit &&
          other.packSize == this.packSize &&
          other.lastUnitCostCentimes == this.lastUnitCostCentimes &&
          other.onHandQty == this.onHandQty &&
          other.availableQty == this.availableQty &&
          other.active == this.active &&
          other.photoUrl == this.photoUrl &&
          other.pricesJson == this.pricesJson &&
          other.barcodesJson == this.barcodesJson &&
          other.syncedAt == this.syncedAt);
}

class CachedProductsCompanion extends UpdateCompanion<CachedProduct> {
  final Value<String> id;
  final Value<String> nameAr;
  final Value<String> nameFr;
  final Value<String> category;
  final Value<String> unit;
  final Value<int> packSize;
  final Value<int> lastUnitCostCentimes;
  final Value<int> onHandQty;
  final Value<int> availableQty;
  final Value<bool> active;
  final Value<String?> photoUrl;
  final Value<String> pricesJson;
  final Value<String> barcodesJson;
  final Value<DateTime> syncedAt;
  final Value<int> rowid;
  const CachedProductsCompanion({
    this.id = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.nameFr = const Value.absent(),
    this.category = const Value.absent(),
    this.unit = const Value.absent(),
    this.packSize = const Value.absent(),
    this.lastUnitCostCentimes = const Value.absent(),
    this.onHandQty = const Value.absent(),
    this.availableQty = const Value.absent(),
    this.active = const Value.absent(),
    this.photoUrl = const Value.absent(),
    this.pricesJson = const Value.absent(),
    this.barcodesJson = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedProductsCompanion.insert({
    required String id,
    required String nameAr,
    required String nameFr,
    required String category,
    required String unit,
    required int packSize,
    required int lastUnitCostCentimes,
    required int onHandQty,
    required int availableQty,
    required bool active,
    this.photoUrl = const Value.absent(),
    required String pricesJson,
    required String barcodesJson,
    required DateTime syncedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        nameAr = Value(nameAr),
        nameFr = Value(nameFr),
        category = Value(category),
        unit = Value(unit),
        packSize = Value(packSize),
        lastUnitCostCentimes = Value(lastUnitCostCentimes),
        onHandQty = Value(onHandQty),
        availableQty = Value(availableQty),
        active = Value(active),
        pricesJson = Value(pricesJson),
        barcodesJson = Value(barcodesJson),
        syncedAt = Value(syncedAt);
  static Insertable<CachedProduct> custom({
    Expression<String>? id,
    Expression<String>? nameAr,
    Expression<String>? nameFr,
    Expression<String>? category,
    Expression<String>? unit,
    Expression<int>? packSize,
    Expression<int>? lastUnitCostCentimes,
    Expression<int>? onHandQty,
    Expression<int>? availableQty,
    Expression<bool>? active,
    Expression<String>? photoUrl,
    Expression<String>? pricesJson,
    Expression<String>? barcodesJson,
    Expression<DateTime>? syncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (nameAr != null) 'name_ar': nameAr,
      if (nameFr != null) 'name_fr': nameFr,
      if (category != null) 'category': category,
      if (unit != null) 'unit': unit,
      if (packSize != null) 'pack_size': packSize,
      if (lastUnitCostCentimes != null)
        'last_unit_cost_centimes': lastUnitCostCentimes,
      if (onHandQty != null) 'on_hand_qty': onHandQty,
      if (availableQty != null) 'available_qty': availableQty,
      if (active != null) 'active': active,
      if (photoUrl != null) 'photo_url': photoUrl,
      if (pricesJson != null) 'prices_json': pricesJson,
      if (barcodesJson != null) 'barcodes_json': barcodesJson,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedProductsCompanion copyWith(
      {Value<String>? id,
      Value<String>? nameAr,
      Value<String>? nameFr,
      Value<String>? category,
      Value<String>? unit,
      Value<int>? packSize,
      Value<int>? lastUnitCostCentimes,
      Value<int>? onHandQty,
      Value<int>? availableQty,
      Value<bool>? active,
      Value<String?>? photoUrl,
      Value<String>? pricesJson,
      Value<String>? barcodesJson,
      Value<DateTime>? syncedAt,
      Value<int>? rowid}) {
    return CachedProductsCompanion(
      id: id ?? this.id,
      nameAr: nameAr ?? this.nameAr,
      nameFr: nameFr ?? this.nameFr,
      category: category ?? this.category,
      unit: unit ?? this.unit,
      packSize: packSize ?? this.packSize,
      lastUnitCostCentimes: lastUnitCostCentimes ?? this.lastUnitCostCentimes,
      onHandQty: onHandQty ?? this.onHandQty,
      availableQty: availableQty ?? this.availableQty,
      active: active ?? this.active,
      photoUrl: photoUrl ?? this.photoUrl,
      pricesJson: pricesJson ?? this.pricesJson,
      barcodesJson: barcodesJson ?? this.barcodesJson,
      syncedAt: syncedAt ?? this.syncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (nameAr.present) {
      map['name_ar'] = Variable<String>(nameAr.value);
    }
    if (nameFr.present) {
      map['name_fr'] = Variable<String>(nameFr.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (packSize.present) {
      map['pack_size'] = Variable<int>(packSize.value);
    }
    if (lastUnitCostCentimes.present) {
      map['last_unit_cost_centimes'] =
          Variable<int>(lastUnitCostCentimes.value);
    }
    if (onHandQty.present) {
      map['on_hand_qty'] = Variable<int>(onHandQty.value);
    }
    if (availableQty.present) {
      map['available_qty'] = Variable<int>(availableQty.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (photoUrl.present) {
      map['photo_url'] = Variable<String>(photoUrl.value);
    }
    if (pricesJson.present) {
      map['prices_json'] = Variable<String>(pricesJson.value);
    }
    if (barcodesJson.present) {
      map['barcodes_json'] = Variable<String>(barcodesJson.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedProductsCompanion(')
          ..write('id: $id, ')
          ..write('nameAr: $nameAr, ')
          ..write('nameFr: $nameFr, ')
          ..write('category: $category, ')
          ..write('unit: $unit, ')
          ..write('packSize: $packSize, ')
          ..write('lastUnitCostCentimes: $lastUnitCostCentimes, ')
          ..write('onHandQty: $onHandQty, ')
          ..write('availableQty: $availableQty, ')
          ..write('active: $active, ')
          ..write('photoUrl: $photoUrl, ')
          ..write('pricesJson: $pricesJson, ')
          ..write('barcodesJson: $barcodesJson, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedCustomersTable extends CachedCustomers
    with TableInfo<$CachedCustomersTable, CachedCustomer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedCustomersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
      'phone', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _creditLimitCentimesMeta =
      const VerificationMeta('creditLimitCentimes');
  @override
  late final GeneratedColumn<int> creditLimitCentimes = GeneratedColumn<int>(
      'credit_limit_centimes', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _currentDebtCentimesMeta =
      const VerificationMeta('currentDebtCentimes');
  @override
  late final GeneratedColumn<int> currentDebtCentimes = GeneratedColumn<int>(
      'current_debt_centimes', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _priceTierMeta =
      const VerificationMeta('priceTier');
  @override
  late final GeneratedColumn<String> priceTier = GeneratedColumn<String>(
      'price_tier', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _wilayaMeta = const VerificationMeta('wilaya');
  @override
  late final GeneratedColumn<String> wilaya = GeneratedColumn<String>(
      'wilaya', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _communeMeta =
      const VerificationMeta('commune');
  @override
  late final GeneratedColumn<String> commune = GeneratedColumn<String>(
      'commune', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _addressTextMeta =
      const VerificationMeta('addressText');
  @override
  late final GeneratedColumn<String> addressText = GeneratedColumn<String>(
      'address_text', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _syncedAtMeta =
      const VerificationMeta('syncedAt');
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
      'synced_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
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
        syncedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_customers';
  @override
  VerificationContext validateIntegrity(Insertable<CachedCustomer> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('phone')) {
      context.handle(
          _phoneMeta, phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta));
    } else if (isInserting) {
      context.missing(_phoneMeta);
    }
    if (data.containsKey('credit_limit_centimes')) {
      context.handle(
          _creditLimitCentimesMeta,
          creditLimitCentimes.isAcceptableOrUnknown(
              data['credit_limit_centimes']!, _creditLimitCentimesMeta));
    } else if (isInserting) {
      context.missing(_creditLimitCentimesMeta);
    }
    if (data.containsKey('current_debt_centimes')) {
      context.handle(
          _currentDebtCentimesMeta,
          currentDebtCentimes.isAcceptableOrUnknown(
              data['current_debt_centimes']!, _currentDebtCentimesMeta));
    } else if (isInserting) {
      context.missing(_currentDebtCentimesMeta);
    }
    if (data.containsKey('price_tier')) {
      context.handle(_priceTierMeta,
          priceTier.isAcceptableOrUnknown(data['price_tier']!, _priceTierMeta));
    } else if (isInserting) {
      context.missing(_priceTierMeta);
    }
    if (data.containsKey('wilaya')) {
      context.handle(_wilayaMeta,
          wilaya.isAcceptableOrUnknown(data['wilaya']!, _wilayaMeta));
    }
    if (data.containsKey('commune')) {
      context.handle(_communeMeta,
          commune.isAcceptableOrUnknown(data['commune']!, _communeMeta));
    }
    if (data.containsKey('address_text')) {
      context.handle(
          _addressTextMeta,
          addressText.isAcceptableOrUnknown(
              data['address_text']!, _addressTextMeta));
    }
    if (data.containsKey('synced_at')) {
      context.handle(_syncedAtMeta,
          syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta));
    } else if (isInserting) {
      context.missing(_syncedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedCustomer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedCustomer(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      phone: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}phone'])!,
      creditLimitCentimes: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}credit_limit_centimes'])!,
      currentDebtCentimes: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}current_debt_centimes'])!,
      priceTier: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}price_tier'])!,
      wilaya: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}wilaya']),
      commune: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}commune']),
      addressText: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}address_text']),
      syncedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}synced_at'])!,
    );
  }

  @override
  $CachedCustomersTable createAlias(String alias) {
    return $CachedCustomersTable(attachedDatabase, alias);
  }
}

class CachedCustomer extends DataClass implements Insertable<CachedCustomer> {
  final String id;
  final String userId;
  final String name;
  final String phone;
  final int creditLimitCentimes;
  final int currentDebtCentimes;
  final String priceTier;
  final String? wilaya;
  final String? commune;
  final String? addressText;
  final DateTime syncedAt;
  const CachedCustomer(
      {required this.id,
      required this.userId,
      required this.name,
      required this.phone,
      required this.creditLimitCentimes,
      required this.currentDebtCentimes,
      required this.priceTier,
      this.wilaya,
      this.commune,
      this.addressText,
      required this.syncedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['name'] = Variable<String>(name);
    map['phone'] = Variable<String>(phone);
    map['credit_limit_centimes'] = Variable<int>(creditLimitCentimes);
    map['current_debt_centimes'] = Variable<int>(currentDebtCentimes);
    map['price_tier'] = Variable<String>(priceTier);
    if (!nullToAbsent || wilaya != null) {
      map['wilaya'] = Variable<String>(wilaya);
    }
    if (!nullToAbsent || commune != null) {
      map['commune'] = Variable<String>(commune);
    }
    if (!nullToAbsent || addressText != null) {
      map['address_text'] = Variable<String>(addressText);
    }
    map['synced_at'] = Variable<DateTime>(syncedAt);
    return map;
  }

  CachedCustomersCompanion toCompanion(bool nullToAbsent) {
    return CachedCustomersCompanion(
      id: Value(id),
      userId: Value(userId),
      name: Value(name),
      phone: Value(phone),
      creditLimitCentimes: Value(creditLimitCentimes),
      currentDebtCentimes: Value(currentDebtCentimes),
      priceTier: Value(priceTier),
      wilaya:
          wilaya == null && nullToAbsent ? const Value.absent() : Value(wilaya),
      commune: commune == null && nullToAbsent
          ? const Value.absent()
          : Value(commune),
      addressText: addressText == null && nullToAbsent
          ? const Value.absent()
          : Value(addressText),
      syncedAt: Value(syncedAt),
    );
  }

  factory CachedCustomer.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedCustomer(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      name: serializer.fromJson<String>(json['name']),
      phone: serializer.fromJson<String>(json['phone']),
      creditLimitCentimes:
          serializer.fromJson<int>(json['creditLimitCentimes']),
      currentDebtCentimes:
          serializer.fromJson<int>(json['currentDebtCentimes']),
      priceTier: serializer.fromJson<String>(json['priceTier']),
      wilaya: serializer.fromJson<String?>(json['wilaya']),
      commune: serializer.fromJson<String?>(json['commune']),
      addressText: serializer.fromJson<String?>(json['addressText']),
      syncedAt: serializer.fromJson<DateTime>(json['syncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'name': serializer.toJson<String>(name),
      'phone': serializer.toJson<String>(phone),
      'creditLimitCentimes': serializer.toJson<int>(creditLimitCentimes),
      'currentDebtCentimes': serializer.toJson<int>(currentDebtCentimes),
      'priceTier': serializer.toJson<String>(priceTier),
      'wilaya': serializer.toJson<String?>(wilaya),
      'commune': serializer.toJson<String?>(commune),
      'addressText': serializer.toJson<String?>(addressText),
      'syncedAt': serializer.toJson<DateTime>(syncedAt),
    };
  }

  CachedCustomer copyWith(
          {String? id,
          String? userId,
          String? name,
          String? phone,
          int? creditLimitCentimes,
          int? currentDebtCentimes,
          String? priceTier,
          Value<String?> wilaya = const Value.absent(),
          Value<String?> commune = const Value.absent(),
          Value<String?> addressText = const Value.absent(),
          DateTime? syncedAt}) =>
      CachedCustomer(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        creditLimitCentimes: creditLimitCentimes ?? this.creditLimitCentimes,
        currentDebtCentimes: currentDebtCentimes ?? this.currentDebtCentimes,
        priceTier: priceTier ?? this.priceTier,
        wilaya: wilaya.present ? wilaya.value : this.wilaya,
        commune: commune.present ? commune.value : this.commune,
        addressText: addressText.present ? addressText.value : this.addressText,
        syncedAt: syncedAt ?? this.syncedAt,
      );
  CachedCustomer copyWithCompanion(CachedCustomersCompanion data) {
    return CachedCustomer(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      name: data.name.present ? data.name.value : this.name,
      phone: data.phone.present ? data.phone.value : this.phone,
      creditLimitCentimes: data.creditLimitCentimes.present
          ? data.creditLimitCentimes.value
          : this.creditLimitCentimes,
      currentDebtCentimes: data.currentDebtCentimes.present
          ? data.currentDebtCentimes.value
          : this.currentDebtCentimes,
      priceTier: data.priceTier.present ? data.priceTier.value : this.priceTier,
      wilaya: data.wilaya.present ? data.wilaya.value : this.wilaya,
      commune: data.commune.present ? data.commune.value : this.commune,
      addressText:
          data.addressText.present ? data.addressText.value : this.addressText,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedCustomer(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('creditLimitCentimes: $creditLimitCentimes, ')
          ..write('currentDebtCentimes: $currentDebtCentimes, ')
          ..write('priceTier: $priceTier, ')
          ..write('wilaya: $wilaya, ')
          ..write('commune: $commune, ')
          ..write('addressText: $addressText, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, userId, name, phone, creditLimitCentimes,
      currentDebtCentimes, priceTier, wilaya, commune, addressText, syncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedCustomer &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.name == this.name &&
          other.phone == this.phone &&
          other.creditLimitCentimes == this.creditLimitCentimes &&
          other.currentDebtCentimes == this.currentDebtCentimes &&
          other.priceTier == this.priceTier &&
          other.wilaya == this.wilaya &&
          other.commune == this.commune &&
          other.addressText == this.addressText &&
          other.syncedAt == this.syncedAt);
}

class CachedCustomersCompanion extends UpdateCompanion<CachedCustomer> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> name;
  final Value<String> phone;
  final Value<int> creditLimitCentimes;
  final Value<int> currentDebtCentimes;
  final Value<String> priceTier;
  final Value<String?> wilaya;
  final Value<String?> commune;
  final Value<String?> addressText;
  final Value<DateTime> syncedAt;
  final Value<int> rowid;
  const CachedCustomersCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.name = const Value.absent(),
    this.phone = const Value.absent(),
    this.creditLimitCentimes = const Value.absent(),
    this.currentDebtCentimes = const Value.absent(),
    this.priceTier = const Value.absent(),
    this.wilaya = const Value.absent(),
    this.commune = const Value.absent(),
    this.addressText = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedCustomersCompanion.insert({
    required String id,
    required String userId,
    required String name,
    required String phone,
    required int creditLimitCentimes,
    required int currentDebtCentimes,
    required String priceTier,
    this.wilaya = const Value.absent(),
    this.commune = const Value.absent(),
    this.addressText = const Value.absent(),
    required DateTime syncedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        userId = Value(userId),
        name = Value(name),
        phone = Value(phone),
        creditLimitCentimes = Value(creditLimitCentimes),
        currentDebtCentimes = Value(currentDebtCentimes),
        priceTier = Value(priceTier),
        syncedAt = Value(syncedAt);
  static Insertable<CachedCustomer> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? name,
    Expression<String>? phone,
    Expression<int>? creditLimitCentimes,
    Expression<int>? currentDebtCentimes,
    Expression<String>? priceTier,
    Expression<String>? wilaya,
    Expression<String>? commune,
    Expression<String>? addressText,
    Expression<DateTime>? syncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (creditLimitCentimes != null)
        'credit_limit_centimes': creditLimitCentimes,
      if (currentDebtCentimes != null)
        'current_debt_centimes': currentDebtCentimes,
      if (priceTier != null) 'price_tier': priceTier,
      if (wilaya != null) 'wilaya': wilaya,
      if (commune != null) 'commune': commune,
      if (addressText != null) 'address_text': addressText,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedCustomersCompanion copyWith(
      {Value<String>? id,
      Value<String>? userId,
      Value<String>? name,
      Value<String>? phone,
      Value<int>? creditLimitCentimes,
      Value<int>? currentDebtCentimes,
      Value<String>? priceTier,
      Value<String?>? wilaya,
      Value<String?>? commune,
      Value<String?>? addressText,
      Value<DateTime>? syncedAt,
      Value<int>? rowid}) {
    return CachedCustomersCompanion(
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
      syncedAt: syncedAt ?? this.syncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (creditLimitCentimes.present) {
      map['credit_limit_centimes'] = Variable<int>(creditLimitCentimes.value);
    }
    if (currentDebtCentimes.present) {
      map['current_debt_centimes'] = Variable<int>(currentDebtCentimes.value);
    }
    if (priceTier.present) {
      map['price_tier'] = Variable<String>(priceTier.value);
    }
    if (wilaya.present) {
      map['wilaya'] = Variable<String>(wilaya.value);
    }
    if (commune.present) {
      map['commune'] = Variable<String>(commune.value);
    }
    if (addressText.present) {
      map['address_text'] = Variable<String>(addressText.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedCustomersCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('creditLimitCentimes: $creditLimitCentimes, ')
          ..write('currentDebtCentimes: $currentDebtCentimes, ')
          ..write('priceTier: $priceTier, ')
          ..write('wilaya: $wilaya, ')
          ..write('commune: $commune, ')
          ..write('addressText: $addressText, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingOperationsTable extends PendingOperations
    with TableInfo<$PendingOperationsTable, PendingOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _clientIdMeta =
      const VerificationMeta('clientId');
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
      'client_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _operationTypeMeta =
      const VerificationMeta('operationType');
  @override
  late final GeneratedColumn<String> operationType = GeneratedColumn<String>(
      'operation_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadJsonMeta =
      const VerificationMeta('payloadJson');
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
      'payload_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pending'));
  static const VerificationMeta _retryCountMeta =
      const VerificationMeta('retryCount');
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
      'retry_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastErrorMeta =
      const VerificationMeta('lastError');
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
      'last_error', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        clientId,
        operationType,
        payloadJson,
        createdAt,
        status,
        retryCount,
        lastError
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_operations';
  @override
  VerificationContext validateIntegrity(Insertable<PendingOperation> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('client_id')) {
      context.handle(_clientIdMeta,
          clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta));
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('operation_type')) {
      context.handle(
          _operationTypeMeta,
          operationType.isAcceptableOrUnknown(
              data['operation_type']!, _operationTypeMeta));
    } else if (isInserting) {
      context.missing(_operationTypeMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
          _payloadJsonMeta,
          payloadJson.isAcceptableOrUnknown(
              data['payload_json']!, _payloadJsonMeta));
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('retry_count')) {
      context.handle(
          _retryCountMeta,
          retryCount.isAcceptableOrUnknown(
              data['retry_count']!, _retryCountMeta));
    }
    if (data.containsKey('last_error')) {
      context.handle(_lastErrorMeta,
          lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {clientId};
  @override
  PendingOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingOperation(
      clientId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}client_id'])!,
      operationType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}operation_type'])!,
      payloadJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload_json'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      retryCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}retry_count'])!,
      lastError: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_error']),
    );
  }

  @override
  $PendingOperationsTable createAlias(String alias) {
    return $PendingOperationsTable(attachedDatabase, alias);
  }
}

class PendingOperation extends DataClass
    implements Insertable<PendingOperation> {
  /// UUID generated on-device before the operation — used as idempotency key.
  final String clientId;

  /// 'pos_sale' | 'delivery' | 'debt_payment'
  final String operationType;

  /// Full JSON payload matching the corresponding RPC parameters.
  final String payloadJson;
  final DateTime createdAt;

  /// 'pending' | 'syncing' | 'failed'
  final String status;
  final int retryCount;
  final String? lastError;
  const PendingOperation(
      {required this.clientId,
      required this.operationType,
      required this.payloadJson,
      required this.createdAt,
      required this.status,
      required this.retryCount,
      this.lastError});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['client_id'] = Variable<String>(clientId);
    map['operation_type'] = Variable<String>(operationType);
    map['payload_json'] = Variable<String>(payloadJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['status'] = Variable<String>(status);
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  PendingOperationsCompanion toCompanion(bool nullToAbsent) {
    return PendingOperationsCompanion(
      clientId: Value(clientId),
      operationType: Value(operationType),
      payloadJson: Value(payloadJson),
      createdAt: Value(createdAt),
      status: Value(status),
      retryCount: Value(retryCount),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory PendingOperation.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingOperation(
      clientId: serializer.fromJson<String>(json['clientId']),
      operationType: serializer.fromJson<String>(json['operationType']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      status: serializer.fromJson<String>(json['status']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'clientId': serializer.toJson<String>(clientId),
      'operationType': serializer.toJson<String>(operationType),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'status': serializer.toJson<String>(status),
      'retryCount': serializer.toJson<int>(retryCount),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  PendingOperation copyWith(
          {String? clientId,
          String? operationType,
          String? payloadJson,
          DateTime? createdAt,
          String? status,
          int? retryCount,
          Value<String?> lastError = const Value.absent()}) =>
      PendingOperation(
        clientId: clientId ?? this.clientId,
        operationType: operationType ?? this.operationType,
        payloadJson: payloadJson ?? this.payloadJson,
        createdAt: createdAt ?? this.createdAt,
        status: status ?? this.status,
        retryCount: retryCount ?? this.retryCount,
        lastError: lastError.present ? lastError.value : this.lastError,
      );
  PendingOperation copyWithCompanion(PendingOperationsCompanion data) {
    return PendingOperation(
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      operationType: data.operationType.present
          ? data.operationType.value
          : this.operationType,
      payloadJson:
          data.payloadJson.present ? data.payloadJson.value : this.payloadJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      status: data.status.present ? data.status.value : this.status,
      retryCount:
          data.retryCount.present ? data.retryCount.value : this.retryCount,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingOperation(')
          ..write('clientId: $clientId, ')
          ..write('operationType: $operationType, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(clientId, operationType, payloadJson,
      createdAt, status, retryCount, lastError);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingOperation &&
          other.clientId == this.clientId &&
          other.operationType == this.operationType &&
          other.payloadJson == this.payloadJson &&
          other.createdAt == this.createdAt &&
          other.status == this.status &&
          other.retryCount == this.retryCount &&
          other.lastError == this.lastError);
}

class PendingOperationsCompanion extends UpdateCompanion<PendingOperation> {
  final Value<String> clientId;
  final Value<String> operationType;
  final Value<String> payloadJson;
  final Value<DateTime> createdAt;
  final Value<String> status;
  final Value<int> retryCount;
  final Value<String?> lastError;
  final Value<int> rowid;
  const PendingOperationsCompanion({
    this.clientId = const Value.absent(),
    this.operationType = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.status = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingOperationsCompanion.insert({
    required String clientId,
    required String operationType,
    required String payloadJson,
    required DateTime createdAt,
    this.status = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : clientId = Value(clientId),
        operationType = Value(operationType),
        payloadJson = Value(payloadJson),
        createdAt = Value(createdAt);
  static Insertable<PendingOperation> custom({
    Expression<String>? clientId,
    Expression<String>? operationType,
    Expression<String>? payloadJson,
    Expression<DateTime>? createdAt,
    Expression<String>? status,
    Expression<int>? retryCount,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (clientId != null) 'client_id': clientId,
      if (operationType != null) 'operation_type': operationType,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (createdAt != null) 'created_at': createdAt,
      if (status != null) 'status': status,
      if (retryCount != null) 'retry_count': retryCount,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingOperationsCompanion copyWith(
      {Value<String>? clientId,
      Value<String>? operationType,
      Value<String>? payloadJson,
      Value<DateTime>? createdAt,
      Value<String>? status,
      Value<int>? retryCount,
      Value<String?>? lastError,
      Value<int>? rowid}) {
    return PendingOperationsCompanion(
      clientId: clientId ?? this.clientId,
      operationType: operationType ?? this.operationType,
      payloadJson: payloadJson ?? this.payloadJson,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (operationType.present) {
      map['operation_type'] = Variable<String>(operationType.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingOperationsCompanion(')
          ..write('clientId: $clientId, ')
          ..write('operationType: $operationType, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncMetaTable extends SyncMeta
    with TableInfo<$SyncMetaTable, SyncMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  @override
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
      'entity', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lastSyncedAtMeta =
      const VerificationMeta('lastSyncedAt');
  @override
  late final GeneratedColumn<DateTime> lastSyncedAt = GeneratedColumn<DateTime>(
      'last_synced_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [entity, lastSyncedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_meta';
  @override
  VerificationContext validateIntegrity(Insertable<SyncMetaData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entity')) {
      context.handle(_entityMeta,
          entity.isAcceptableOrUnknown(data['entity']!, _entityMeta));
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
          _lastSyncedAtMeta,
          lastSyncedAt.isAcceptableOrUnknown(
              data['last_synced_at']!, _lastSyncedAtMeta));
    } else if (isInserting) {
      context.missing(_lastSyncedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entity};
  @override
  SyncMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMetaData(
      entity: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity'])!,
      lastSyncedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_synced_at'])!,
    );
  }

  @override
  $SyncMetaTable createAlias(String alias) {
    return $SyncMetaTable(attachedDatabase, alias);
  }
}

class SyncMetaData extends DataClass implements Insertable<SyncMetaData> {
  final String entity;
  final DateTime lastSyncedAt;
  const SyncMetaData({required this.entity, required this.lastSyncedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entity'] = Variable<String>(entity);
    map['last_synced_at'] = Variable<DateTime>(lastSyncedAt);
    return map;
  }

  SyncMetaCompanion toCompanion(bool nullToAbsent) {
    return SyncMetaCompanion(
      entity: Value(entity),
      lastSyncedAt: Value(lastSyncedAt),
    );
  }

  factory SyncMetaData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMetaData(
      entity: serializer.fromJson<String>(json['entity']),
      lastSyncedAt: serializer.fromJson<DateTime>(json['lastSyncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entity': serializer.toJson<String>(entity),
      'lastSyncedAt': serializer.toJson<DateTime>(lastSyncedAt),
    };
  }

  SyncMetaData copyWith({String? entity, DateTime? lastSyncedAt}) =>
      SyncMetaData(
        entity: entity ?? this.entity,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      );
  SyncMetaData copyWithCompanion(SyncMetaCompanion data) {
    return SyncMetaData(
      entity: data.entity.present ? data.entity.value : this.entity,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaData(')
          ..write('entity: $entity, ')
          ..write('lastSyncedAt: $lastSyncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(entity, lastSyncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetaData &&
          other.entity == this.entity &&
          other.lastSyncedAt == this.lastSyncedAt);
}

class SyncMetaCompanion extends UpdateCompanion<SyncMetaData> {
  final Value<String> entity;
  final Value<DateTime> lastSyncedAt;
  final Value<int> rowid;
  const SyncMetaCompanion({
    this.entity = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncMetaCompanion.insert({
    required String entity,
    required DateTime lastSyncedAt,
    this.rowid = const Value.absent(),
  })  : entity = Value(entity),
        lastSyncedAt = Value(lastSyncedAt);
  static Insertable<SyncMetaData> custom({
    Expression<String>? entity,
    Expression<DateTime>? lastSyncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entity != null) 'entity': entity,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncMetaCompanion copyWith(
      {Value<String>? entity,
      Value<DateTime>? lastSyncedAt,
      Value<int>? rowid}) {
    return SyncMetaCompanion(
      entity: entity ?? this.entity,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaCompanion(')
          ..write('entity: $entity, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CachedProductsTable cachedProducts = $CachedProductsTable(this);
  late final $CachedCustomersTable cachedCustomers =
      $CachedCustomersTable(this);
  late final $PendingOperationsTable pendingOperations =
      $PendingOperationsTable(this);
  late final $SyncMetaTable syncMeta = $SyncMetaTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [cachedProducts, cachedCustomers, pendingOperations, syncMeta];
}

typedef $$CachedProductsTableCreateCompanionBuilder = CachedProductsCompanion
    Function({
  required String id,
  required String nameAr,
  required String nameFr,
  required String category,
  required String unit,
  required int packSize,
  required int lastUnitCostCentimes,
  required int onHandQty,
  required int availableQty,
  required bool active,
  Value<String?> photoUrl,
  required String pricesJson,
  required String barcodesJson,
  required DateTime syncedAt,
  Value<int> rowid,
});
typedef $$CachedProductsTableUpdateCompanionBuilder = CachedProductsCompanion
    Function({
  Value<String> id,
  Value<String> nameAr,
  Value<String> nameFr,
  Value<String> category,
  Value<String> unit,
  Value<int> packSize,
  Value<int> lastUnitCostCentimes,
  Value<int> onHandQty,
  Value<int> availableQty,
  Value<bool> active,
  Value<String?> photoUrl,
  Value<String> pricesJson,
  Value<String> barcodesJson,
  Value<DateTime> syncedAt,
  Value<int> rowid,
});

class $$CachedProductsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedProductsTable> {
  $$CachedProductsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get nameAr => $composableBuilder(
      column: $table.nameAr, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get nameFr => $composableBuilder(
      column: $table.nameFr, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get unit => $composableBuilder(
      column: $table.unit, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get packSize => $composableBuilder(
      column: $table.packSize, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastUnitCostCentimes => $composableBuilder(
      column: $table.lastUnitCostCentimes,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get onHandQty => $composableBuilder(
      column: $table.onHandQty, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get availableQty => $composableBuilder(
      column: $table.availableQty, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get active => $composableBuilder(
      column: $table.active, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get photoUrl => $composableBuilder(
      column: $table.photoUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pricesJson => $composableBuilder(
      column: $table.pricesJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get barcodesJson => $composableBuilder(
      column: $table.barcodesJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedProductsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedProductsTable> {
  $$CachedProductsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get nameAr => $composableBuilder(
      column: $table.nameAr, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get nameFr => $composableBuilder(
      column: $table.nameFr, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get unit => $composableBuilder(
      column: $table.unit, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get packSize => $composableBuilder(
      column: $table.packSize, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastUnitCostCentimes => $composableBuilder(
      column: $table.lastUnitCostCentimes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get onHandQty => $composableBuilder(
      column: $table.onHandQty, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get availableQty => $composableBuilder(
      column: $table.availableQty,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get active => $composableBuilder(
      column: $table.active, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get photoUrl => $composableBuilder(
      column: $table.photoUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pricesJson => $composableBuilder(
      column: $table.pricesJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get barcodesJson => $composableBuilder(
      column: $table.barcodesJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnOrderings(column));
}

class $$CachedProductsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedProductsTable> {
  $$CachedProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get nameAr =>
      $composableBuilder(column: $table.nameAr, builder: (column) => column);

  GeneratedColumn<String> get nameFr =>
      $composableBuilder(column: $table.nameFr, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<int> get packSize =>
      $composableBuilder(column: $table.packSize, builder: (column) => column);

  GeneratedColumn<int> get lastUnitCostCentimes => $composableBuilder(
      column: $table.lastUnitCostCentimes, builder: (column) => column);

  GeneratedColumn<int> get onHandQty =>
      $composableBuilder(column: $table.onHandQty, builder: (column) => column);

  GeneratedColumn<int> get availableQty => $composableBuilder(
      column: $table.availableQty, builder: (column) => column);

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  GeneratedColumn<String> get photoUrl =>
      $composableBuilder(column: $table.photoUrl, builder: (column) => column);

  GeneratedColumn<String> get pricesJson => $composableBuilder(
      column: $table.pricesJson, builder: (column) => column);

  GeneratedColumn<String> get barcodesJson => $composableBuilder(
      column: $table.barcodesJson, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);
}

class $$CachedProductsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedProductsTable,
    CachedProduct,
    $$CachedProductsTableFilterComposer,
    $$CachedProductsTableOrderingComposer,
    $$CachedProductsTableAnnotationComposer,
    $$CachedProductsTableCreateCompanionBuilder,
    $$CachedProductsTableUpdateCompanionBuilder,
    (
      CachedProduct,
      BaseReferences<_$AppDatabase, $CachedProductsTable, CachedProduct>
    ),
    CachedProduct,
    PrefetchHooks Function()> {
  $$CachedProductsTableTableManager(
      _$AppDatabase db, $CachedProductsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> nameAr = const Value.absent(),
            Value<String> nameFr = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<String> unit = const Value.absent(),
            Value<int> packSize = const Value.absent(),
            Value<int> lastUnitCostCentimes = const Value.absent(),
            Value<int> onHandQty = const Value.absent(),
            Value<int> availableQty = const Value.absent(),
            Value<bool> active = const Value.absent(),
            Value<String?> photoUrl = const Value.absent(),
            Value<String> pricesJson = const Value.absent(),
            Value<String> barcodesJson = const Value.absent(),
            Value<DateTime> syncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedProductsCompanion(
            id: id,
            nameAr: nameAr,
            nameFr: nameFr,
            category: category,
            unit: unit,
            packSize: packSize,
            lastUnitCostCentimes: lastUnitCostCentimes,
            onHandQty: onHandQty,
            availableQty: availableQty,
            active: active,
            photoUrl: photoUrl,
            pricesJson: pricesJson,
            barcodesJson: barcodesJson,
            syncedAt: syncedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String nameAr,
            required String nameFr,
            required String category,
            required String unit,
            required int packSize,
            required int lastUnitCostCentimes,
            required int onHandQty,
            required int availableQty,
            required bool active,
            Value<String?> photoUrl = const Value.absent(),
            required String pricesJson,
            required String barcodesJson,
            required DateTime syncedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedProductsCompanion.insert(
            id: id,
            nameAr: nameAr,
            nameFr: nameFr,
            category: category,
            unit: unit,
            packSize: packSize,
            lastUnitCostCentimes: lastUnitCostCentimes,
            onHandQty: onHandQty,
            availableQty: availableQty,
            active: active,
            photoUrl: photoUrl,
            pricesJson: pricesJson,
            barcodesJson: barcodesJson,
            syncedAt: syncedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedProductsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CachedProductsTable,
    CachedProduct,
    $$CachedProductsTableFilterComposer,
    $$CachedProductsTableOrderingComposer,
    $$CachedProductsTableAnnotationComposer,
    $$CachedProductsTableCreateCompanionBuilder,
    $$CachedProductsTableUpdateCompanionBuilder,
    (
      CachedProduct,
      BaseReferences<_$AppDatabase, $CachedProductsTable, CachedProduct>
    ),
    CachedProduct,
    PrefetchHooks Function()>;
typedef $$CachedCustomersTableCreateCompanionBuilder = CachedCustomersCompanion
    Function({
  required String id,
  required String userId,
  required String name,
  required String phone,
  required int creditLimitCentimes,
  required int currentDebtCentimes,
  required String priceTier,
  Value<String?> wilaya,
  Value<String?> commune,
  Value<String?> addressText,
  required DateTime syncedAt,
  Value<int> rowid,
});
typedef $$CachedCustomersTableUpdateCompanionBuilder = CachedCustomersCompanion
    Function({
  Value<String> id,
  Value<String> userId,
  Value<String> name,
  Value<String> phone,
  Value<int> creditLimitCentimes,
  Value<int> currentDebtCentimes,
  Value<String> priceTier,
  Value<String?> wilaya,
  Value<String?> commune,
  Value<String?> addressText,
  Value<DateTime> syncedAt,
  Value<int> rowid,
});

class $$CachedCustomersTableFilterComposer
    extends Composer<_$AppDatabase, $CachedCustomersTable> {
  $$CachedCustomersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get phone => $composableBuilder(
      column: $table.phone, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get creditLimitCentimes => $composableBuilder(
      column: $table.creditLimitCentimes,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get currentDebtCentimes => $composableBuilder(
      column: $table.currentDebtCentimes,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get priceTier => $composableBuilder(
      column: $table.priceTier, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get wilaya => $composableBuilder(
      column: $table.wilaya, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get commune => $composableBuilder(
      column: $table.commune, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get addressText => $composableBuilder(
      column: $table.addressText, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedCustomersTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedCustomersTable> {
  $$CachedCustomersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get phone => $composableBuilder(
      column: $table.phone, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get creditLimitCentimes => $composableBuilder(
      column: $table.creditLimitCentimes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get currentDebtCentimes => $composableBuilder(
      column: $table.currentDebtCentimes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get priceTier => $composableBuilder(
      column: $table.priceTier, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get wilaya => $composableBuilder(
      column: $table.wilaya, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get commune => $composableBuilder(
      column: $table.commune, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get addressText => $composableBuilder(
      column: $table.addressText, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnOrderings(column));
}

class $$CachedCustomersTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedCustomersTable> {
  $$CachedCustomersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<int> get creditLimitCentimes => $composableBuilder(
      column: $table.creditLimitCentimes, builder: (column) => column);

  GeneratedColumn<int> get currentDebtCentimes => $composableBuilder(
      column: $table.currentDebtCentimes, builder: (column) => column);

  GeneratedColumn<String> get priceTier =>
      $composableBuilder(column: $table.priceTier, builder: (column) => column);

  GeneratedColumn<String> get wilaya =>
      $composableBuilder(column: $table.wilaya, builder: (column) => column);

  GeneratedColumn<String> get commune =>
      $composableBuilder(column: $table.commune, builder: (column) => column);

  GeneratedColumn<String> get addressText => $composableBuilder(
      column: $table.addressText, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);
}

class $$CachedCustomersTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedCustomersTable,
    CachedCustomer,
    $$CachedCustomersTableFilterComposer,
    $$CachedCustomersTableOrderingComposer,
    $$CachedCustomersTableAnnotationComposer,
    $$CachedCustomersTableCreateCompanionBuilder,
    $$CachedCustomersTableUpdateCompanionBuilder,
    (
      CachedCustomer,
      BaseReferences<_$AppDatabase, $CachedCustomersTable, CachedCustomer>
    ),
    CachedCustomer,
    PrefetchHooks Function()> {
  $$CachedCustomersTableTableManager(
      _$AppDatabase db, $CachedCustomersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedCustomersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedCustomersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedCustomersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> userId = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> phone = const Value.absent(),
            Value<int> creditLimitCentimes = const Value.absent(),
            Value<int> currentDebtCentimes = const Value.absent(),
            Value<String> priceTier = const Value.absent(),
            Value<String?> wilaya = const Value.absent(),
            Value<String?> commune = const Value.absent(),
            Value<String?> addressText = const Value.absent(),
            Value<DateTime> syncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedCustomersCompanion(
            id: id,
            userId: userId,
            name: name,
            phone: phone,
            creditLimitCentimes: creditLimitCentimes,
            currentDebtCentimes: currentDebtCentimes,
            priceTier: priceTier,
            wilaya: wilaya,
            commune: commune,
            addressText: addressText,
            syncedAt: syncedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String userId,
            required String name,
            required String phone,
            required int creditLimitCentimes,
            required int currentDebtCentimes,
            required String priceTier,
            Value<String?> wilaya = const Value.absent(),
            Value<String?> commune = const Value.absent(),
            Value<String?> addressText = const Value.absent(),
            required DateTime syncedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedCustomersCompanion.insert(
            id: id,
            userId: userId,
            name: name,
            phone: phone,
            creditLimitCentimes: creditLimitCentimes,
            currentDebtCentimes: currentDebtCentimes,
            priceTier: priceTier,
            wilaya: wilaya,
            commune: commune,
            addressText: addressText,
            syncedAt: syncedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedCustomersTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CachedCustomersTable,
    CachedCustomer,
    $$CachedCustomersTableFilterComposer,
    $$CachedCustomersTableOrderingComposer,
    $$CachedCustomersTableAnnotationComposer,
    $$CachedCustomersTableCreateCompanionBuilder,
    $$CachedCustomersTableUpdateCompanionBuilder,
    (
      CachedCustomer,
      BaseReferences<_$AppDatabase, $CachedCustomersTable, CachedCustomer>
    ),
    CachedCustomer,
    PrefetchHooks Function()>;
typedef $$PendingOperationsTableCreateCompanionBuilder
    = PendingOperationsCompanion Function({
  required String clientId,
  required String operationType,
  required String payloadJson,
  required DateTime createdAt,
  Value<String> status,
  Value<int> retryCount,
  Value<String?> lastError,
  Value<int> rowid,
});
typedef $$PendingOperationsTableUpdateCompanionBuilder
    = PendingOperationsCompanion Function({
  Value<String> clientId,
  Value<String> operationType,
  Value<String> payloadJson,
  Value<DateTime> createdAt,
  Value<String> status,
  Value<int> retryCount,
  Value<String?> lastError,
  Value<int> rowid,
});

class $$PendingOperationsTableFilterComposer
    extends Composer<_$AppDatabase, $PendingOperationsTable> {
  $$PendingOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get clientId => $composableBuilder(
      column: $table.clientId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get operationType => $composableBuilder(
      column: $table.operationType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnFilters(column));
}

class $$PendingOperationsTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingOperationsTable> {
  $$PendingOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get clientId => $composableBuilder(
      column: $table.clientId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get operationType => $composableBuilder(
      column: $table.operationType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnOrderings(column));
}

class $$PendingOperationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingOperationsTable> {
  $$PendingOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<String> get operationType => $composableBuilder(
      column: $table.operationType, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$PendingOperationsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PendingOperationsTable,
    PendingOperation,
    $$PendingOperationsTableFilterComposer,
    $$PendingOperationsTableOrderingComposer,
    $$PendingOperationsTableAnnotationComposer,
    $$PendingOperationsTableCreateCompanionBuilder,
    $$PendingOperationsTableUpdateCompanionBuilder,
    (
      PendingOperation,
      BaseReferences<_$AppDatabase, $PendingOperationsTable, PendingOperation>
    ),
    PendingOperation,
    PrefetchHooks Function()> {
  $$PendingOperationsTableTableManager(
      _$AppDatabase db, $PendingOperationsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingOperationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingOperationsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> clientId = const Value.absent(),
            Value<String> operationType = const Value.absent(),
            Value<String> payloadJson = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int> retryCount = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PendingOperationsCompanion(
            clientId: clientId,
            operationType: operationType,
            payloadJson: payloadJson,
            createdAt: createdAt,
            status: status,
            retryCount: retryCount,
            lastError: lastError,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String clientId,
            required String operationType,
            required String payloadJson,
            required DateTime createdAt,
            Value<String> status = const Value.absent(),
            Value<int> retryCount = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PendingOperationsCompanion.insert(
            clientId: clientId,
            operationType: operationType,
            payloadJson: payloadJson,
            createdAt: createdAt,
            status: status,
            retryCount: retryCount,
            lastError: lastError,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PendingOperationsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PendingOperationsTable,
    PendingOperation,
    $$PendingOperationsTableFilterComposer,
    $$PendingOperationsTableOrderingComposer,
    $$PendingOperationsTableAnnotationComposer,
    $$PendingOperationsTableCreateCompanionBuilder,
    $$PendingOperationsTableUpdateCompanionBuilder,
    (
      PendingOperation,
      BaseReferences<_$AppDatabase, $PendingOperationsTable, PendingOperation>
    ),
    PendingOperation,
    PrefetchHooks Function()>;
typedef $$SyncMetaTableCreateCompanionBuilder = SyncMetaCompanion Function({
  required String entity,
  required DateTime lastSyncedAt,
  Value<int> rowid,
});
typedef $$SyncMetaTableUpdateCompanionBuilder = SyncMetaCompanion Function({
  Value<String> entity,
  Value<DateTime> lastSyncedAt,
  Value<int> rowid,
});

class $$SyncMetaTableFilterComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get entity => $composableBuilder(
      column: $table.entity, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt, builder: (column) => ColumnFilters(column));
}

class $$SyncMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get entity => $composableBuilder(
      column: $table.entity, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt,
      builder: (column) => ColumnOrderings(column));
}

class $$SyncMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt, builder: (column) => column);
}

class $$SyncMetaTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SyncMetaTable,
    SyncMetaData,
    $$SyncMetaTableFilterComposer,
    $$SyncMetaTableOrderingComposer,
    $$SyncMetaTableAnnotationComposer,
    $$SyncMetaTableCreateCompanionBuilder,
    $$SyncMetaTableUpdateCompanionBuilder,
    (SyncMetaData, BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaData>),
    SyncMetaData,
    PrefetchHooks Function()> {
  $$SyncMetaTableTableManager(_$AppDatabase db, $SyncMetaTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> entity = const Value.absent(),
            Value<DateTime> lastSyncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncMetaCompanion(
            entity: entity,
            lastSyncedAt: lastSyncedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String entity,
            required DateTime lastSyncedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncMetaCompanion.insert(
            entity: entity,
            lastSyncedAt: lastSyncedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncMetaTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SyncMetaTable,
    SyncMetaData,
    $$SyncMetaTableFilterComposer,
    $$SyncMetaTableOrderingComposer,
    $$SyncMetaTableAnnotationComposer,
    $$SyncMetaTableCreateCompanionBuilder,
    $$SyncMetaTableUpdateCompanionBuilder,
    (SyncMetaData, BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaData>),
    SyncMetaData,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CachedProductsTableTableManager get cachedProducts =>
      $$CachedProductsTableTableManager(_db, _db.cachedProducts);
  $$CachedCustomersTableTableManager get cachedCustomers =>
      $$CachedCustomersTableTableManager(_db, _db.cachedCustomers);
  $$PendingOperationsTableTableManager get pendingOperations =>
      $$PendingOperationsTableTableManager(_db, _db.pendingOperations);
  $$SyncMetaTableTableManager get syncMeta =>
      $$SyncMetaTableTableManager(_db, _db.syncMeta);
}
