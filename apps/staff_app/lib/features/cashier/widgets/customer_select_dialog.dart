import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';

class CustomerSelectDialog extends ConsumerStatefulWidget {
  const CustomerSelectDialog({super.key});

  @override
  ConsumerState<CustomerSelectDialog> createState() => _CustomerSelectDialogState();
}

class _CustomerSelectDialogState extends ConsumerState<CustomerSelectDialog> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isCreatingNew = false;

  // New Customer Form
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _creditLimitController = TextEditingController(text: '0');
  final _pinController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _creditLimitController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _handleCreateCustomer() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final pin = _pinController.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('يرجى ملء اسم الزبون ورقم الهاتف'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    final currentUser = ref.read(authStateProvider);
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحديد الموظف الحالي')),
      );
      return;
    }
    if (pin.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('يرجى إدخال رمز PIN الخاص بك (4 أرقام على الأقل)'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repo = ref.read(customerRepositoryProvider);
      final limitDzd = double.tryParse(_creditLimitController.text.trim()) ?? 0;
      final newCustomer = await repo.createCustomer(
        name: name,
        phone: phone,
        callerId: currentUser.id,
        callerPin: pin,
        creditLimitCentimes: (limitDzd * 100).round(),
      );

      if (!mounted) return;
      Navigator.pop(context, newCustomer);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تسجيل الزبون: ${e.toString()}'),
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
    final colors = context.appColors;

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      children: [
                        const Icon(Icons.person_search_rounded, size: 28),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: Text(
                            _isCreatingNew ? 'إضافة زبون جديد' : 'تحديد حساب الزبون والديون',
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _isCreatingNew = !_isCreatingNew),
                    icon: Icon(_isCreatingNew ? Icons.search : Icons.person_add_outlined),
                    label: Text(_isCreatingNew ? 'البحث في القائمة' : 'زبون جديد'),
                  ),
                ],
              ),
              const Divider(),
              if (_isCreatingNew)
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppSpacing.gapMd,
                        TextField(
                          controller: _nameController,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'اسم الزبون / المحل *',
                            prefixIcon: Icon(Icons.business),
                          ),
                        ),
                        AppSpacing.gapMd,
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'رقم الهاتف *',
                            prefixIcon: Icon(Icons.phone),
                          ),
                        ),
                        AppSpacing.gapMd,
                        TextField(
                          controller: _creditLimitController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'سقف الائتمان / الدين المسموح (دج)',
                            prefixIcon: Icon(Icons.credit_card),
                          ),
                        ),
                        AppSpacing.gapMd,
                        TextField(
                          controller: _pinController,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          maxLength: 8,
                          decoration: const InputDecoration(
                            labelText: 'رمز PIN الخاص بك لتأكيد العملية *',
                            prefixIcon: Icon(Icons.lock_outline),
                            counterText: '',
                          ),
                        ),
                        AppSpacing.gapLg,
                        FilledButton.icon(
                          onPressed: _isSaving ? null : _handleCreateCustomer,
                          icon: _isSaving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator.adaptive(strokeWidth: 2))
                              : const Icon(Icons.check),
                          label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ واختيار الزبون'),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'ابحث بالاسم أو رقم الهاتف...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
                AppSpacing.gapMd,
                Expanded(
                  child: FutureBuilder<List<CustomerProfileEntity>>(
                    future: ref.read(customerRepositoryProvider).getCustomers(search: _searchQuery),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const AppLoadingView(message: 'جاري جلب حسابات الزبائن...');
                      }

                      final customers = snapshot.data ?? [];
                      if (customers.isEmpty) {
                        return AppEmptyView(
                          icon: Icons.person_off_outlined,
                          title: 'لا يوجد زبائن مطابقين',
                          description: 'لم يتم العثور على أي زبون بالاسم أو الهاتف المدخل.',
                          actionLabel: 'إضافة كزبون جديد',
                          onAction: () => setState(() => _isCreatingNew = true),
                        );
                      }

                      return ListView.separated(
                        itemCount: customers.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final c = customers[idx];
                          final hasDebt = c.currentDebtCentimes > 0;
                          final isOverLimit = c.currentDebtCentimes >= c.creditLimitCentimes && c.creditLimitCentimes > 0;

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isOverLimit
                                  ? theme.colorScheme.errorContainer
                                  : (hasDebt ? colors.warningContainer : theme.colorScheme.primaryContainer),
                              child: Icon(
                                isOverLimit ? Icons.warning_amber_rounded : Icons.person,
                                color: isOverLimit
                                    ? theme.colorScheme.onErrorContainer
                                    : (hasDebt ? colors.onWarningContainer : theme.colorScheme.onPrimaryContainer),
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                ),
                                if (isOverLimit)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.errorContainer,
                                      borderRadius: AppRadius.smAll,
                                    ),
                                    child: Text(
                                      'تجاوز السقف',
                                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onErrorContainer, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.phone, style: theme.textTheme.bodySmall),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text('الدين الحالي: ', style: theme.textTheme.bodySmall),
                                    DzdPriceTag(
                                      centimes: c.currentDebtCentimes,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: hasDebt ? theme.colorScheme.error : colors.success,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.md),
                                    Text('سقف الائتمان: ', style: theme.textTheme.bodySmall),
                                    DzdPriceTag(
                                      centimes: c.creditLimitCentimes,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (hasDebt)
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                                    child: FilledButton.tonalIcon(
                                      style: FilledButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 4),
                                      ),
                                      icon: const Icon(Icons.payments_outlined, size: 14),
                                      label: const Text('سداد', style: TextStyle(fontSize: 11)),
                                      onPressed: () {
                                        Navigator.pop(context, c);
                                      },
                                    ),
                                  ),
                                const Icon(Icons.arrow_forward_ios, size: 14),
                              ],
                            ),
                            onTap: () => Navigator.pop(context, c),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  Flexible(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, null),
                      icon: const Icon(Icons.person_outline),
                    label: const Text('متابعة كزبون غير مسجل (مباشر)'),
                  ),
                  )
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
