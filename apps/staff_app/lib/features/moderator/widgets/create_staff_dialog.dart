import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';

class CreateStaffDialog extends ConsumerStatefulWidget {
  const CreateStaffDialog({super.key});

  @override
  ConsumerState<CreateStaffDialog> createState() => _CreateStaffDialogState();
}

class _CreateStaffDialogState extends ConsumerState<CreateStaffDialog> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController(text: '+213');
  final _pinController = TextEditingController(text: '1234');
  String _selectedRole = 'cashier';
  String _selectedLang = 'ar';
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _generateRandomPin() {
    final random = Random();
    final pin = (1000 + random.nextInt(9000)).toString();
    setState(() => _pinController.text = pin);
  }

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final pin = _pinController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('يرجى ملء اسم الموظف ورقم الهاتف!'),
          backgroundColor: context.appColors.warning,
        ),
      );
      return;
    }

    if (pin.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('يجب أن يتكون رمز PIN من 4 أرقام!'),
          backgroundColor: context.appColors.warning,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final supa = ref.read(supabaseServiceProvider);
      final res = await supa.createStaffMember(
        name: name,
        phone: phone,
        role: _selectedRole,
        language: _selectedLang,
      );

      final newUserId = res['id'] as String?;
      if (newUserId != null) {
        final currentAdmin = ref.read(authStateProvider);
        final adminId = currentAdmin?.id ?? '11111111-1111-1111-1111-111111111111';
        final repo = ref.read(authRepositoryProvider);
        await repo.resetStaffPinByModerator(
          adminId: adminId,
          targetUserId: newUserId,
          newPin: pin,
        );
      }

      if (!mounted) return;
      res['pin'] = pin;
      Navigator.pop(context, res);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('فشل إنشاء حساب الموظف. تأكد من صحة رقم الهاتف وعدم تكراره.'),
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
      title: const Text('إضافة موظف جديد (Nouveau Membre du Personnel)'),
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
                  labelText: 'اسم الموظف الكامل *',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              AppSpacing.gapMd,
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف (لتسجيل الدخول) *',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              AppSpacing.gapMd,
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      decoration: const InputDecoration(
                        labelText: 'رمز PIN الأولي للدخول *',
                        prefixIcon: Icon(Icons.pin_outlined),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.outlined(
                    tooltip: 'توليد رمز عشوائي',
                    onPressed: _generateRandomPin,
                    icon: const Icon(Icons.casino_outlined),
                  ),
                ],
              ),
              AppSpacing.gapMd,
              DropdownButtonFormField<String>(
                initialValue: _selectedRole,
                decoration: const InputDecoration(labelText: 'الدور الوظيفي والصلاحيات *'),
                items: const [
                  DropdownMenuItem(value: 'cashier', child: Text('أمين الصندوق (Cashier)')),
                  DropdownMenuItem(value: 'manager', child: Text('مدير المخزون والمشتريات (Manager)')),
                  DropdownMenuItem(value: 'driver', child: Text('سائق التوصيل (Delivery Driver)')),
                  DropdownMenuItem(value: 'moderator', child: Text('مشرف عام إضافي (Moderator)')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _selectedRole = val);
                },
              ),
              AppSpacing.gapMd,
              DropdownButtonFormField<String>(
                initialValue: _selectedLang,
                decoration: const InputDecoration(labelText: 'اللغة المفضلة'),
                items: const [
                  DropdownMenuItem(value: 'ar', child: Text('العربية (Arabic)')),
                  DropdownMenuItem(value: 'fr', child: Text('Français (French)')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _selectedLang = val);
                },
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
              : const Icon(Icons.person_add_alt_1),
          label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ وإنشاء الحساب'),
        ),
      ],
    );
  }
}
