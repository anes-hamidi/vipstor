import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';

/// A bottom sheet / dialog for editing any staff member's profile.
/// Usable from any screen: moderator dashboard, cashier settings,
/// driver profile, manager profile, etc.
///
/// Usage:
/// ```dart
/// await StaffProfileEditSheet.show(context, ref, userId: user.id);
/// ```
class StaffProfileEditSheet extends ConsumerStatefulWidget {
  final String userId;
  final String initialName;
  final String initialPhone;
  final String initialRole;
  final bool initialActive;
  final String initialLanguage;

  const StaffProfileEditSheet({
    super.key,
    required this.userId,
    required this.initialName,
    required this.initialPhone,
    required this.initialRole,
    required this.initialActive,
    required this.initialLanguage,
  });

  /// Convenience factory to show as a modal bottom sheet.
  static Future<bool?> show(
    BuildContext context,
    WidgetRef ref, {
    required String userId,
    required String name,
    required String phone,
    required String role,
    required bool active,
    required String language,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: StaffProfileEditSheet(
          userId: userId,
          initialName: name,
          initialPhone: phone,
          initialRole: role,
          initialActive: active,
          initialLanguage: language,
        ),
      ),
    );
  }

  @override
  ConsumerState<StaffProfileEditSheet> createState() =>
      _StaffProfileEditSheetState();
}

class _StaffProfileEditSheetState
    extends ConsumerState<StaffProfileEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _callerPinCtrl;
  late final TextEditingController _newPinCtrl;
  late String _role;
  late bool _active;
  late String _language;
  bool _changePin = false;
  bool _saving = false;
  String? _error;

  static const _roles = [
    ('moderator', 'مشرف عام', Icons.admin_panel_settings_rounded),
    ('manager', 'مدير مخزون', Icons.inventory_2_rounded),
    ('cashier', 'أمين صندوق', Icons.point_of_sale_rounded),
    ('driver', 'سائق توصيل', Icons.local_shipping_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _phone = TextEditingController(text: widget.initialPhone);
    _callerPinCtrl = TextEditingController();
    _newPinCtrl = TextEditingController();
    _role = widget.initialRole;
    _active = widget.initialActive;
    _language = widget.initialLanguage;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _callerPinCtrl.dispose();
    _newPinCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final currentUser = ref.read(authStateProvider);
      if (currentUser == null) {
        throw Exception('تعذر تحديد المستخدم الحالي');
      }

      final isModerator = currentUser.role == UserRole.moderator;
      final callerPin = _callerPinCtrl.text.trim();
      if (callerPin.length < 4) {
        throw Exception('يرجى إدخال رمز PIN الخاص بك لتأكيد الحفظ');
      }

      final newPin = _changePin ? _newPinCtrl.text.trim() : null;
      if (_changePin && (newPin == null || newPin.length < 4)) {
        throw Exception('رمز PIN الجديد يجب أن يتكون من 4 أرقام على الأقل');
      }

      // One RPC verifies the caller, enforces the moderator/self rule,
      // protects the last active moderator, and optionally resets the
      // target's PIN. No direct table update is attempted.
      final client = ref.read(supabaseClientProvider);
      final res = await client.rpc('rpc_save_user_profile', params: {
        'p_caller_id': currentUser.id,
        'p_caller_pin': callerPin,
        'p_target_user_id': widget.userId,
        'p_name': _name.text.trim(),
        'p_phone': _phone.text.trim(),
        'p_language': _language,
        'p_role': isModerator ? _role : null,
        'p_active': isModerator ? _active : null,
        'p_new_pin': newPin,
      });

      if (res is! Map || res['status'] != 'success') {
        throw Exception(
          (res is Map ? res['message'] : null)?.toString() ??
              'تعذر حفظ التعديلات',
        );
      }

      // Immediately update in-memory auth state if editing self.
      if (currentUser.id == widget.userId) {
        ref.read(authStateProvider.notifier).state = currentUser.copyWith(
          name: res['name'] as String? ?? _name.text.trim(),
          phone: res['phone'] as String? ?? _phone.text.trim(),
          language: res['language'] as String? ?? _language,
          role: isModerator ? UserRole.fromString(_role) : currentUser.role,
          active: isModerator ? _active : currentUser.active,
        );
      }

      ref.invalidate(staffMembersProvider);
      ref.invalidate(liveStaffUsersProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'تعذر حفظ التعديلات: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final isDark = theme.brightness == Brightness.dark;
    final currentUser = ref.watch(authStateProvider);
    final isModerator = currentUser?.role == UserRole.moderator;

    return DraggableScrollableSheet(
      initialChildSize: 0.80,
      maxChildSize: 0.95,
      minChildSize: 0.45,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: isDark ? colors.obsidianCard : theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
        ),
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
              child: Row(
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppGradients.gold,
                      shape: BoxShape.circle,
                      boxShadow: [AppShadows.goldGlowSm],
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.manage_accounts_rounded,
                          size: 20, color: Color(0xFF1A1400)),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تعديل الملف الشخصي',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          widget.initialName,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Form
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
                  children: [
                    // Full Name
                    TextFormField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
                      decoration: const InputDecoration(
                        labelText: 'الاسم الكامل *',
                        prefixIcon: Icon(Icons.person_rounded),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // Phone Number
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'رقم الهاتف مطلوب' : null,
                      decoration: const InputDecoration(
                        labelText: 'رقم الهاتف *',
                        prefixIcon: Icon(Icons.phone_rounded),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Role Section: editable by moderator, view-only badge for driver/manager
                    if (isModerator) ...[
                      Text('الصلاحية / الدور',
                          style: theme.textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: _roles.map((r) {
                          final (value, label, icon) = r;
                          final selected = _role == value;
                          return GestureDetector(
                            onTap: () => setState(() => _role = value),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsetsDirectional.symmetric(
                                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                              decoration: BoxDecoration(
                                gradient: selected ? AppGradients.gold : null,
                                color: selected
                                    ? null
                                    : (isDark
                                        ? colors.obsidianSurface
                                        : theme.colorScheme.surfaceContainerHighest),
                                borderRadius: AppRadius.mdAll,
                                border: Border.all(
                                  color: selected
                                      ? const Color(0xFFD4AF37)
                                      : theme.colorScheme.outlineVariant,
                                ),
                                boxShadow: selected ? [AppShadows.goldGlowSm] : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(icon,
                                      size: 16,
                                      color: selected
                                          ? const Color(0xFF1A1400)
                                          : theme.colorScheme.onSurfaceVariant),
                                  const SizedBox(width: 6),
                                  Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: selected
                                          ? const Color(0xFF1A1400)
                                          : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? colors.obsidianSurface : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: AppRadius.mdAll,
                          border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.badge_outlined, size: 20, color: Color(0xFFD4AF37)),
                            const SizedBox(width: AppSpacing.sm),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('الدور الوظيفي الحالي', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                                const SizedBox(height: 2),
                                Text(
                                  _roles.firstWhere((r) => r.$1 == _role, orElse: () => ('', _role, Icons.person)).$2,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    // Preferred Language
                    Text('اللغة المفضلة',
                        style: theme.textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        _LangChip(
                          label: 'العربية',
                          value: 'ar',
                          selected: _language == 'ar',
                          onTap: () => setState(() => _language = 'ar'),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        _LangChip(
                          label: 'Français',
                          value: 'fr',
                          selected: _language == 'fr',
                          onTap: () => setState(() => _language = 'fr'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Active account toggle (only moderator can enable/disable staff)
                    if (isModerator) ...[
                      LuxuryCard(
                        padding: const EdgeInsetsDirectional.symmetric(
                            horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                        child: SwitchListTile.adaptive(
                          value: _active,
                          onChanged: (v) => setState(() => _active = v),
                          title: Text(
                            _active ? 'الحساب نشط' : 'الحساب معطل',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            _active
                                ? 'يمكن لهذا الموظف تسجيل الدخول'
                                : 'لا يمكن لهذا الموظف تسجيل الدخول',
                            style: theme.textTheme.bodySmall,
                          ),
                          secondary: Icon(
                            _active
                                ? Icons.check_circle_rounded
                                : Icons.cancel_rounded,
                            color: _active ? colors.success : colors.error,
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    // Caller PIN confirmation (always required)
                    LuxuryCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.verified_user_outlined,
                                  size: 20, color: Color(0xFFD4AF37)),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'تأكيد هويتك',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            isModerator
                                ? 'أدخل رمز PIN الخاص بك لتأكيد تعديل بيانات الموظف.'
                                : 'أدخل رمز PIN الخاص بك لتأكيد حفظ ملفك الشخصي.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          TextFormField(
                            controller: _callerPinCtrl,
                            keyboardType: TextInputType.number,
                            obscureText: true,
                            maxLength: 8,
                            decoration: const InputDecoration(
                              labelText: 'رمز PIN الخاص بك *',
                              prefixIcon: Icon(Icons.lock_outline),
                              counterText: '',
                            ),
                            validator: (v) {
                              if (v == null || v.trim().length < 4) {
                                return 'يرجى إدخال رمز PIN الخاص بك (4 أرقام على الأقل)';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Optional new PIN for the target account
                    LuxuryCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.pin_outlined,
                                  size: 20, color: Color(0xFFD4AF37)),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'تعيين رمز PIN جديد للموظف',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                              Switch.adaptive(
                                value: _changePin,
                                onChanged: (v) => setState(() {
                                  _changePin = v;
                                  if (!v) _newPinCtrl.clear();
                                }),
                              ),
                            ],
                          ),
                          if (_changePin) ...[
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _newPinCtrl,
                              keyboardType: TextInputType.number,
                              obscureText: true,
                              maxLength: 8,
                              decoration: const InputDecoration(
                                labelText:
                                    'رمز PIN الجديد (4 أرقام على الأقل) *',
                                prefixIcon: Icon(Icons.lock_reset),
                                counterText: '',
                              ),
                              validator: (v) {
                                if (!_changePin) return null;
                                if (v == null || v.trim().length < 4) {
                                  return 'يجب أن يكون الرمز 4 أرقام على الأقل';
                                }
                                return null;
                              },
                            ),
                          ],
                        ],
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        padding: const EdgeInsetsDirectional.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: colors.error.withValues(alpha: 0.1),
                          borderRadius: AppRadius.mdAll,
                          border: Border.all(
                              color: colors.error.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline_rounded,
                                color: colors.error, size: 18),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(_error!,
                                  style: TextStyle(
                                      color: colors.error, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),
            // Save button
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                MediaQuery.paddingOf(context).bottom + AppSpacing.lg,
              ),
              child: GoldButton.icon(
                icon: Icons.save_rounded,
                label: _saving ? 'جاري الحفظ...' : 'حفظ التعديلات',
                onPressed: _saving ? null : _save,
                loading: _saving,
                width: double.infinity,
                height: 52,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const _LangChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected ? AppGradients.gold : null,
          color: selected ? null : theme.colorScheme.surfaceContainerHighest,
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: selected
                ? const Color(0xFFD4AF37)
                : theme.colorScheme.outlineVariant,
          ),
          boxShadow: selected ? [AppShadows.goldGlowSm] : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: selected ? const Color(0xFF1A1400) : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
