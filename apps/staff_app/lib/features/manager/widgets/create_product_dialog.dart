import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import 'package:uuid/uuid.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';

class CreateProductDialog extends ConsumerStatefulWidget {
  const CreateProductDialog({super.key});

  @override
  ConsumerState<CreateProductDialog> createState() => _CreateProductDialogState();
}

class _CreateProductDialogState extends ConsumerState<CreateProductDialog> {
  final _nameArController = TextEditingController();
  final _nameFrController = TextEditingController();
  final _categoryController = TextEditingController(text: 'مواد غذائية (Alimentation)');
  final _barcodeController = TextEditingController();
  final _boxBarcodeController = TextEditingController();
  final _packSizeController = TextEditingController(text: '1');
  final _openingStockController = TextEditingController(text: '0');

  int _costCentimes = 0;
  int _retailCentimes = 0;
  int _wholesaleCentimes = 0;
  int _bulkCentimes = 0;
  String _selectedUnit = 'carton';
  bool _isSaving = false;

  @override
  void dispose() {
    _nameArController.dispose();
    _nameFrController.dispose();
    _categoryController.dispose();
    _barcodeController.dispose();
    _boxBarcodeController.dispose();
    _packSizeController.dispose();
    _openingStockController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final nameAr = _nameArController.text.trim();
    if (nameAr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('يرجى كتابة اسم المنتج بالعربية!'),
          backgroundColor: context.appColors.warning,
        ),
      );
      return;
    }

    final nameFr = _nameFrController.text.trim().isNotEmpty ? _nameFrController.text.trim() : nameAr;
    final category = _categoryController.text.trim().isNotEmpty ? _categoryController.text.trim() : 'عام';
    final packSize = int.tryParse(_packSizeController.text) ?? 1;
    final openingStock = int.tryParse(_openingStockController.text) ?? 0;

    setState(() => _isSaving = true);

    try {
      final productId = const Uuid().v4();
      final barcodes = <String>[];
      if (_barcodeController.text.trim().isNotEmpty) barcodes.add(_barcodeController.text.trim());
      if (_boxBarcodeController.text.trim().isNotEmpty) barcodes.add(_boxBarcodeController.text.trim());

      final priceTiers = <ProductPriceTier>[
        ProductPriceTier(
          id: const Uuid().v4(),
          tier: PriceTier.retail,
          minQty: 1,
          priceCentimes: _retailCentimes > 0 ? _retailCentimes : _costCentimes,
        ),
        ProductPriceTier(
          id: const Uuid().v4(),
          tier: PriceTier.wholesale,
          minQty: packSize,
          priceCentimes: _wholesaleCentimes > 0 ? _wholesaleCentimes : _costCentimes,
        ),
        ProductPriceTier(
          id: const Uuid().v4(),
          tier: PriceTier.bulk,
          minQty: packSize * 5,
          priceCentimes: _bulkCentimes > 0 ? _bulkCentimes : (_wholesaleCentimes > 0 ? _wholesaleCentimes : _costCentimes),
        ),
      ];

      final product = Product(
        id: productId,
        nameAr: nameAr,
        nameFr: nameFr,
        category: category,
        unit: _selectedUnit,
        packSize: packSize,
        costCentimes: _costCentimes,
        barcodes: barcodes,
        priceTiers: priceTiers,
        active: true,
      );

      final authUser = ref.read(authStateProvider);
      final repo = ref.read(productRepositoryProvider);
      await repo.saveProduct(product, initialOpeningStock: openingStock, userId: authUser?.id);

      if (!mounted) return;
      Navigator.pop(context, product);
    } catch (e) {
      debugPrint('Error saving product: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل حفظ المنتج: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('إضافة منتج جديد للمتجر (Nouveau Produit)'),
      content: SingleChildScrollView(
        child: ContentConstrainedBox.form(
          maxWidth: 580,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Names
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameArController,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'اسم المنتج بالعربية *',
                        hintText: 'مثال: زيت المائدة 5 لتر',
                        prefixIcon: Icon(Icons.shopping_bag_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: _nameFrController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'الاسم بالفرنسية',
                        hintText: 'Ex: Huile 5L',
                        prefixIcon: Icon(Icons.translate),
                      ),
                    ),
                  ),
                ],
              ),
              AppSpacing.gapMd,

              // Category & Unit
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _categoryController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'الفئة / التصنيف *',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedUnit,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'نوع الوحدة'),
                      items: const [
                        DropdownMenuItem(value: 'carton', child: Text('كرتون (Carton)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'pack', child: Text('طرد (Pack)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'box', child: Text('علبة (Boîte)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'piece', child: Text('قطعة (Pièce)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'kg', child: Text('كغ (Kg)', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedUnit = val);
                      },
                    ),
                  ),
                ],
              ),
              AppSpacing.gapMd,

              // Pack Size & Barcodes
              Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _packSizeController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'قطع/طرد',
                        hintText: '1',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: _barcodeController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'باركود القطعة',
                        prefixIcon: Icon(Icons.qr_code_scanner),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: _boxBarcodeController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'باركود الكرتون',
                        prefixIcon: Icon(Icons.qr_code_2),
                      ),
                    ),
                  ),
                ],
              ),
              AppSpacing.gapLg,
              const Divider(),
              AppSpacing.gapSm,
              Text(
                'التكلفة وأسعار البيع بالدينار الجزائري (DZD):',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              AppSpacing.gapMd,

              // Cost & Retail Price
              Row(
                children: [
                  Expanded(
                    child: MoneyField(
                      initialCentimes: _costCentimes,
                      labelText: 'سعر التكلفة (دج) *',
                      onChanged: (val) => _costCentimes = val,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: MoneyField(
                      initialCentimes: _retailCentimes,
                      labelText: 'سعر التجزئة (دج) *',
                      onChanged: (val) => _retailCentimes = val,
                    ),
                  ),
                ],
              ),
              AppSpacing.gapMd,

              // Wholesale & Bulk Price
              Row(
                children: [
                  Expanded(
                    child: MoneyField(
                      initialCentimes: _wholesaleCentimes,
                      labelText: 'سعر الجملة (دج) *',
                      onChanged: (val) => _wholesaleCentimes = val,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: MoneyField(
                      initialCentimes: _bulkCentimes,
                      labelText: 'سعر الكميات (Bulk) دج',
                      onChanged: (val) => _bulkCentimes = val,
                    ),
                  ),
                ],
              ),
              AppSpacing.gapMd,

              // Opening Stock
              TextField(
                controller: _openingStockController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'المخزون الافتتاحي الأولي المتوفر حالياً (الوحدات/الكراتين)',
                  prefixIcon: Icon(Icons.warehouse_outlined),
                  helperText: 'إذا كانت البضاعة متوفرة في المحل حالياً أدخل الكمية لتدوينها في دفتر المخزون',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _isSaving ? null : _handleSave,
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ المنتج في الكتالوج'),
        ),
      ],
    );
  }
}
