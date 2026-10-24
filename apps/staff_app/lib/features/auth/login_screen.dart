import 'dart:async';
// ignore_for_file: invalid_use_of_protected_member
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';
import 'package:domain/domain.dart';
import 'package:data/data.dart';
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
      if (mounted) setState(() => _currentTime = DateTime.now());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAppUpdates();
    });
  }

  Future<void> _checkAppUpdates() async {
    try {
      final res = await ref.read(appUpdateServiceProvider).checkForUpdate();
      if (res.hasUpdate && mounted && res.newRelease != null) {
        final service = ref.read(appUpdateServiceProvider);
        AppUpdateDialog.show(
          context,
          release: res.newRelease!,
          currentVersion: res.currentVersion,
          currentBuild: res.currentBuild,
          updateService: service,
          force: res.isForceUpdate,
        );
      }
    } catch (e) {
      debugPrint('[Login] Error checking updates: $e');
    }
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    _pinController.dispose();
    _focusNode.dispose();
    _searchController.dispose();
    super.dispose();
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
          userId: _selectedStaff!.id, pin: pin);
      if (!mounted) return;
      if (isValid) {
        final staff = _selectedStaff!;
        ref.read(staffLocalAuthStoreProvider).saveLastActiveUser(staff);
        ref.read(staffAuditLoggerProvider).logLogin(user: staff);
        ref.read(authStateProvider.notifier).state = staff;
      } else {
        setState(() {
          _isAuthenticating = false;
          _errorMessage = 'رمز PIN غير صحيح!';
          _pinController.clear();
        });
        _focusNode.requestFocus();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAuthenticating = false;
        // Surface the real message (e.g. "account locked") rather than a generic one
        _errorMessage = e.toString().replaceFirst('AuthException: ', '').replaceFirst('Exception: ', '');
        _pinController.clear();
      });
      _focusNode.requestFocus();
    }
  }

  void _openChangePinDialog() async {
    if (_selectedStaff == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('يرجى تحديد حساب الموظف أولاً!'),
        backgroundColor: context.appColors.warning,
      ));
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
    final isDark = theme.brightness == Brightness.dark;
    final staffAsync = ref.watch(liveStaffUsersProvider);
    final isCompact = MediaQuery.sizeOf(context).width < 720;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0908) : const Color(0xFFFAF7EE),
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(currentTime: _currentTime, isDark: isDark),
            Container(
              height: 1,
              decoration: const BoxDecoration(
                gradient: AppGradients.goldBorder,
              ),
            ),
            Expanded(
              child: staffAsync.when(
                data: (staffList) {
                  final active = staffList.where((u) => u.active).toList();
                  if (_selectedStaff == null && active.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _selectedStaff == null) {
                        setState(() => _selectedStaff = active.first);
                      }
                    });
                  }
                  final filtered = active.where((u) {
                    if (_searchQuery.isEmpty) return true;
                    return u.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                        u.phone.contains(_searchQuery);
                  }).toList();
                  return isCompact
                      ? _CompactLayout(
                          state: this,
                          staffList: filtered,
                          isDark: isDark,
                        )
                      : _SplitLayout(
                          state: this,
                          staffList: filtered,
                          isDark: isDark,
                        );
                },
                loading: () => Center(child: AppStates.loading(message: 'جاري تحميل طاقم العمل...')),
                error: (err, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppStates.error('تعذر الاتصال بالخادم',
                          onRetry: () => ref.invalidate(liveStaffUsersProvider)),
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

  // ── helpers ────────────────────────────────────────────────────────────────

  static IconData roleIcon(UserRole role) => switch (role) {
        UserRole.cashier   => Icons.point_of_sale_rounded,
        UserRole.manager   => Icons.inventory_2_rounded,
        UserRole.moderator => Icons.admin_panel_settings_rounded,
        UserRole.driver    => Icons.local_shipping_rounded,
        _                  => Icons.person_rounded,
      };

  static String roleLabel(UserRole role) => switch (role) {
        UserRole.cashier   => 'كاشير',
        UserRole.manager   => 'مدير المخزن',
        UserRole.moderator => 'مشرف عام',
        UserRole.driver    => 'سائق توصيل',
        _                  => 'عميل',
      };
}

// ── Top Bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final DateTime currentTime;
  final bool isDark;
  const _TopBar({required this.currentTime, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = currentTime;
    final timeStr =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      color: isDark ? const Color(0xFF141210) : const Color(0xFFFFFDF8),
      child: Row(
        children: [
          // VIP brand logo
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppGradients.gold,
              borderRadius: AppRadius.smAll,
              boxShadow: [AppShadows.goldGlowSm],
            ),
            child: Padding(
              padding: EdgeInsets.all(7),
              child: Icon(Icons.storefront_rounded,
                  color: Color(0xFF1A1400), size: 22),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'نظام متجر الجملة VIP POS',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 0.2),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                Text(
                  'تسجيل الدخول السريع برمز PIN',
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? const Color(0xFFB8A882)
                          : const Color(0xFF9A8A60)),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (!ConnectivityService.instance.isOnline) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: AppRadius.pillAll,
                border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.wifi_off_rounded, size: 14, color: Colors.orange),
                  SizedBox(width: 4),
                  Text(
                    'غير متصل (Offline)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          // Clock pill
          Container(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.sm, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2518) : const Color(0xFFF3E8C8),
              borderRadius: AppRadius.pillAll,
              border: Border.all(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.30),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.access_time_rounded,
                    size: 13,
                    color: isDark
                        ? const Color(0xFFF3D278)
                        : const Color(0xFFC59B27)),
                const SizedBox(width: 4),
                Text(timeStr,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? const Color(0xFFF3D278)
                          : const Color(0xFF9A7319),
                    )),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // Online indicator
          _LiveDot(),
        ],
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colors.success.withValues(alpha: 0.12),
          borderRadius: AppRadius.pillAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.success,
                boxShadow: [
                  BoxShadow(
                    color: colors.success
                        .withValues(alpha: 0.30 + 0.30 * _ctrl.value),
                    blurRadius: 4 + 4 * _ctrl.value,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 5),
            Text('متصل',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: colors.success)),
          ],
        ),
      ),
    );
  }
}

// ── Split Layout ──────────────────────────────────────────────────────────────

class _SplitLayout extends StatelessWidget {
  final _LoginScreenState state;
  final List<UserEntity> staffList;
  final bool isDark;

  const _SplitLayout({
    required this.state,
    required this.staffList,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        // Staff grid pane
        Expanded(
          flex: 5,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: const Color(0xFFD4AF37)
                      .withValues(alpha: isDark ? 0.15 : 0.12),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                      AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'اختر موظف الوردية'),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'اضغط على حسابك ثم أدخل رمز PIN للدخول',
                        style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? const Color(0xFFB8A882)
                                : const Color(0xFF9A8A60)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      // Search field
                      TextField(
                        controller: state._searchController,
                        onChanged: (v) =>
                            state.setState(() => state._searchQuery = v),
                        decoration: InputDecoration(
                          hintText: 'بحث عن موظف...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          isDense: true,
                          suffixIcon: state._searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    state._searchController.clear();
                                    state.setState(() => state._searchQuery = '');
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
                          child: Text('لا يوجد موظفون',
                              style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        )
                      : GridView.builder(
                          padding: const EdgeInsetsDirectional.symmetric(
                              horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 220,
                            mainAxisExtent: 110,
                            crossAxisSpacing: AppSpacing.md,
                            mainAxisSpacing: AppSpacing.md,
                          ),
                          itemCount: staffList.length,
                          itemBuilder: (_, i) => _StaffCard(
                            staff: staffList[i],
                            isSelected:
                                state._selectedStaff?.id == staffList[i].id,
                            isDark: isDark,
                            onTap: () => state.setState(() {
                              state._selectedStaff = staffList[i];
                              state._errorMessage = null;
                              state._pinController.clear();
                              state._focusNode.requestFocus();
                            }),
                          ),
                        ),
                ),

        // PIN terminal pane
        Expanded(
          flex: 4,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: _PinTerminalCard(state: state, isDark: isDark),
              ),
            ),
          ),
        ),
      ],
     
       

    )
          )
        )
      ]
    );
    
  }

}

// ── Compact Layout ────────────────────────────────────────────────────────────

class _CompactLayout extends StatelessWidget {
  final _LoginScreenState state;
  final List<UserEntity> staffList;
  final bool isDark;

  const _CompactLayout({
    required this.state,
    required this.staffList,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            children: [
              // Staff dropdown
              Container(
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: AppSpacing.md),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1814) : const Color(0xFFFFFDF8),
                  borderRadius: AppRadius.lgAll,
                  border: Border.all(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: state._selectedStaff?.id,
                    items: staffList
                        .map((s) => DropdownMenuItem<String>(
                              value: s.id,
                              child: Row(
                                children: [
                                  Icon(
                                    _LoginScreenState.roleIcon(s.role),
                                    size: 16,
                                    color: const Color(0xFFD4AF37),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Text(s.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13)),
                                  const Spacer(),
                                  Text(_LoginScreenState.roleLabel(s.role),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: cs.onSurfaceVariant)),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        final s = staffList.firstWhere((x) => x.id == val);
                        state.setState(() {
                          state._selectedStaff = s;
                          state._errorMessage = null;
                          state._pinController.clear();
                        });
                        state._focusNode.requestFocus();
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _PinTerminalCard(state: state, isDark: isDark),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Staff Card ────────────────────────────────────────────────────────────────

class _StaffCard extends StatelessWidget {
  final UserEntity staff;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _StaffCard({
    required this.staff,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LuxuryCard(
      selected: isSelected,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                // Role avatar
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: isSelected ? AppGradients.gold : null,
                    color: isSelected
                        ? null
                        : (isDark
                            ? const Color(0xFF2A2518)
                            : const Color(0xFFF3E8C8)),
                    borderRadius: AppRadius.smAll,
                    boxShadow: isSelected ? [AppShadows.goldGlowSm] : null,
                  ),
                  child: Icon(
                    _LoginScreenState.roleIcon(staff.role),
                    size: 18,
                    color: isSelected
                        ? const Color(0xFF1A1400)
                        : (isDark
                            ? const Color(0xFFF3D278)
                            : const Color(0xFFC59B27)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    staff.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      fontSize: 13,
                      color: isSelected
                          ? (isDark
                              ? const Color(0xFFF3D278)
                              : const Color(0xFF9A7319))
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF2A2518)
                        : const Color(0xFFF3E8C8),
                    borderRadius: AppRadius.pillAll,
                  ),
                  child: Text(
                    _LoginScreenState.roleLabel(staff.role),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? const Color(0xFFF3D278)
                          : const Color(0xFFC59B27),
                    ),
                  ),
                ),
                Text(
                  staff.phone,
                  style: TextStyle(
                      fontSize: 9,
                      color: isDark
                          ? const Color(0xFFB8A882)
                          : const Color(0xFF9A8A60)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── PIN Terminal Card ─────────────────────────────────────────────────────────

class _PinTerminalCard extends StatelessWidget {
  final _LoginScreenState state;
  final bool isDark;
  const _PinTerminalCard({required this.state, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final staff = state._selectedStaff;

    // Gold PIN theme
    final pinBase = PinTheme(
      width: 58,
      height: 62,
      textStyle: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: isDark ? const Color(0xFFF3D278) : const Color(0xFF9A7319),
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF232018) : const Color(0xFFF5EDD8),
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: isDark ? 0.25 : 0.20),
          width: 1,
        ),
      ),
    );

    final pinFocused = pinBase.copyWith(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2518) : const Color(0xFFFBF4DC),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: const Color(0xFFD4AF37), width: 2),
        boxShadow: const [AppShadows.goldGlowSm],
      ),
    );

    final pinError = pinBase.copyWith(
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.30),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: cs.error, width: 2),
      ),
    );

    return LuxuryCard(
      goldAccent: true,
      padding: const EdgeInsetsDirectional.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Staff avatar + name
          if (staff != null) ...[
            Center(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: AppGradients.gold,
                  shape: BoxShape.circle,
                  boxShadow: [AppShadows.goldGlow],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Icon(
                    _LoginScreenState.roleIcon(staff.role),
                    size: 28,
                    color: const Color(0xFF1A1400),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              staff.name,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Center(
              child: GoldBadge(
                label: _LoginScreenState.roleLabel(staff.role),
                icon: _LoginScreenState.roleIcon(staff.role),
                small: true,
              ),
            ),
          ] else ...[
            Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2A2518)
                      : const Color(0xFFF3E8C8),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.30),
                  ),
                ),
                child: const Icon(Icons.lock_outline_rounded,
                    size: 28, color: Color(0xFFD4AF37)),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'أدخل رمز PIN لتسجيل الدخول',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],

          const SizedBox(height: AppSpacing.xl),

          // PIN field
          Center(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Pinput(
                controller: state._pinController,
                focusNode: state._focusNode,
                autofocus: true,
                length: 4,
                obscureText: true,
                obscuringCharacter: '◆',
                defaultPinTheme: pinBase,
                focusedPinTheme: pinFocused,
                errorPinTheme: pinError,
                hapticFeedbackType: HapticFeedbackType.mediumImpact,
                onCompleted: state._handlePinLogin,
                onChanged: (_) {
                  if (state._errorMessage != null) {
                    state.setState(() => state._errorMessage = null);
                  }
                },
              ),
            ),
          ),

          // Error
          if (state._errorMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline_rounded, size: 14, color: cs.error),
                const SizedBox(width: 4),
                Text(state._errorMessage!,
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.error,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ],

          const SizedBox(height: AppSpacing.xl),

          // Virtual keypad
          _GoldKeypad(state: state, isDark: isDark),

          const SizedBox(height: AppSpacing.md),

          // Change PIN
          Center(
            child: TextButton.icon(
              onPressed: state._openChangePinDialog,
              icon: Icon(Icons.password_rounded,
                  size: 15,
                  color: isDark
                      ? const Color(0xFFF3D278)
                      : const Color(0xFFC59B27)),
              label: Text(
                'تغيير رمز PIN',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? const Color(0xFFF3D278)
                      : const Color(0xFFC59B27),
                ),
              ),
            ),
          ),

          if (state._isAuthenticating) ...[
            const SizedBox(height: AppSpacing.sm),
            const Center(
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child:
                      CircularProgressIndicator.adaptive(strokeWidth: 2)),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Gold Keypad ───────────────────────────────────────────────────────────────

class _GoldKeypad extends StatelessWidget {
  final _LoginScreenState state;
  final bool isDark;
  const _GoldKeypad({required this.state, required this.isDark});

  void _press(String key) {
    if (key == 'C') {
      state._pinController.clear();
      state.setState(() => state._errorMessage = null);
    } else if (key == '⌫') {
      if (state._pinController.text.isNotEmpty) {
        state._pinController.text = state._pinController.text
            .substring(0, state._pinController.text.length - 1);
      }
    } else {
      if (state._pinController.text.length < 4) {
        state._pinController.text = state._pinController.text + key;
        if (state._pinController.text.length == 4) {
          state._handlePinLogin(state._pinController.text);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['C', '0', '⌫'],
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        children: rows
            .map((row) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: row.map((key) {
                      final isAction = key == 'C' || key == '⌫';
                      return _KeyButton(
                        label: key,
                        isAction: isAction,
                        isDark: isDark,
                        onTap: () => _press(key),
                      );
                    }).toList(),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _KeyButton extends StatefulWidget {
  final String label;
  final bool isAction;
  final bool isDark;
  final VoidCallback onTap;
  const _KeyButton(
      {required this.label,
      required this.isAction,
      required this.isDark,
      required this.onTap});

  @override
  State<_KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<_KeyButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Transform.scale(
          scale: 1.0 - 0.05 * _ctrl.value,
          child: Container(
            width: 76,
            height: 50,
            decoration: BoxDecoration(
              gradient: !widget.isAction && _ctrl.value > 0.5
                  ? AppGradients.goldSubtleLight
                  : null,
              color: widget.isAction
                  ? (widget.isDark
                      ? const Color(0xFF2A2518)
                      : const Color(0xFFF3E8C8))
                  : (widget.isDark
                      ? const Color(0xFF232018)
                      : const Color(0xFFFFFDF8)),
              borderRadius: AppRadius.mdAll,
              border: Border.all(
                color: const Color(0xFFD4AF37)
                    .withValues(alpha: widget.isDark ? 0.20 : 0.15),
                width: 1,
              ),
              boxShadow: _ctrl.value > 0.5
                  ? [AppShadows.goldGlowSm]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: widget.isAction ? 16 : 20,
                fontWeight: FontWeight.bold,
                color: widget.isAction
                    ? cs.error
                    : (widget.isDark
                        ? const Color(0xFFFBF8F0)
                        : const Color(0xFF1E1B14)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
