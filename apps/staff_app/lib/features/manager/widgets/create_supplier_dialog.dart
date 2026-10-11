import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import '../../../providers/staff_providers.dart';

class CreateSupplierDialog extends ConsumerStatefulWidget {
  const CreateSupplierDialog({super.key});

  @override
  ConsumerState<CreateSupplierDialog> createState() => _CreateSupplierDialogState();
}

class _CreateSupplierDialogState extends ConsumerState<CreateSupplierDialog> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController(text: '+213');
  final _rcController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _rcController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('يرجى ملء اسم المورد ورقم هاتفه!'),
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
        companyRegister: _rcController.text.trim().isNotEmpty ? _rcController.text.trim() : null,
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
      );

      if (!mounted) return;
      Navigator.pop(context, created);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('فشل حفظ المورد. يرجى التأكد من البيانات وحالة الاتصال.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة مورد جديد (Nouveau Fournisseur)'),
      content: SingleChildScrollView(
        child: ContentConstrainedBox.form(
          maxWidth: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'اسم المورد / الشركة *',
                  prefixIcon: Icon(Icons.business_outlined),
                ),
              ),
              AppSpacing.gapMd,
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف *',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              AppSpacing.gapMd,
              TextField(
                controller: _rcController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'السجل التجاري (RC)',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              AppSpacing.gapMd,
              TextField(
                controller: _notesController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات إضافية',
                  prefixIcon: Icon(Icons.notes_outlined),
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
          label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ المورد'),
        ),
      ],
    );
  }
}
