import 'dart:math';
import 'package:core/constants/dzd_formatter.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:data/data.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';

/// Supported unit definitions with localized labels and default packing factors.
enum ProductUnitType {
  carton('carton', 'كرتون (Carton)', Icons.inventory_2_outlined, true),
  pack('pack', 'طرد (Pack)', Icons.all_inbox_outlined, true),
  box('box', 'علبة (Boîte)', Icons.inbox_outlined, true),
  piece('piece', 'قطعة (Pièce)', Icons.widgets_outlined, false),
  kg('kg', 'كغ (Kg)', Icons.scale_outlined, false),
  g('g', 'غرام (g)', Icons.grain_outlined, false),
  l('l', 'لتر (L)', Icons.local_drink_outlined, false);

  final String code;
  final String label;
  final IconData icon;
  final bool isPackage;

  const ProductUnitType(this.code, this.label, this.icon, this.isPackage);

  static ProductUnitType fromCode(String code) {
    return ProductUnitType.values.firstWhere(
      (u) => u.code == code,
      orElse: () => ProductUnitType.piece,
    );
  }
}

/// Mode for pricing inputs when handling package units (Carton, Pack, Box).
enum PricingInputMode {
  unit, // Prices entered / viewed per individual piece
  pack, // Prices entered / viewed per package/carton
}

/// Curated FMCG categories with corresponding icons and bilingual labels.
const List<Map<String, dynamic>> _kCuratedCategories = [
  {'label': 'مواد غذائية (Alimentation)', 'icon': Icons.kitchen_rounded},
  {'label': 'مشروبات وعصائر (Boissons & Jus)', 'icon': Icons.local_drink_rounded},
  {'label': 'ألبان وأجبان (Produits Laitiers)', 'icon': Icons.egg_alt_rounded},
  {'label': 'حلويات وبسكويت (Confiserie)', 'icon': Icons.cookie_rounded},
  {'label': 'معلبات ومصبرات (Conserves)', 'icon': Icons.soup_kitchen_rounded},
  {'label': 'مواد التنظيف (Entretien)', 'icon': Icons.cleaning_services_rounded},
  {'label': 'عناية شخصية (Hygiène & Soins)', 'icon': Icons.soap_rounded},
  {'label': 'توابل وبقوليات (Épices & Légumes)', 'icon': Icons.grain_rounded},
  {'label': 'خضر وفواكه (Fruits & Légumes)', 'icon': Icons.eco_rounded},
  {'label': 'لحوم ومجمدات (Viandes & Surgelés)', 'icon': Icons.set_meal_rounded},
  {'label': 'بلاستيك وتغليف (Emballage)', 'icon': Icons.takeout_dining_rounded},
  {'label': 'عام (Divers)', 'icon': Icons.category_rounded},
];

/// Dialog for creating a new product or editing an existing one.
///
/// Features:
/// - Bidirectional pricing (Unit price ⟷ Pack price with live conversions)
/// - KG / Weight price breakdowns (100g, 250g, 500g, 1g)
/// - Real-time profit margins and below-cost warning system
/// - Quick margin presets (+10%, +15%, +20%, +25%, +30%)
/// - Category auto-suggestion and dynamic category picker from database
/// - Instant EAN-13 barcode generation for unbarcoded/unpackaged products
/// - Image picker with web/mobile fallback and existing image preview
/// - Opening inventory conversion between package units and base stock count
class CreateProductDialog extends ConsumerStatefulWidget {
  final Product? existing;

  const CreateProductDialog({super.key, this.existing});

  @override
  ConsumerState<CreateProductDialog> createState() =>
      _CreateProductDialogState();
}

class _CreateProductDialogState extends ConsumerState<CreateProductDialog>
    with SingleTickerProviderStateMixin {
  // ── Controllers ──────────────────────────────────────────────────────────
  final _nameArController = TextEditingController();
  final _nameFrController = TextEditingController();
  final _categoryController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _boxBarcodeController = TextEditingController();
  final _packSizeController = TextEditingController(text: '1');
  final _openingStockPackagesController = TextEditingController(text: '0');

  // ── State ─────────────────────────────────────────────────────────────────
  ProductUnitType _unitType = ProductUnitType.carton;
  PricingInputMode _pricingInputMode = PricingInputMode.unit;

  // Stored source of truth: Prices in CENTIMES per BASE UNIT (Piece, Kg, Litre)
  int _unitCostCentimes = 0;
  int _unitRetailCentimes = 0;
  int _unitWholesaleCentimes = 0;
  int _unitBulkCentimes = 0;

  bool _isSaving = false;
  Uint8List? _selectedImageBytes;
  bool _removeExistingPhoto = false;
  bool _active = true;

  // ── Validation flags ──────────────────────────────────────────────────────
  bool _touchedNameAr = false;
  bool _touchedCost = false;
  bool _touchedRetail = false;
  bool _touchedWholesale = false;
  bool _touchedPackSize = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  bool get _isEditMode => widget.existing != null;

  int get _packSize {
    final ps = int.tryParse(_packSizeController.text) ?? 1;
    return ps > 0 ? ps : 1;
  }

  bool get _isPackType => _unitType.isPackage;
  bool get _isKg => _unitType == ProductUnitType.kg;

  // Derived Pack Prices
  int get _packCostCentimes => _unitCostCentimes * _packSize;
  int get _packRetailCentimes => _unitRetailCentimes * _packSize;
  int get _packWholesaleCentimes => _unitWholesaleCentimes * _packSize;
  int get _packBulkCentimes => _unitBulkCentimes * _packSize;

  // Display prices based on selected input mode
  int get _displayCostCentimes =>
      (_isPackType && _pricingInputMode == PricingInputMode.pack)
          ? _packCostCentimes
          : _unitCostCentimes;

  int get _displayRetailCentimes =>
      (_isPackType && _pricingInputMode == PricingInputMode.pack)
          ? _packRetailCentimes
          : _unitRetailCentimes;

  int get _displayWholesaleCentimes =>
      (_isPackType && _pricingInputMode == PricingInputMode.pack)
          ? _packWholesaleCentimes
          : _unitWholesaleCentimes;

  int get _displayBulkCentimes =>
      (_isPackType && _pricingInputMode == PricingInputMode.pack)
          ? _packBulkCentimes
          : _unitBulkCentimes;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    // Default category for new products
    _categoryController.text = 'مواد غذائية (Alimentation)';

    // Pre-fill in edit mode
    final p = widget.existing;
    if (p != null) {
      _nameArController.text = p.nameAr;
      _nameFrController.text = p.nameFr;
      _categoryController.text = p.category;
      _packSizeController.text = p.packSize.toString();
      _unitType = ProductUnitType.fromCode(p.unit);
      _unitCostCentimes = p.costCentimes;

      // Extract tiers directly by tier enum to avoid fallback bug
      final retailTier =
          p.prices.where((t) => t.tier == PriceTier.retail).firstOrNull;
      final wholesaleTier =
          p.prices.where((t) => t.tier == PriceTier.wholesale).firstOrNull;
      final bulkTier =
          p.prices.where((t) => t.tier == PriceTier.bulk).firstOrNull;

      _unitRetailCentimes = retailTier?.priceCentimes ??
          p.getPriceForQuantity(PriceTier.retail, 1);
      _unitWholesaleCentimes = wholesaleTier?.priceCentimes ??
          p.getPriceForQuantity(PriceTier.wholesale, p.packSize);
      _unitBulkCentimes = bulkTier?.priceCentimes ??
          p.getPriceForQuantity(PriceTier.bulk, p.packSize * 5);

      _active = p.active;
      if (p.barcodes.isNotEmpty) {
        _barcodeController.text = p.barcodes.first;
      }
      if (p.barcodes.length > 1) {
        _boxBarcodeController.text = p.barcodes[1];
      }

      // Convert current available stock into packages for display
      final packages = p.packSize > 0
          ? (p.availableQty / p.packSize).floor()
          : p.availableQty;
      _openingStockPackagesController.text = packages.toString();
    }
  }

  @override
  void dispose() {
    _nameArController.dispose();
    _nameFrController.dispose();
    _categoryController.dispose();
    _barcodeController.dispose();
    _boxBarcodeController.dispose();
    _packSizeController.dispose();
    _openingStockPackagesController.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Price Auto-Suggest & Margins ──────────────────────────────────────────

  int get _retailMarginPercent {
    if (_unitCostCentimes <= 0 || _unitRetailCentimes <= 0) return 0;
    return (((_unitRetailCentimes - _unitCostCentimes) / _unitCostCentimes) *
            100)
        .round();
  }

  int get _wholesaleMarginPercent {
    if (_unitCostCentimes <= 0 || _unitWholesaleCentimes <= 0) return 0;
    return (((_unitWholesaleCentimes - _unitCostCentimes) /
                _unitCostCentimes) *
            100)
        .round();
  }

  void _autoSuggestPrices(int newUnitCost) {
    if (newUnitCost <= 0) return;
    setState(() {
      if (_unitRetailCentimes == 0) {
        _unitRetailCentimes = (newUnitCost * 1.25).round();
      }
      if (_unitWholesaleCentimes == 0) {
        _unitWholesaleCentimes = (newUnitCost * 1.12).round();
      }
      if (_unitBulkCentimes == 0) {
        _unitBulkCentimes = (newUnitCost * 1.07).round();
      }
    });
  }

  void _applyMarginPreset(double percent) {
    if (_unitCostCentimes <= 0) return;
    setState(() {
      _touchedRetail = true;
      _touchedWholesale = true;
      _unitRetailCentimes =
          (_unitCostCentimes * (1 + (percent / 100))).round();
      _unitWholesaleCentimes =
          (_unitCostCentimes * (1 + ((percent * 0.55) / 100))).round();
      _unitBulkCentimes =
          (_unitCostCentimes * (1 + ((percent * 0.35) / 100))).round();
    });
  }

  // ── Price Input Handlers (Bidirectional Conversion) ───────────────────────

  void _handleCostChanged(int inputCentimes) {
    setState(() {
      _touchedCost = true;
      if (_isPackType && _pricingInputMode == PricingInputMode.pack) {
        _unitCostCentimes =
            _packSize > 0 ? (inputCentimes / _packSize).round() : inputCentimes;
      } else {
        _unitCostCentimes = inputCentimes;
      }
    });
    _autoSuggestPrices(_unitCostCentimes);
  }

  void _handleRetailChanged(int inputCentimes) {
    setState(() {
      _touchedRetail = true;
      if (_isPackType && _pricingInputMode == PricingInputMode.pack) {
        _unitRetailCentimes =
            _packSize > 0 ? (inputCentimes / _packSize).round() : inputCentimes;
      } else {
        _unitRetailCentimes = inputCentimes;
      }
    });
  }

  void _handleWholesaleChanged(int inputCentimes) {
    setState(() {
      _touchedWholesale = true;
      if (_isPackType && _pricingInputMode == PricingInputMode.pack) {
        _unitWholesaleCentimes =
            _packSize > 0 ? (inputCentimes / _packSize).round() : inputCentimes;
      } else {
        _unitWholesaleCentimes = inputCentimes;
      }
    });
  }

  void _handleBulkChanged(int inputCentimes) {
    setState(() {
      if (_isPackType && _pricingInputMode == PricingInputMode.pack) {
        _unitBulkCentimes =
            _packSize > 0 ? (inputCentimes / _packSize).round() : inputCentimes;
      } else {
        _unitBulkCentimes = inputCentimes;
      }
    });
  }

  // ── Barcode Generator (EAN-13) ────────────────────────────────────────────

  void _generateBarcode({required bool isBox}) {
    final random = Random();
    // Prefix 200 for pieces, 201 for boxes (standard in-store private prefixes)
    final prefix = isBox ? '201' : '200';
    final sb = StringBuffer(prefix);
    while (sb.length < 12) {
      sb.write(random.nextInt(10));
    }
    final code12 = sb.toString();

    // Calculate EAN-13 modulo-10 checksum
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      final digit = int.parse(code12[i]);
      sum += (i % 2 == 0) ? digit : digit * 3;
    }
    final checkDigit = (10 - (sum % 10)) % 10;
    final barcode = '$code12$checkDigit';

    setState(() {
      if (isBox) {
        _boxBarcodeController.text = barcode;
      } else {
        _barcodeController.text = barcode;
      }
    });
  }

  // ── Image Picking ─────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 82,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() {
        _selectedImageBytes = bytes;
        _removeExistingPhoto = false;
      });
    } catch (e) {
      if (mounted) {
        _showError('تعذر اختيار الصورة: $e');
      }
    }
  }

  void _showImageSourceSheet() {
    final supportsCamera = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    if (!supportsCamera) {
      _pickImage(ImageSource.gallery);
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: AppSpacing.sm),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: AppRadius.pillAll,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('اختيار من المعرض'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('التقاط صورة بالكاميرا'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  // ── Form Validation ───────────────────────────────────────────────────────

  bool get _isFormValid {
    if (_nameArController.text.trim().isEmpty) return false;
    if (_unitCostCentimes <= 0) return false;
    if (_unitRetailCentimes <= 0) return false;
    if (_unitWholesaleCentimes <= 0) return false;
    if (_isPackType) {
      final ps = int.tryParse(_packSizeController.text) ?? 0;
      if (ps <= 0) return false;
    }
    return true;
  }

  String? get _nameArError {
    if (!_touchedNameAr) return null;
    if (_nameArController.text.trim().isEmpty) return 'الاسم العربي مطلوب *';
    return null;
  }

  // ── Save Operation ────────────────────────────────────────────────────────

  Future<void> _handleSave() async {
    setState(() {
      _touchedNameAr = true;
      _touchedCost = true;
      _touchedRetail = true;
      _touchedWholesale = true;
      _touchedPackSize = true;
    });

    if (!_isFormValid) return;

    setState(() => _isSaving = true);

    try {
      final productId = widget.existing?.id ?? const Uuid().v4();
      String? photoUrl =
          _removeExistingPhoto ? null : widget.existing?.photoUrl;

      // Upload newly picked photo if present
      if (_selectedImageBytes != null) {
        try {
          final client = ref.read(supabaseClientProvider);
          final path = 'products/$productId.jpg';
          await client.storage.from('product-images').uploadBinary(
                path,
                _selectedImageBytes!,
                fileOptions:
                    const FileOptions(upsert: true, contentType: 'image/jpeg'),
              );
          photoUrl =
              '${client.storage.from('product-images').getPublicUrl(path)}'
              '?v=${DateTime.now().millisecondsSinceEpoch}';
        } catch (_) {
          if (mounted) {
            _showWarning('تعذر رفع الصورة — سيتم الحفظ بدون تحديث الصورة');
          }
        }
      }

      final nameAr = _nameArController.text.trim();
      final nameFr = _nameFrController.text.trim().isNotEmpty
          ? _nameFrController.text.trim()
          : nameAr;
      final category = _categoryController.text.trim().isNotEmpty
          ? _categoryController.text.trim()
          : 'عام';
      final packSize = _isPackType ? _packSize : 1;

      // Calculate total pieces for opening stock
      final enteredPackages =
          int.tryParse(_openingStockPackagesController.text) ?? 0;
      final openingStockPieces = _isPackType
          ? (enteredPackages * packSize)
          : enteredPackages;

      final barcodes = <String>[
        if (_barcodeController.text.trim().isNotEmpty)
          _barcodeController.text.trim(),
        if (_boxBarcodeController.text.trim().isNotEmpty &&
            _boxBarcodeController.text.trim() !=
                _barcodeController.text.trim())
          _boxBarcodeController.text.trim(),
      ];

      // Re-use existing price tier IDs when updating
      final existingRetail = widget.existing?.prices
          .where((t) => t.tier == PriceTier.retail)
          .firstOrNull;
      final existingWholesale = widget.existing?.prices
          .where((t) => t.tier == PriceTier.wholesale)
          .firstOrNull;
      final existingBulk = widget.existing?.prices
          .where((t) => t.tier == PriceTier.bulk)
          .firstOrNull;

      final priceTiers = <ProductPriceTier>[
        ProductPriceTier(
          id: existingRetail?.id ?? const Uuid().v4(),
          tier: PriceTier.retail,
          minQty: 1,
          priceCentimes: _unitRetailCentimes,
        ),
        ProductPriceTier(
          id: existingWholesale?.id ?? const Uuid().v4(),
          tier: PriceTier.wholesale,
          minQty: packSize,
          priceCentimes: _unitWholesaleCentimes,
        ),
        ProductPriceTier(
          id: existingBulk?.id ?? const Uuid().v4(),
          tier: PriceTier.bulk,
          minQty: packSize * 5,
          priceCentimes: _unitBulkCentimes > 0
              ? _unitBulkCentimes
              : _unitWholesaleCentimes,
        ),
      ];

      final product = Product(
        id: productId,
        nameAr: nameAr,
        nameFr: nameFr,
        category: category,
        unit: _unitType.code,
        packSize: packSize,
        photoUrl: photoUrl,
        costCentimes: _unitCostCentimes,
        barcodes: barcodes,
        priceTiers: priceTiers,
        active: _active,
      );

      final authUser = ref.read(authStateProvider);
      final repo = ref.read(productRepositoryProvider);

      await repo.saveProduct(
        product,
        initialOpeningStock: _isEditMode ? 0 : openingStockPieces,
        userId: authUser?.id,
      );

      if (!mounted) return;
      Navigator.pop(context, product);
    } catch (e) {
      if (!mounted) return;
      _showError('فشل حفظ المنتج: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Theme.of(context).colorScheme.error,
    ));
  }

  void _showWarning(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: context.appColors.warning,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final isDark = theme.brightness == Brightness.dark;
    final wc = context.windowClass;
    final isWide = wc != WindowClass.compact && wc != WindowClass.medium;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Dialog(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        insetPadding: EdgeInsets.symmetric(
          horizontal: isWide ? 40 : 12,
          vertical: 20,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 920),
          child: Column(
            children: [
              _buildHeader(theme, isDark),
              Expanded(child: _buildBody(theme, colors, isDark, isWide)),
              _buildFooter(theme, colors, isDark),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.md, AppSpacing.md),
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                colors: [Color(0xFF1C1810), Color(0xFF141210)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFFFBF6E8), Color(0xFFFAF7F0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppRadius.lg),
          topRight: Radius.circular(AppRadius.lg),
        ),
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.25),
          ),
        ),
      ),
      child: Row(
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppGradients.gold,
              borderRadius: AppRadius.smAll,
              boxShadow: [AppShadows.goldGlowSm],
            ),
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.inventory_2_rounded,
                  size: 20, color: Color(0xFF1A1400)),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEditMode ? 'تعديل بيانات المنتج' : 'إضافة منتج جديد للكتالوج',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  _isEditMode
                      ? widget.existing!.nameAr
                      : 'أدخل تفاصيل التعبئة، الفئة، وأسعار التجزئة والجملة بدقة',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_isEditMode) ...[
            const SizedBox(width: AppSpacing.sm),
            _ActiveToggleChip(
              active: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
            style: IconButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────

  Widget _buildBody(
      ThemeData theme, dynamic colors, bool isDark, bool isWide) {
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Section 1: Identification & Names ─────────────────────────
          const SectionHeader(title: 'هوية المنتج والبيانات الأساسية'),
          AppSpacing.gapMd,

          isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildImagePicker(isDark),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: _buildNameFields()),
                  ],
                )
              : Column(
                  children: [
                    _buildImagePicker(isDark),
                    AppSpacing.gapMd,
                    _buildNameFields(),
                  ],
                ),
          AppSpacing.gapLg,

          // ── Section 2: Category Selection ─────────────────────────────
          _buildCategorySection(isDark),
          AppSpacing.gapLg,

          // ── Section 3: Packaging & Unit Configuration ─────────────────
          _buildUnitAndPackagingSection(isDark, isWide),
          AppSpacing.gapLg,

          // ── Section 4: Barcodes ───────────────────────────────────────
          _buildBarcodesSection(isWide),
          AppSpacing.gapXl,
          const GoldDivider(),
          AppSpacing.gapMd,

          // ── Section 5: Pricing Engine ─────────────────────────────────
          _buildPricingSection(theme, colors, isDark, isWide),

          // ── Section 6: Opening Inventory (Create Mode Only) ───────────
          if (!_isEditMode) ...[
            AppSpacing.gapXl,
            const GoldDivider(),
            AppSpacing.gapMd,
            _buildOpeningInventorySection(),
          ],
        ],
      ),
    );
  }

  // ── Section Builders ──────────────────────────────────────────────────────

  Widget _buildNameFields() {
    return Column(
      children: [
        TextField(
          controller: _nameArController,
          autofocus: !_isEditMode,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() => _touchedNameAr = true),
          decoration: InputDecoration(
            labelText: 'اسم المنتج بالعربية *',
            hintText: 'مثال: زيت المائدة سيم 5 لتر',
            prefixIcon: const Icon(Icons.shopping_bag_outlined),
            errorText: _nameArError,
          ),
        ),
        AppSpacing.gapMd,
        TextField(
          controller: _nameFrController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'الاسم بالفرنسية (Nom en français)',
            hintText: 'Ex: Huile de table Sim 5L',
            prefixIcon: Icon(Icons.translate_rounded),
          ),
        ),
      ],
    );
  }

  Widget _buildCategorySection(bool isDark) {
    final categoriesAsync = ref.watch(posCategoryListProvider);
    final dbCategories = categoriesAsync.asData?.value ?? [];

    // Merge database categories with curated list
    final allCategoryNames = <String>{
      ..._kCuratedCategories.map((c) => c['label'] as String),
      ...dbCategories,
    }.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.category_outlined,
                size: 18, color: Color(0xFFD4AF37)),
            SizedBox(width: AppSpacing.xs),
            Text(
              'الفئة / التصنيف *',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
        AppSpacing.gapSm,

        // Autocomplete Category Field
        Autocomplete<String>(
          initialValue: TextEditingValue(text: _categoryController.text),
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) {
              return allCategoryNames.take(8);
            }
            final q = textEditingValue.text.toLowerCase();
            return allCategoryNames.where((c) => c.toLowerCase().contains(q));
          },
          onSelected: (String selection) {
            setState(() {
              _categoryController.text = selection;
            });
          },
          fieldViewBuilder:
              (context, textEditingController, focusNode, onFieldSubmitted) {
            // Keep controllers synced
            if (textEditingController.text != _categoryController.text) {
              textEditingController.text = _categoryController.text;
            }
            return TextField(
              controller: textEditingController,
              focusNode: focusNode,
              textInputAction: TextInputAction.next,
              onChanged: (v) => _categoryController.text = v,
              decoration: InputDecoration(
                hintText: 'اختر أو اكتب فئة المنتج...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () {
                    textEditingController.clear();
                    _categoryController.clear();
                    setState(() {});
                  },
                ),
              ),
            );
          },
        ),
        AppSpacing.gapSm,

        // Quick Select Category Chips
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _kCuratedCategories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final cat = _kCuratedCategories[i];
              final label = cat['label'] as String;
              final icon = cat['icon'] as IconData;
              final isSelected = _categoryController.text == label;

              return FilterChip(
                label: Text(label.split(' (').first),
                avatar: Icon(icon,
                    size: 14,
                    color: isSelected
                        ? const Color(0xFF1A1400)
                        : const Color(0xFFD4AF37)),
                selected: isSelected,
                selectedColor: const Color(0xFFD4AF37),
                checkmarkColor: const Color(0xFF1A1400),
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? const Color(0xFF1A1400)
                      : (isDark
                          ? const Color(0xFFE8DDB0)
                          : const Color(0xFF4A3B10)),
                ),
                backgroundColor: isDark
                    ? const Color(0xFF1E1A14)
                    : const Color(0xFFF9F6EE),
                side: BorderSide(
                  color: isSelected
                      ? const Color(0xFFD4AF37)
                      : const Color(0xFFD4AF37).withValues(alpha: 0.22),
                ),
                onSelected: (_) {
                  setState(() {
                    _categoryController.text = label;
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUnitAndPackagingSection(bool isDark, bool isWide) {
    final unitDropdown = DropdownButtonFormField<ProductUnitType>(
      initialValue: _unitType,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'نوع الوحدة والقياس',
        prefixIcon: Icon(Icons.straighten_rounded),
      ),
      items: ProductUnitType.values.map((u) {
        return DropdownMenuItem(
          value: u,
          child: Row(
            children: [
              Icon(u.icon, size: 16, color: const Color(0xFFD4AF37)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(u.label, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (val) {
        if (val != null) {
          setState(() {
            _unitType = val;
            if (!_unitType.isPackage) {
              _pricingInputMode = PricingInputMode.unit;
            }
          });
        }
      },
    );

    final packSizeField = TextField(
      controller: _packSizeController,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textInputAction: TextInputAction.next,
      enabled: _isPackType,
      onChanged: (_) => setState(() => _touchedPackSize = true),
      decoration: InputDecoration(
        labelText: 'عدد القطع في الطرد *',
        hintText: '12',
        prefixIcon: const Icon(Icons.format_list_numbered_rounded),
        helperText: _isPackType ? 'عدد الوحدات الفردية داخل العلبة/الكرتون' : null,
        errorText: _isPackType && _touchedPackSize && _packSize <= 0
            ? 'مطلوب (1 أو أكثر)'
            : null,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: unitDropdown),
                  if (_isPackType) ...[
                    const SizedBox(width: AppSpacing.md),
                    Expanded(flex: 2, child: packSizeField),
                  ],
                ],
              )
            : Column(
                children: [
                  unitDropdown,
                  if (_isPackType) ...[
                    AppSpacing.gapMd,
                    packSizeField,
                  ],
                ],
              ),
      ],
    );
  }

  Widget _buildBarcodesSection(bool isWide) {
    final pieceBarcodeField = TextField(
      controller: _barcodeController,
      textInputAction: TextInputAction.next,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d\-A-Za-z]')),
      ],
      decoration: InputDecoration(
        labelText: _isPackType ? 'باركود القطعة الفردية' : 'باركود المنتج',
        hintText: 'امسح أو اكتب الباركود...',
        prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
        suffixIcon: IconButton(
          icon: const Icon(Icons.auto_awesome_rounded, size: 18),
          tooltip: 'توليد باركود تلقائي EAN-13',
          onPressed: () => _generateBarcode(isBox: false),
        ),
      ),
    );

    final boxBarcodeField = TextField(
      controller: _boxBarcodeController,
      textInputAction: TextInputAction.next,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d\-A-Za-z]')),
      ],
      decoration: InputDecoration(
        labelText: 'باركود الكرتون / الطرد (Colis)',
        hintText: 'امسح باركود الصندوق الخارجي...',
        prefixIcon: const Icon(Icons.qr_code_2_rounded),
        suffixIcon: IconButton(
          icon: const Icon(Icons.auto_awesome_rounded, size: 18),
          tooltip: 'توليد باركود للكرتون',
          onPressed: () => _generateBarcode(isBox: true),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'الباركود والترميز'),
        AppSpacing.gapSm,
        isWide
            ? Row(
                children: [
                  Expanded(child: pieceBarcodeField),
                  if (_isPackType) ...[
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: boxBarcodeField),
                  ],
                ],
              )
            : Column(
                children: [
                  pieceBarcodeField,
                  if (_isPackType) ...[
                    AppSpacing.gapMd,
                    boxBarcodeField,
                  ],
                ],
              ),
      ],
    );
  }

  Widget _buildPricingSection(
      ThemeData theme, dynamic colors, bool isDark, bool isWide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SectionHeader(
                title: _isKg
                    ? 'التسعير بالكيلوغرام (دج / كغ)'
                    : 'التكلفة وأسعار البيع (دج)',
              ),
            ),
            // Mode selector for package types: Enter by unit vs by pack
            if (_isPackType && _packSize > 1)
              _buildPricingModeSwitch(isDark),
          ],
        ),
        AppSpacing.gapSm,

        // Margin presets & profit alert banner
        _buildMarginBanner(colors),
        AppSpacing.gapSm,

        // Margin preset quick buttons
        _buildMarginPresetButtons(isDark),
        AppSpacing.gapMd,

        // 4 Core price fields
        _buildPricingFields(isWide),

        // Contextual breakdown card (Weight breakdown for KG, Pack breakdown for Carton)
        _buildContextualBreakdownCard(isDark),
      ],
    );
  }

  Widget _buildPricingModeSwitch(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1A14) : const Color(0xFFF3ECE0),
        borderRadius: AppRadius.pillAll,
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeChoicePill(
            label: 'بالقطعة',
            selected: _pricingInputMode == PricingInputMode.unit,
            onTap: () =>
                setState(() => _pricingInputMode = PricingInputMode.unit),
          ),
          _ModeChoicePill(
            label: 'بالكرتون (×$_packSize)',
            selected: _pricingInputMode == PricingInputMode.pack,
            onTap: () =>
                setState(() => _pricingInputMode = PricingInputMode.pack),
          ),
        ],
      ),
    );
  }

  Widget _buildMarginPresetButtons(bool isDark) {
    const presets = [10.0, 15.0, 20.0, 25.0, 30.0];
    return Row(
      children: [
        Text(
          'نسب هامش سريعة:',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: presets.map((p) {
                return Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: InkWell(
                    borderRadius: AppRadius.pillAll,
                    onTap: () => _applyMarginPreset(p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF221E16)
                            : const Color(0xFFFAF6EE),
                        borderRadius: AppRadius.pillAll,
                        border: Border.all(
                          color: const Color(0xFFD4AF37)
                              .withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        '+${p.toInt()}%',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD4AF37),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMarginBanner(dynamic colors) {
    if (_unitCostCentimes <= 0 || _unitRetailCentimes <= 0) {
      return const SizedBox.shrink();
    }

    final isNegative = _retailMarginPercent < 0 || _wholesaleMarginPercent < 0;
    final isLow = _retailMarginPercent < 10;
    final isInverted = _unitWholesaleCentimes > _unitRetailCentimes;

    final retailProfitCentimes = _unitRetailCentimes - _unitCostCentimes;
    final wholesaleProfitCentimes =
        _unitWholesaleCentimes - _unitCostCentimes;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
      decoration: BoxDecoration(
        color: isNegative || isInverted
            ? colors.errorContainer
            : isLow
                ? colors.warningContainer
                : colors.successContainer,
        borderRadius: AppRadius.smAll,
        border: Border.all(
          color: isNegative || isInverted
              ? colors.error.withValues(alpha: 0.35)
              : isLow
                  ? colors.warning.withValues(alpha: 0.35)
                  : colors.success.withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isNegative || isInverted
                    ? Icons.warning_amber_rounded
                    : Icons.trending_up_rounded,
                size: 16,
                color: isNegative || isInverted
                    ? colors.onErrorContainer
                    : isLow
                        ? colors.onWarningContainer
                        : colors.onSuccessContainer,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  isInverted
                      ? '⚠ تنبيه: سعر الجملة أعلى من سعر التجزئة!'
                      : isNegative
                          ? '⚠ تنبيه: أنت تبيع بأقل من سعر التكلفة!'
                          : 'هامش ربح التجزئة: $_retailMarginPercent% (+${DzdFormatter.formatCentimes(retailProfitCentimes)}/وحدة)  •  '
                              'هامش الجملة: $_wholesaleMarginPercent% (+${DzdFormatter.formatCentimes(wholesaleProfitCentimes)}/وحدة)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isNegative || isInverted
                        ? colors.onErrorContainer
                        : isLow
                            ? colors.onWarningContainer
                            : colors.onSuccessContainer,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPricingFields(bool isWide) {
    final modeLabel =
        (_isPackType && _pricingInputMode == PricingInputMode.pack)
            ? 'للكرتون'
            : _isKg
                ? 'لكل كغ'
                : 'للقطعة';

    final costField = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MoneyField(
          initialCentimes: _displayCostCentimes,
          labelText: 'سعر التكلفة ($modeLabel) *',
          validator: _touchedCost
              ? (v) => v <= 0 ? 'سعر التكلفة مطلوب' : null
              : null,
          onChanged: _handleCostChanged,
        ),
        if (_isPackType && _packSize > 1)
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 4),
            child: Text(
              _pricingInputMode == PricingInputMode.pack
                  ? 'يعادل: ${DzdFormatter.formatCentimes(_unitCostCentimes)} / قطعة'
                  : 'يعادل: ${DzdFormatter.formatCentimes(_packCostCentimes)} / كرتون',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );

    final retailField = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MoneyField(
          initialCentimes: _displayRetailCentimes,
          labelText: 'سعر التجزئة ($modeLabel) *',
          validator: _touchedRetail
              ? (v) {
                  if (v <= 0) return 'سعر التجزئة مطلوب';
                  if (_unitCostCentimes > 0 &&
                      _unitRetailCentimes < _unitCostCentimes) {
                    return 'أقل من سعر التكلفة!';
                  }
                  return null;
                }
              : null,
          onChanged: _handleRetailChanged,
        ),
        if (_isPackType && _packSize > 1)
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 4),
            child: Text(
              _pricingInputMode == PricingInputMode.pack
                  ? 'يعادل: ${DzdFormatter.formatCentimes(_unitRetailCentimes)} / قطعة'
                  : 'يعادل: ${DzdFormatter.formatCentimes(_packRetailCentimes)} / كرتون',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );

    final wholesaleField = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MoneyField(
          initialCentimes: _displayWholesaleCentimes,
          labelText: 'سعر الجملة ($modeLabel) *',
          validator: _touchedWholesale
              ? (v) => v <= 0 ? 'سعر الجملة مطلوب' : null
              : null,
          onChanged: _handleWholesaleChanged,
        ),
        if (_isPackType && _packSize > 1)
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 4),
            child: Text(
              _pricingInputMode == PricingInputMode.pack
                  ? 'يعادل: ${DzdFormatter.formatCentimes(_unitWholesaleCentimes)} / قطعة'
                  : 'يعادل: ${DzdFormatter.formatCentimes(_packWholesaleCentimes)} / كرتون',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );

    final bulkField = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MoneyField(
          initialCentimes: _displayBulkCentimes,
          labelText: 'سعر الكميات ($modeLabel)',
          onChanged: _handleBulkChanged,
        ),
        if (_isPackType && _packSize > 1)
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 4),
            child: Text(
              _pricingInputMode == PricingInputMode.pack
                  ? 'يعادل: ${DzdFormatter.formatCentimes(_unitBulkCentimes)} / قطعة'
                  : 'يعادل: ${DzdFormatter.formatCentimes(_packBulkCentimes)} / كرتون',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: costField),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: retailField),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: wholesaleField),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: bulkField),
        ],
      );
    }

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: costField),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: retailField),
          ],
        ),
        AppSpacing.gapMd,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: wholesaleField),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: bulkField),
          ],
        ),
      ],
    );
  }

  Widget _buildContextualBreakdownCard(bool isDark) {
    if (_isKg && _unitWholesaleCentimes > 0) {
      // Weight breakdown for KG
      final p500 = (_unitWholesaleCentimes / 2).round();
      final p250 = (_unitWholesaleCentimes / 4).round();
      final p100 = (_unitWholesaleCentimes / 10).round();
      final p1g = _unitWholesaleCentimes / 1000.0;

      return Container(
        margin: const EdgeInsets.only(top: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1B1812) : const Color(0xFFF9F5EC),
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.scale_rounded, size: 16, color: Color(0xFFD4AF37)),
                SizedBox(width: AppSpacing.xs),
                Text(
                  'جدول تفكيك أوزان البيع بالجملة (Détail au poids):',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _WeightPill(label: '1 كغ', price: _unitWholesaleCentimes),
                _WeightPill(label: '500 غ (نصف كغ)', price: p500),
                _WeightPill(label: '250 غ (رطل)', price: p250),
                _WeightPill(label: '100 غ', price: p100),
                _WeightPill(label: '1 غرام', dzdValue: p1g / 100.0),
              ],
            ),
          ],
        ),
      );
    }

    if (_isPackType && _packSize > 1 && _unitWholesaleCentimes > 0) {
      return Container(
        margin: const EdgeInsets.only(top: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1B1812) : const Color(0xFFF9F5EC),
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.calculate_outlined,
                size: 18, color: Color(0xFFD4AF37)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'ملخص الطرد: كرتون يحتوي على $_packSize قطعة  •  '
                'سعر الكرتون بالجملة: ${DzdFormatter.formatCentimes(_packWholesaleCentimes)}  '
                '(= ${DzdFormatter.formatCentimes(_unitWholesaleCentimes)} للقطعة)',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildOpeningInventorySection() {
    final packLabel = _isPackType
        ? 'عدد الكراتين / الطرود'
        : _isKg
            ? 'الكمية بالكيلوغرام (كغ)'
            : 'الكمية بالقطع';

    final helperText = _isPackType && _packSize > 1
        ? 'سيتم تسجيل '
            '${(int.tryParse(_openingStockPackagesController.text) ?? 0) * _packSize} '
            'قطعة في دفتر المخزون'
        : 'سيُسجَّل كحركة جرد افتتاحية في دفتر المخزون';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'المخزون الافتتاحي الأولي'),
        AppSpacing.gapSm,
        TextField(
          controller: _openingStockPackagesController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: '$packLabel بالمستودع',
            prefixIcon: const Icon(Icons.warehouse_outlined),
            suffixText: _unitType.label.split(' (').first,
            helperText: helperText,
          ),
        ),
      ],
    );
  }

  Widget _buildImagePicker(bool isDark) {
    final existingUrl = widget.existing?.photoUrl;
    final hasExistingPhoto =
        existingUrl != null && existingUrl.isNotEmpty && !_removeExistingPhoto;
    final hasNewPhoto = _selectedImageBytes != null;

    return GestureDetector(
      onTap: _showImageSourceSheet,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1A14) : const Color(0xFFFBF8F0),
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: (hasNewPhoto || hasExistingPhoto)
                ? const Color(0xFFD4AF37).withValues(alpha: 0.70)
                : const Color(0xFFD4AF37).withValues(alpha: 0.28),
            width: (hasNewPhoto || hasExistingPhoto) ? 2 : 1,
          ),
          boxShadow: (hasNewPhoto || hasExistingPhoto)
              ? [const BoxShadow(color: Color(0x18D4AF37), blurRadius: 10)]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: hasNewPhoto
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(_selectedImageBytes!, fit: BoxFit.cover),
                  _buildPhotoOverlay(onRemove: () {
                    setState(() => _selectedImageBytes = null);
                  }),
                ],
              )
            : hasExistingPhoto
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        existingUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _buildPlaceholderImage(isDark),
                      ),
                      _buildPhotoOverlay(onRemove: () {
                        setState(() => _removeExistingPhoto = true);
                      }),
                    ],
                  )
                : _buildPlaceholderImage(isDark),
      ),
    );
  }

  Widget _buildPlaceholderImage(bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate_outlined,
            size: 30,
            color: isDark ? const Color(0xFF8A7A50) : const Color(0xFFB8A060)),
        const SizedBox(height: 4),
        Text(
          'صورة\nالمنتج',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? const Color(0xFF8A7A50) : const Color(0xFFB8A060)),
        ),
      ],
    );
  }

  Widget _buildPhotoOverlay({required VoidCallback onRemove}) {
    return Stack(
      children: [
        Positioned(
          bottom: 4,
          left: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.85),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.close_rounded, size: 12, color: Colors.white),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.edit_rounded, size: 12, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(ThemeData theme, dynamic colors, bool isDark) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141210) : const Color(0xFFFAF7F0),
        border: Border(
          top: BorderSide(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.20)),
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(AppRadius.lg),
          bottomRight: Radius.circular(AppRadius.lg),
        ),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          const Spacer(),
          if (!_isFormValid && (_touchedNameAr || _touchedCost)) ...[
            Flexible(
              child: Text(
                _isPackType && _packSize <= 0
                    ? 'أدخل عدد القطع في الطرد *'
                    : 'يرجى استكمال الحقول المطلوبة والتأكد من الأسعار *',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          GoldButton.icon(
            onPressed: _isSaving ? null : _handleSave,
            loading: _isSaving,
            icon: Icons.save_rounded,
            label: _isSaving
                ? 'جاري الحفظ...'
                : (_isEditMode ? 'حفظ التعديلات' : 'حفظ المنتج'),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ─────────────────────────────────────────────────────────────

class _ModeChoicePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFD4AF37) : Colors.transparent,
          borderRadius: AppRadius.pillAll,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected
                ? const Color(0xFF1A1400)
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _WeightPill extends StatelessWidget {
  final String label;
  final int? price;
  final double? dzdValue;

  const _WeightPill({
    required this.label,
    this.price,
    this.dzdValue,
  });

  @override
  Widget build(BuildContext context) {
    final text = price != null
        ? DzdFormatter.formatCentimes(price!)
        : '${(dzdValue ?? 0).toStringAsFixed(2)} دج';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFD4AF37).withValues(alpha: 0.12),
        borderRadius: AppRadius.smAll,
      ),
      child: Text(
        '$label: $text',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Color(0xFF8B6B15),
        ),
      ),
    );
  }
}

class _ActiveToggleChip extends StatelessWidget {
  final bool active;
  final ValueChanged<bool> onChanged;

  const _ActiveToggleChip({required this.active, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: () => onChanged(!active),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.sm, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? colors.successContainer
              : Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: AppRadius.pillAll,
          border: Border.all(
            color: active
                ? colors.success.withValues(alpha: 0.40)
                : Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.30),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? Icons.check_circle_outline : Icons.cancel_outlined,
              size: 13,
              color: active
                  ? colors.onSuccessContainer
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              active ? 'نشط' : 'معطل',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: active
                    ? colors.onSuccessContainer
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
