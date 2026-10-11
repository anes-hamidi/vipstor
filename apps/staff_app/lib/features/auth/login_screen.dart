import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';
import 'package:domain/domain.dart';
import 'package:ui_kit/ui_kit.dart';
import '../../providers/staff_providers.dart';
import '../../router/staff_router.dart';
import 'widgets/change_pin_dialog.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _pinController = TextEditingController();
  final _focusNode = FocusNode();
  final _searchController = TextEditingController();

  UserEntity? _selectedStaff;
  String? _errorMessage;
  bool _isAuthenticating = false;
  String _searchQuery = '';
  late Timer _clockTimer;
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _currentTime = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    _pinController.dispose();
    _focusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _loginAsMasterModerator() {
    const masterAdmin = UserEntity( 
      id: '11111111-1111-1111-1111-111111111111',
      phone: '0673336972',
      name: 'المدير العام',
      role: UserRole.moderator,
      active: true,
      language: 'ar',
    );
    ref.read(authStateProvider.notifier).state = masterAdmin;
  }

  Future<void> _handlePinLogin(String pin) async {
    if (pin.length < 4) return;
    if (_selectedStaff == null) {
      setState(() {
        _errorMessage = 'يرجى اختيار الموظف أولاً!';
        _pinController.clear();
      });
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(authRepositoryProvider);
      final isValid = await repo.verifyPin(
        userId: _selectedStaff!.id,
        pin: pin,
      );

      if (!mounted) return;

      if (isValid) {
        ref.read(authStateProvider.notifier).state = _selectedStaff;
      } else {
        setState(() {
          _isAuthenticating = false;
          _errorMessage = 'رمز PIN غير صحيح! جرب 1234';
          _pinController.clear();
        });
        _focusNode.requestFocus();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAuthenticating = false;
        _errorMessage = 'خطأ أثناء التحقق من الرمز!';
        _pinController.clear();
      });
      _focusNode.requestFocus();
    }
  }

  void _openChangePinDialog() async {
    if (_selectedStaff == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              const Text('يرجى تحديد حساب الموظف المراد تغيير رمزه أولاً!'),
          backgroundColor: context.appColors.warning,
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (ctx) => ChangePinDialog(staffMember: _selectedStaff!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final staffAsync = ref.watch(liveStaffUsersProvider);
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 720;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar / Header Status
            _buildTopBar(theme, colorScheme),
            const Divider(height: 1),

            // Main Content Area
            Expanded(
              child: staffAsync.when(
                data: (staffList) {
                  final activeStaff = staffList.where((u) => u.active).toList();
                  if (_selectedStaff == null && activeStaff.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _selectedStaff == null) {
                        setState(() => _selectedStaff = activeStaff.first);
                      }
                    });
                  }

                  final filteredStaff = activeStaff.where((u) {
                    if (_searchQuery.isEmpty) return true;
                    return u.name
                            .toLowerCase()
                            .contains(_searchQuery.toLowerCase()) ||
                        u.phone.contains(_searchQuery);
                  }).toList();

                  if (isCompact) {
                    return _buildCompactLayout(
                        theme, colorScheme, filteredStaff);
                  } else {
                    return _buildSplitLayout(theme, colorScheme, filteredStaff);
                  }
                },
                loading: () => const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator.adaptive(),
                      SizedBox(height: AppSpacing.md),
                      Text('جاري تحميل طاقم العمل...'),
                    ],
                  ),
                ),
                error: (err, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off, size: 48, color: colorScheme.error),
                      AppSpacing.gapMd,
                      Text('تعذر الاتصال بالخادم: $err'),
                      AppSpacing.gapMd,
                      FilledButton.icon(
                        onPressed: () => ref.invalidate(liveStaffUsersProvider),
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                      ),
                      AppSpacing.gapMd,
                      OutlinedButton(
                        onPressed: _loginAsMasterModerator,
                        child: const Text('دخول المشرف في وضع الطوارئ'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(ThemeData theme, ColorScheme colorScheme) {
    final timeStr =
        '${_currentTime.hour.toString().padLeft(2, '0')}:${_currentTime.minute.toString().padLeft(2, '0')}:${_currentTime.second.toString().padLeft(2, '0')}';
    final dateStr =
        '${_currentTime.day}/${_currentTime.month}/${_currentTime.year}';

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsetsDirectional.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: AppRadius.mdAll,
                ),
                child: const Icon(Icons.storefront_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'نظام متجر الجملة VIP POS',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'تسجيل الدخول السريع برمز PIN',
                    style: TextStyle(
                        fontSize: 11, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: AppSpacing.md, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: AppRadius.pillAll,
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_rounded, size: 14),
                    const SizedBox(width: 4),
                    Text('$timeStr • $dateStr',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Container(
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: AppSpacing.sm, vertical: 4),
                decoration: BoxDecoration(
                  color: context.appColors.success.withValues(alpha: 0.15),
                  borderRadius: AppRadius.pillAll,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: context.appColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'متصل (Online)',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.appColors.success,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSplitLayout(
    ThemeData theme,
    ColorScheme colorScheme,
    List<UserEntity> staffList,
  ) {
    return Row(
      children: [
        // Left/First Pane: Staff Selection Grid
        Expanded(
          flex: 5,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'اختر موظف الوردية:',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'اضغط على حسابك للدخول السريع أو تغيير الرمز السري',
                        style: TextStyle(
                            fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                      AppSpacing.gapMd,
                      TextField(
                        controller: _searchController,
                        onChanged: (val) => setState(() => _searchQuery = val),
                        decoration: InputDecoration(
                          hintText: 'بحث عن موظف بالاسم أو الهاتف...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          isDense: true,
                          contentPadding:
                              const EdgeInsetsDirectional.all(AppSpacing.md),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: staffList.isEmpty
                      ? Center(
                          child: Text(
                            'لم يتم العثور على أي موظف!',
                            style:
                                TextStyle(color: colorScheme.onSurfaceVariant),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsetsDirectional.symmetric(
                              horizontal: AppSpacing.lg),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 220,
                            mainAxisExtent: 110,
                            crossAxisSpacing: AppSpacing.md,
                            mainAxisSpacing: AppSpacing.md,
                          ),
                          itemCount: staffList.length,
                          itemBuilder: (context, index) {
                            final staff = staffList[index];
                            final isSelected = _selectedStaff?.id == staff.id;
                            return _buildStaffCard(
                                theme, colorScheme, staff, isSelected);
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
                  child: OutlinedButton.icon(
                    onPressed: _loginAsMasterModerator,
                    icon: const Icon(Icons.admin_panel_settings_outlined,
                        size: 18),
                    label: const Text('دخول سريع كمشرف عام (Master Moderator)'),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Right/Second Pane: PIN Keypad Terminal
        Expanded(
          flex: 4,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.all(AppSpacing.xl),
              child: ContentConstrainedBox.form(
                maxWidth: 360,
                child: _buildPinTerminalCard(theme, colorScheme),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactLayout(
    ThemeData theme,
    ColorScheme colorScheme,
    List<UserEntity> staffList,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      child: Center(
        child: ContentConstrainedBox.form(
          maxWidth: 400,
          child: Column(
            children: [
              // Staff Dropdown / Selector
              Container(
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: AppSpacing.md),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedStaff?.id,
                    items: staffList.map((staff) {
                      return DropdownMenuItem<String>(
                        value: staff.id,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: colorScheme.primaryContainer,
                              child: Icon(
                                _getRoleIcon(staff.role),
                                size: 16,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(staff.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13)),
                            const Spacer(),
                            Text(_getRoleLabel(staff.role),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        final staff = staffList.firstWhere((s) => s.id == val);
                        setState(() {
                          _selectedStaff = staff;
                          _errorMessage = null;
                          _pinController.clear();
                        });
                        _focusNode.requestFocus();
                      }
                    },
                  ),
                ),
              ),
              AppSpacing.gapLg,

              // PIN Terminal Card
              _buildPinTerminalCard(theme, colorScheme),
              AppSpacing.gapMd,

              OutlinedButton.icon(
                onPressed: _loginAsMasterModerator,
                icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                label: const Text('دخول سريع كمشرف عام'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStaffCard(
    ThemeData theme,
    ColorScheme colorScheme,
    UserEntity staff,
    bool isSelected,
  ) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedStaff = staff;
          _errorMessage = null;
          _pinController.clear();
        });
        _focusNode.requestFocus();
      },
      borderRadius: AppRadius.lgAll,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsetsDirectional.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.4)
              : colorScheme.surfaceContainer,
          borderRadius: AppRadius.lgAll,
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: isSelected
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest,
                  child: Icon(
                    _getRoleIcon(staff.role),
                    size: 18,
                    color: isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    staff.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w600,
                      fontSize: 13,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: AppRadius.pillAll,
                    ),
                    child: Text(
                      _getRoleLabel(staff.role),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10, color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  staff.phone,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinTerminalCard(ThemeData theme, ColorScheme colorScheme) {
    final staff = _selectedStaff;

    final defaultPinTheme = PinTheme(
      width: 58,
      height: 62,
      textStyle: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyWith(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colorScheme.primary, width: 2),
      ),
    );

    final errorPinTheme = defaultPinTheme.copyWith(
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colorScheme.error, width: 2),
      ),
    );

    return Card(
      elevation: 2,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Selected Staff Header
            if (staff != null) ...[
              Center(
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(
                    _getRoleIcon(staff.role),
                    size: 30,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              AppSpacing.gapSm,
              Text(
                staff.name,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: AppRadius.pillAll,
                    ),
                    child: Text(
                      _getRoleLabel(staff.role),
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Icon(Icons.lock_outline, size: 48, color: colorScheme.primary),
              AppSpacing.gapSm,
              const Text(
                'أدخل رمز PIN لتسجيل الدخول',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],

            AppSpacing.gapLg,

            // Pinput 4-Digit Field
            Directionality(
              textDirection: TextDirection.ltr,
              child: Pinput(
                controller: _pinController,
                focusNode: _focusNode,
                autofocus: true,
                length: 4,
                obscureText: true,
                obscuringCharacter: '●',
                defaultPinTheme: defaultPinTheme,
                focusedPinTheme: focusedPinTheme,
                errorPinTheme: errorPinTheme,
                hapticFeedbackType: HapticFeedbackType.mediumImpact,
                onCompleted: _handlePinLogin,
                onChanged: (_) {
                  if (_errorMessage != null) {
                    setState(() => _errorMessage = null);
                  }
                },
              ),
            ),

            // Error Message
            if (_errorMessage != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 14, color: colorScheme.error),
                  const SizedBox(width: 4),
                  Text(
                    _errorMessage!,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],

            AppSpacing.gapLg,

            // Virtual Keypad
            _buildKeypad(theme, colorScheme),

            AppSpacing.gapMd,

            // Change PIN Button
            TextButton.icon(
              onPressed: _openChangePinDialog,
              icon: const Icon(Icons.password_rounded, size: 16),
              label: const Text(
                'تغيير رمز PIN الخاص بي',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),

            if (_isAuthenticating) ...[
              AppSpacing.gapSm,
              const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildKeypad(ThemeData theme, ColorScheme colorScheme) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        children: [
          for (var row in [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['C', '0', '⌫'],
          ]) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((key) {
                final isAction = key == 'C' || key == '⌫';
                return Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: InkWell(
                    borderRadius: AppRadius.mdAll,
                    onTap: () {
                      if (key == 'C') {
                        _pinController.clear();
                        setState(() => _errorMessage = null);
                      } else if (key == '⌫') {
                        if (_pinController.text.isNotEmpty) {
                          _pinController.text = _pinController.text
                              .substring(0, _pinController.text.length - 1);
                        }
                      } else {
                        if (_pinController.text.length < 4) {
                          _pinController.text = _pinController.text + key;
                          if (_pinController.text.length == 4) {
                            _handlePinLogin(_pinController.text);
                          }
                        }
                      }
                    },
                    child: Container(
                      width: 76,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isAction
                            ? colorScheme.surfaceContainer
                            : colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.6),
                        borderRadius: AppRadius.mdAll,
                        border: Border.all(
                          color:
                              colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        key,
                        style: TextStyle(
                          fontSize: isAction ? 15 : 18,
                          fontWeight: FontWeight.bold,
                          color: isAction
                              ? colorScheme.error
                              : colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getRoleIcon(UserRole role) {
    switch (role) {
      case UserRole.cashier:
        return Icons.point_of_sale_rounded;
      case UserRole.manager:
        return Icons.inventory_2_rounded;
      case UserRole.moderator:
        return Icons.admin_panel_settings_rounded;
      case UserRole.driver:
        return Icons.local_shipping_rounded;
      case UserRole.customer:
        return Icons.person_rounded;
    }
  }

  String _getRoleLabel(UserRole role) {
    switch (role) {
      case UserRole.cashier:
        return 'كاشير';
      case UserRole.manager:
        return 'مدير المخزن';
      case UserRole.moderator:
        return 'مشرف عام';
      case UserRole.driver:
        return 'سائق توصيل';
      case UserRole.customer:
        return 'عميل';
    }
  }
}
