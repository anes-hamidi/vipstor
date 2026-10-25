import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';

/// A responsive, high-fidelity screen for selecting an existing customer or quickly registering a new customer.
class CustomerSelectDialog extends ConsumerStatefulWidget {
  const CustomerSelectDialog({super.key});

  /// Opens customer selection as a dedicated fullscreen screen route.
  static Future<CustomerProfileEntity?> show(BuildContext context) {
    return Navigator.of(context).push<CustomerProfileEntity>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const CustomerSelectDialog(),
      ),
    );
  }

  @override
  ConsumerState<CustomerSelectDialog> createState() =>
      _CustomerSelectDialogState();
}

class _CustomerSelectDialogState extends ConsumerState<CustomerSelectDialog> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isCreatingNew = false;
  CustomerProfileEntity? _selectedCustomer;

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
          content:
              const Text('يرجى إدخال رمز PIN الخاص بك (4 أرقام على الأقل)'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repo = ref.read(customerRepositoryProvider);
      final limitDzd =
          double.tryParse(_creditLimitController.text.trim()) ?? 0;
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
    final colorScheme = theme.colorScheme;
    final colors = context.appColors;
    final role = context.roleTheme;
    final brand = role.roleBrandColor;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: colorScheme.surface,
          appBar: AppBar(
            elevation: 0,
            scrolledUnderElevation: 2,
            backgroundColor: colorScheme.surfaceContainer,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'رجوع [Esc]',
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: role.badgeBackground,
                    borderRadius: AppRadius.smAll,
                    border: Border.all(color: brand.withValues(alpha: 0.30)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.person_search_rounded,
                        size: 20, color: role.badgeText),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'تحديد حساب الزبون والديون',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 17),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'اختيار زبون مسجل أو إضافة زبون جديد للوصل الحالي',
                        style:
                            theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding:
                    const EdgeInsetsDirectional.only(end: AppSpacing.md),
                child: OutlinedButton.icon(
                  icon: Icon(_isCreatingNew
                      ? Icons.list_alt_rounded
                      : Icons.person_add_rounded),
                  label: Text(_isCreatingNew
                      ? 'عرض قائمة الزبائن'
                      : 'إضافة زبون جديد'),
                  onPressed: () =>
                      setState(() => _isCreatingNew = !_isCreatingNew),
                ),
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 840;

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Column: Search & Customer list
                    SizedBox(
                      width: 440,
                      child: Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          border: BorderDirectional(
                            end: BorderSide(
                              color: colorScheme.outlineVariant
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: TextField(
                                controller: _searchController,
                                autofocus: true,
                                decoration: InputDecoration(
                                  hintText:
                                      'ابحث باسم الزبون أو رقم هاتفه...',
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  suffixIcon: _searchController.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear_rounded),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() => _searchQuery = '');
                                          },
                                        )
                                      : null,
                                  filled: true,
                                  fillColor: colorScheme.surfaceContainer,
                                  border: const OutlineInputBorder(
                                      borderRadius: AppRadius.mdAll),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                ),
                                onChanged: (v) =>
                                    setState(() => _searchQuery = v),
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: _buildCustomerList(theme, colorScheme, colors),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Right Column: Customer Details or New Registration Form
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 580),
                            child: _isCreatingNew
                                ? _buildNewCustomerForm(
                                    theme, colorScheme, colors, brand)
                                : _buildCustomerPreview(
                                    _selectedCustomer,
                                    theme,
                                    colorScheme,
                                    colors,
                                    brand),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              // Mobile Layout
              if (_isCreatingNew) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: _buildNewCustomerForm(
                      theme, colorScheme, colors, brand),
                );
              }

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'ابحث باسم الزبون أو الهاتف...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerLow,
                        border: const OutlineInputBorder(
                            borderRadius: AppRadius.mdAll),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _buildCustomerList(theme, colorScheme, colors,
                        isMobile: true),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCustomerList(
      ThemeData theme, ColorScheme colorScheme, dynamic colors,
      {bool isMobile = false}) {
    return FutureBuilder<List<CustomerProfileEntity>>(
      future: ref
          .read(customerRepositoryProvider)
          .getCustomers(search: _searchQuery),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: AppLoadingView(message: 'جاري جلب حسابات الزبائن...'),
          );
        }

        final customers = snapshot.data ?? [];
        if (customers.isEmpty) {
          return Center(
            child: AppEmptyView(
              icon: Icons.person_off_outlined,
              title: 'لا يوجد زبائن مطابقين',
              description: 'لم يتم العثور على أي زبون بالاسم أو الهاتف المدخل.',
              actionLabel: 'إضافة كزبون جديد',
              onAction: () => setState(() => _isCreatingNew = true),
            ),
          );
        }

        return ListView.separated(
          itemCount: customers.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, idx) {
            final c = customers[idx];
            final isSel = _selectedCustomer?.id == c.id;
            final hasDebt = c.currentDebtCentimes > 0;
            final isOverLimit = c.currentDebtCentimes >= c.creditLimitCentimes &&
                c.creditLimitCentimes > 0;

            return ListTile(
              selected: isSel,
              selectedTileColor:
                  colorScheme.primaryContainer.withValues(alpha: 0.25),
              onTap: () {
                if (isMobile) {
                  Navigator.pop(context, c);
                } else {
                  setState(() => _selectedCustomer = c);
                }
              },
              leading: CircleAvatar(
                backgroundColor: isOverLimit
                    ? colorScheme.errorContainer
                    : (hasDebt
                        ? colors.warningContainer
                        : colorScheme.primaryContainer),
                child: Icon(
                  isOverLimit
                      ? Icons.warning_amber_rounded
                      : (hasDebt
                          ? Icons.credit_card_rounded
                          : Icons.person_rounded),
                  color: isOverLimit
                      ? colorScheme.onErrorContainer
                      : (hasDebt
                          ? colors.onWarningContainer
                          : colorScheme.onPrimaryContainer),
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      c.name,
                      style: TextStyle(
                        fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isOverLimit)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: AppRadius.xsAll,
                      ),
                      child: Text(
                        'تجاوز السقف',
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onErrorContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: Text(c.phone, style: theme.textTheme.bodySmall),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  DzdPriceTag(
                    centimes: c.currentDebtCentimes,
                    color: hasDebt ? colorScheme.error : colors.success,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    hasDebt ? 'دين حالي' : 'لا توجد ديون',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: hasDebt ? colorScheme.error : colors.success,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCustomerPreview(CustomerProfileEntity? c, ThemeData theme,
      ColorScheme colorScheme, dynamic colors, Color brand) {
    if (c == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_pin_rounded,
                size: 64, color: colorScheme.outlineVariant),
            AppSpacing.gapMd,
            Text(
              'اختر زبونًا من القائمة على اليمين',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'أو انقر على زر "إضافة زبون جديد" لتسجيل عميل جديد فورًا',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    final hasDebt = c.currentDebtCentimes > 0;
    final remainingCredit = c.creditLimitCentimes - c.currentDebtCentimes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxuryCard(
          goldAccent: true,
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: brand.withValues(alpha: 0.15),
                child: Icon(Icons.person_rounded, size: 40, color: brand),
              ),
              AppSpacing.gapMd,
              Text(
                c.name,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.phone_rounded, size: 16),
                  const SizedBox(width: 4),
                  Text(c.phone, style: theme.textTheme.bodyMedium),
                ],
              ),
              const Divider(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statItem('الدين الحالي', c.currentDebtCentimes,
                      hasDebt ? colorScheme.error : colors.success),
                  _statItem('سقف الائتمان', c.creditLimitCentimes,
                      colorScheme.onSurface),
                  _statItem(
                      'الائتمان المتاح',
                      remainingCredit > 0 ? remainingCredit : 0,
                      remainingCredit > 0 ? colors.success : colorScheme.error),
                ],
              ),
            ],
          ),
        ),
        AppSpacing.gapXl,
        GoldButton.icon(
          icon: Icons.check_circle_rounded,
          label: 'اختيار الزبون وتعيينه للوصل الحالي',
          onPressed: () => Navigator.pop(context, c),
        ),
      ],
    );
  }

  Widget _statItem(String label, int centimes, Color? color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11)),
        const SizedBox(height: 4),
        DzdPriceTag(
          centimes: centimes,
          color: color,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildNewCustomerForm(ThemeData theme, ColorScheme colorScheme,
      dynamic colors, Color brand) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'تسجيل حساب زبون جديد:',
          style:
              theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'أدخل بيانات الزبون وسقف الائتمان لتمكين البيع بالدين',
          style: theme.textTheme.bodySmall,
        ),
        AppSpacing.gapLg,
        TextField(
          controller: _nameController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'اسم الزبون / المحل التجاري *',
            prefixIcon: const Icon(Icons.person_outline_rounded),
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
            border: const OutlineInputBorder(borderRadius: AppRadius.mdAll),
          ),
        ),
        AppSpacing.gapMd,
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: 'رقم الهاتف *',
            prefixIcon: const Icon(Icons.phone_rounded),
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
            border: const OutlineInputBorder(borderRadius: AppRadius.mdAll),
          ),
        ),
        AppSpacing.gapMd,
        TextField(
          controller: _creditLimitController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'سقف الائتمان / الدين المسموح (دج)',
            suffixText: 'دج',
            prefixIcon: const Icon(Icons.credit_card_rounded),
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
            border: const OutlineInputBorder(borderRadius: AppRadius.mdAll),
          ),
        ),
        AppSpacing.gapMd,
        TextField(
          controller: _pinController,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 8,
          decoration: InputDecoration(
            labelText: 'رمز PIN الخاص بك لتأكيد العملية *',
            hintText: '••••',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            counterText: '',
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
            border: const OutlineInputBorder(borderRadius: AppRadius.mdAll),
          ),
        ),
        AppSpacing.gapXl,
        GoldButton.icon(
          onPressed: _isSaving ? null : _handleCreateCustomer,
          icon: _isSaving
              ? Icons.hourglass_top_rounded
              : Icons.check_circle_rounded,
          label: _isSaving ? 'جاري الحفظ...' : 'حفظ واختيار الزبون للوصل',
        ),
      ],
    );
  }
}
