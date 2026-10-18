import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';

// ─── Role descriptor ─────────────────────────────────────────────────────────

class _RoleOption {
  final String value;
  final String labelAr;
  final String labelFr;
  final String description;
  final IconData icon;
  final Color color;

  const _RoleOption({
    required this.value,
    required this.labelAr,
    required this.labelFr,
    required this.description,
    required this.icon,
    required this.color,
  });
}

const _roles = [
  _RoleOption(
    value: 'cashier',
    labelAr: 'أمين الصندوق',
    labelFr: 'Cashier',
    description: 'نقطة البيع، الوصلات، قراءة الباركود',
    icon: Icons.point_of_sale_rounded,
    color: Color(0xFF2196F3),
  ),
  _RoleOption(
    value: 'manager',
    labelAr: 'مدير المخزون',
    labelFr: 'Manager',
    description: 'المشتريات، الكتالوج، الطلبيات',
    icon: Icons.inventory_2_rounded,
    color: Color(0xFF9C27B0),
  ),
  _RoleOption(
    value: 'driver',
    labelAr: 'سائق التوصيل',
    labelFr: 'Livreur',
    description: 'التوصيل، التحصيل، الخريطة',
    icon: Icons.local_shipping_rounded,
    color: Color(0xFF4CAF50),
  ),
  _RoleOption(
    value: 'moderator',
    labelAr: 'مشرف عام',
    labelFr: 'Modérateur',
    description: 'صلاحيات كاملة، إدارة الطاقم',
    icon: Icons.admin_panel_settings_rounded,
    color: Color(0xFFD4AF37),
  ),
];

// ─── Dialog ──────────────────────────────────────────────────────────────────

class CreateStaffDialog extends ConsumerStatefulWidget {
  const CreateStaffDialog({super.key});

  @override
  ConsumerState<CreateStaffDialog> createState() => _CreateStaffDialogState();
}

class _CreateStaffDialogState extends ConsumerState<CreateStaffDialog>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController(text: '+213');
  final _pinController = TextEditingController(text: '1234');
  final _adminPinController = TextEditingController();

  String _selectedRole = 'cashier';
  String _selectedLang = 'ar';
  bool _isSaving = false;
  bool _showAdminPin = false;
  bool _showStaffPin = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _fadeAnim =
        CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    _adminPinController.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _generateRandomPin() {
    final pin =
        (1000 + Random().nextInt(9000)).toString();
    setState(() => _pinController.text = pin);
    HapticFeedback.lightImpact();
  }

  _RoleOption get _currentRole =>
      _roles.firstWhere((r) => r.value == _selectedRole);

  // ── Validation ────────────────────────────────────────────────────────────

  String? get _nameError {
    if (_nameController.text.trim().isEmpty) return 'الاسم مطلوب';
    return null;
  }

  String? get _phoneError {
    final p = _phoneController.text.trim();
    if (p.isEmpty || p == '+213') return 'رقم الهاتف مطلوب';
    return null;
  }

  String? get _pinError {
    if (_pinController.text.trim().length < 4) return 'PIN يجب أن يكون 4 أرقام';
    return null;
  }

  String? get _adminPinError {
    if (_adminPinController.text.trim().length < 4) {
      return 'PIN المشرف مطلوب للتأكيد';
    }
    return null;
  }

  Future<void> _handleSave() async {
    // Trigger UI rebuild to show errors
    setState(() {});

    if (_nameError != null ||
        _phoneError != null ||
        _pinError != null ||
        _adminPinError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('يرجى تصحيح الحقول المُشار إليها'),
          backgroundColor: context.appColors.warning,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final supa = ref.read(supabaseServiceProvider);
      final currentAdmin = ref.read(authStateProvider);
      final adminId = currentAdmin?.id;
      if (adminId == null) return;

      final res = await supa.createStaffMember(
        adminId: adminId,
        adminPin: _adminPinController.text.trim(),
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        role: _selectedRole,
        initialPin: _pinController.text.trim(),
        language: _selectedLang,
      );

      if (!mounted) return;
      res['pin'] = _pinController.text.trim();
      Navigator.pop(context, res);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل إنشاء حساب الموظف: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Dialog(
        shape:
            const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 820),
          child: Column(
            children: [
              // ── Gold Header ───────────────────────────────────────
              _buildHeader(theme, isDark),

              // ── Scrollable Body ───────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Section 1: Identity
                      const SectionHeader(title: 'بيانات الموظف'),
                      AppSpacing.gapMd,
                      _buildNameField(theme),
                      AppSpacing.gapMd,
                      _buildPhoneField(),
                      AppSpacing.gapXl,

                      // Section 2: Role
                      const SectionHeader(title: 'الدور والصلاحيات'),
                      AppSpacing.gapMd,
                      _buildRoleSelector(isDark),
                      AppSpacing.gapXl,

                      // Section 3: Language
                      const SectionHeader(title: 'اللغة والواجهة'),
                      AppSpacing.gapMd,
                      _buildLanguageToggle(theme, isDark),
                      AppSpacing.gapXl,

                      // Section 4: Initial PIN
                      const SectionHeader(title: 'رمز الدخول الأولي (PIN)'),
                      AppSpacing.gapSm,
                      Text(
                        'سيستخدمه الموظف للدخول السريع — يمكن تغييره لاحقاً',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                      AppSpacing.gapMd,
                      _buildPinField(theme, isDark),
                      AppSpacing.gapXl,

                      // Section 5: Admin confirmation
                      _buildAdminConfirmZone(theme, isDark),
                    ],
                  ),
                ),
              ),

              // ── Footer ────────────────────────────────────────────
              _buildFooter(isDark),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Section builders ─────────────────────────────────────────────────────

  Widget _buildHeader(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.md, AppSpacing.md),
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                colors: [Color(0xFF1C1810), Color(0xFF141210)])
            : const LinearGradient(
                colors: [Color(0xFFFBF6E8), Color(0xFFFAF7F0)]),
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
              child: Icon(Icons.person_add_alt_1_rounded,
                  size: 20, color: Color(0xFF1A1400)),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إضافة موظف جديد',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Nouveau membre du personnel',
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
                foregroundColor: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildNameField(ThemeData theme) {
    return TextField(
      controller: _nameController,
      autofocus: true,
      textInputAction: TextInputAction.next,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: 'الاسم الكامل *',
        hintText: 'مثال: أحمد بن علي',
        prefixIcon: const Icon(Icons.badge_outlined),
        errorText: _nameController.text.isNotEmpty ? _nameError : null,
      ),
    );
  }

  Widget _buildPhoneField() {
    return TextField(
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.next,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: 'رقم الهاتف (لتسجيل الدخول) *',
        hintText: '+213 5XX XX XX XX',
        prefixIcon: const Icon(Icons.phone_outlined),
        errorText: _phoneController.text.isNotEmpty &&
                _phoneController.text != '+213'
            ? _phoneError
            : null,
        helperText: 'سيُستخدم كمعرف لتسجيل الدخول',
      ),
    );
  }

  Widget _buildRoleSelector(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Role chips — 2×2 grid on phone, row on wider
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: _roles
              .map((role) => _RoleChip(
                    role: role,
                    selected: _selectedRole == role.value,
                    isDark: isDark,
                    onTap: () =>
                        setState(() => _selectedRole = role.value),
                  ))
              .toList(),
        ),
        AppSpacing.gapSm,

        // Selected role description card
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsetsDirectional.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: _currentRole.color.withValues(alpha: isDark ? 0.12 : 0.08),
            borderRadius: AppRadius.smAll,
            border: Border.all(
              color: _currentRole.color.withValues(alpha: 0.30),
            ),
          ),
          child: Row(
            children: [
              Icon(_currentRole.icon,
                  size: 16, color: _currentRole.color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${_currentRole.labelAr}: ${_currentRole.description}',
                  style: TextStyle(
                    fontSize: 12,
                    color: _currentRole.color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageToggle(ThemeData theme, bool isDark) {
    return Row(
      children: [
        _LangChip(
          code: 'ar',
          label: 'العربية',
          flag: '🇩🇿',
          selected: _selectedLang == 'ar',
          isDark: isDark,
          onTap: () => setState(() => _selectedLang = 'ar'),
        ),
        const SizedBox(width: AppSpacing.sm),
        _LangChip(
          code: 'fr',
          label: 'Français',
          flag: '🇫🇷',
          selected: _selectedLang == 'fr',
          isDark: isDark,
          onTap: () => setState(() => _selectedLang = 'fr'),
        ),
      ],
    );
  }

  Widget _buildPinField(ThemeData theme, bool isDark) {
    final pin = _pinController.text;
    final isFull = pin.length == 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                obscureText: !_showStaffPin,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'رمز PIN الأولي (4 أرقام) *',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  counterText: '',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showStaffPin
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    onPressed: () =>
                        setState(() => _showStaffPin = !_showStaffPin),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            GoldIconButton(
              icon: Icons.casino_outlined,
              tooltip: 'توليد رمز عشوائي',
              onPressed: _generateRandomPin,
            ),
          ],
        ),
        AppSpacing.gapSm,

        // PIN strength dots
        Row(
          children: List.generate(4, (i) {
            final filled = i < pin.length;
            return Padding(
              padding: EdgeInsetsDirectional.only(
                  end: i < 3 ? AppSpacing.xs : 0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled
                      ? (isFull
                          ? const Color(0xFFD4AF37)
                          : theme.colorScheme.primary)
                      : theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.40),
                  boxShadow: filled && isFull
                      ? [
                          BoxShadow(
                            color: const Color(0xFFD4AF37)
                                .withValues(alpha: 0.40),
                            blurRadius: 6,
                          )
                        ]
                      : null,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildAdminConfirmZone(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1C1410).withValues(alpha: 0.60)
            : const Color(0xFFFFF8E8).withValues(alpha: 0.80),
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.admin_panel_settings_rounded,
                  size: 16, color: Color(0xFFD4AF37)),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'تأكيد الهوية — PIN المشرف',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? const Color(0xFFF3D278)
                      : const Color(0xFF9A7319),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'أدخل رمز PIN الخاص بك لتفويض إنشاء هذا الحساب',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant),
          ),
          AppSpacing.gapMd,
          TextField(
            controller: _adminPinController,
            obscureText: !_showAdminPin,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'PIN المشرف *',
              prefixIcon: const Icon(Icons.key_rounded),
              counterText: '',
              errorText: _adminPinController.text.isNotEmpty
                  ? _adminPinError
                  : null,
              suffixIcon: IconButton(
                icon: Icon(
                  _showAdminPin
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                ),
                onPressed: () =>
                    setState(() => _showAdminPin = !_showAdminPin),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(bool isDark) {
    final isValid = _nameError == null &&
        _phoneError == null &&
        _pinError == null &&
        _adminPinError == null &&
        _nameController.text.isNotEmpty &&
        _pinController.text.length == 4 &&
        _adminPinController.text.length == 4;

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
      decoration: BoxDecoration(
        color:
            isDark ? const Color(0xFF141210) : const Color(0xFFFAF7F0),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(AppRadius.lg),
          bottomRight: Radius.circular(AppRadius.lg),
        ),
        border: Border(
          top: BorderSide(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.18),
          ),
        ),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          const Spacer(),
          // Role badge preview
          if (!_isSaving) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: 4),
              decoration: BoxDecoration(
                color: _currentRole.color.withValues(alpha: 0.10),
                borderRadius: AppRadius.pillAll,
                border: Border.all(
                    color: _currentRole.color.withValues(alpha: 0.30)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_currentRole.icon,
                      size: 12, color: _currentRole.color),
                  const SizedBox(width: 4),
                  Text(
                    _currentRole.labelAr,
                    style: TextStyle(
                        fontSize: 11,
                        color: _currentRole.color,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          GoldButton.icon(
            onPressed: (_isSaving || !isValid) ? null : _handleSave,
            loading: _isSaving,
            icon: Icons.person_add_alt_1_rounded,
            label: _isSaving ? 'جاري الإنشاء...' : 'إنشاء الحساب',
          ),
        ],
      ),
    );
  }
}

// ─── Role Chip ────────────────────────────────────────────────────────────────

class _RoleChip extends StatelessWidget {
  final _RoleOption role;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _RoleChip({
    required this.role,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected
              ? role.color.withValues(alpha: isDark ? 0.18 : 0.10)
              : (isDark
                  ? const Color(0xFF1A1814)
                  : const Color(0xFFF5F3EE)),
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: selected
                ? role.color.withValues(alpha: 0.55)
                : (isDark
                    ? const Color(0xFF2A2520)
                    : const Color(0xFFE0DBD0)),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: role.color.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              role.icon,
              size: 16,
              color: selected
                  ? role.color
                  : (isDark
                      ? const Color(0xFF8A8070)
                      : const Color(0xFF9A9080)),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              role.labelAr,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    selected ? FontWeight.bold : FontWeight.normal,
                color: selected
                    ? role.color
                    : (isDark
                        ? const Color(0xFFB0A890)
                        : const Color(0xFF5A5040)),
              ),
            ),
            if (selected) ...[
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.check_circle_rounded,
                  size: 12, color: role.color),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Language Chip ────────────────────────────────────────────────────────────

class _LangChip extends StatelessWidget {
  final String code;
  final String label;
  final String flag;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _LangChip({
    required this.code,
    required this.label,
    required this.flag,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
              : (isDark
                  ? const Color(0xFF1A1814)
                  : const Color(0xFFF5F3EE)),
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.55)
                : (isDark
                    ? const Color(0xFF2A2520)
                    : const Color(0xFFE0DBD0)),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(flag, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    selected ? FontWeight.bold : FontWeight.normal,
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : (isDark
                        ? const Color(0xFFB0A890)
                        : const Color(0xFF5A5040)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
