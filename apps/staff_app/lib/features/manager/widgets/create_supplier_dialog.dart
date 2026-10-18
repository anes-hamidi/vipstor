import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import '../../../providers/staff_providers.dart';

class CreateSupplierDialog extends ConsumerStatefulWidget {
  const CreateSupplierDialog({super.key});

  @override
  ConsumerState<CreateSupplierDialog> createState() => _CreateSupplierDialogState();
}

class _CreateSupplierDialogState extends ConsumerState<CreateSupplierDialog>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController(text: '+213');
  final _rcController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isSaving = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _rcController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('يرجى إدخال اسم المورد!'),
          backgroundColor: context.appColors.warning,
        ),
      );
      return;
    }
    if (phone.isEmpty || phone == '+213') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('يرجى إدخال رقم هاتف المورد!'),
          backgroundColor: context.appColors.warning,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repo = ref.read(purchaseRepositoryProvider);
      final created = await repo.createSupplier(
        name: name,
        phone: phone,
        companyRegister: _rcController.text.trim().isNotEmpty
            ? _rcController.text.trim()
            : null,
        notes: [
          if (_addressController.text.trim().isNotEmpty)
            'العنوان: ${_addressController.text.trim()}',
          if (_notesController.text.trim().isNotEmpty)
            _notesController.text.trim(),
        ].join('\n').trim().isNotEmpty
            ? [
                if (_addressController.text.trim().isNotEmpty)
                  'العنوان: ${_addressController.text.trim()}',
                if (_notesController.text.trim().isNotEmpty)
                  _notesController.text.trim(),
              ].join('\n')
            : null,
      );

      if (!mounted) return;
      Navigator.pop(context, created);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل حفظ المورد: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 8),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Dialog(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Gold Header ─────────────────────────────────────────
              Container(
                padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.lg, AppSpacing.md, AppSpacing.md, AppSpacing.md),
                decoration: BoxDecoration(
                  gradient: isDark
                      ? const LinearGradient(
                          colors: [Color(0xFF1C1810), Color(0xFF141210)],
                        )
                      : const LinearGradient(
                          colors: [Color(0xFFFBF6E8), Color(0xFFFAF7F0)],
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
                        child: Icon(Icons.business_rounded,
                            size: 20, color: Color(0xFF1A1400)),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'إضافة مورد جديد',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Nouveau fournisseur',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                      style: IconButton.styleFrom(
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Form Body ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionHeader(title: 'بيانات التعريف'),
                    AppSpacing.gapMd,
                    TextField(
                      controller: _nameController,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'اسم المورد / الشركة *',
                        hintText: 'مثال: مؤسسة الأمين للتجارة',
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                    ),
                    AppSpacing.gapMd,
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'رقم الهاتف *',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: TextField(
                            controller: _rcController,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'السجل التجاري (RC)',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                          ),
                        ),
                      ],
                    ),
                    AppSpacing.gapMd,
                    TextField(
                      controller: _addressController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'العنوان / المنطقة',
                        prefixIcon: Icon(Icons.location_on_outlined),
                        hintText: 'مثال: حي السلام، باتنة',
                      ),
                    ),
                    AppSpacing.gapMd,
                    TextField(
                      controller: _notesController,
                      textInputAction: TextInputAction.done,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات إضافية',
                        prefixIcon: Padding(
                          padding: EdgeInsets.only(bottom: AppSpacing.xl),
                          child: Icon(Icons.notes_outlined),
                        ),
                        hintText: 'شروط الدفع، مدة التسليم...',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Footer ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF141210) : const Color(0xFFFAF7F0),
                  border: Border(
                    top: BorderSide(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.18),
                    ),
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
                    GoldButton.icon(
                      onPressed: _isSaving ? null : _handleSave,
                      loading: _isSaving,
                      icon: Icons.save_rounded,
                      label: _isSaving ? 'جاري الحفظ...' : 'حفظ المورد',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
