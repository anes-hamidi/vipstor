import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';
import 'package:domain/domain.dart';
import 'package:data/data.dart';
import 'package:ui_kit/ui_kit.dart';
import '../../providers/staff_providers.dart';
import '../../router/staff_router.dart';
import 'widgets/change_pin_dialog.dart';

/// Minimized, responsive, and tactile Login Screen for VIP Staff App.
///
/// Features:
/// - Disables native system keyboard pop-up (`useNativeKeyboard: false`).
/// - Full on-screen tactile numeric keypad with physical keyboard shortcut support.
/// - Adaptive responsive design for Desktop, Tablet, and Mobile.
/// - Minimalist VIP Gold & Obsidian visual styling.
/// - Real-time connection status and background OTA update checks.
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
  UserRole? _filterRole;

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
      _restoreLastStaffUser();
    });
  }

  Future<void> _restoreLastStaffUser() async {
    try {
      final lastUser =
          await ref.read(staffLocalAuthStoreProvider).getLastActiveUser();
      if (lastUser != null && mounted && _selectedStaff == null) {
        setState(() => _selectedStaff = lastUser);
      }
    } catch (_) {}
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

  void _pressKeypadKey(String key) {
    if (_isAuthenticating) return;

    if (key == 'C') {
      _pinController.clear();
      if (_errorMessage != null) {
        setState(() => _errorMessage = null);
      }
    } else if (key == 'back') {
      if (_pinController.text.isNotEmpty) {
        _pinController.text =
            _pinController.text.substring(0, _pinController.text.length - 1);
        if (_errorMessage != null) {
          setState(() => _errorMessage = null);
        }
      }
    } else {
      if (_pinController.text.length < 4) {
        _pinController.text = _pinController.text + key;
        if (_errorMessage != null) {
          setState(() => _errorMessage = null);
        }
        if (_pinController.text.length == 4) {
          _handlePinLogin(_pinController.text);
        }
      }
    }
  }

  Future<void> _handlePinLogin(String pin) async {
    if (pin.length < 4 || _isAuthenticating) return;
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
        final staff = _selectedStaff!;
        await ref.read(staffLocalAuthStoreProvider).saveLastActiveUser(staff);
        ref.read(staffAuditLoggerProvider).logLogin(user: staff);
        ref.read(authStateProvider.notifier).state = staff;
      } else {
        setState(() {
          _isAuthenticating = false;
          _errorMessage = 'رمز PIN غير صحيح!';
          _pinController.clear();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAuthenticating = false;
        _errorMessage = e
            .toString()
            .replaceFirst('AuthException: ', '')
            .replaceFirst('Exception: ', '');
        _pinController.clear();
      });
    }
  }

  void _openChangePinDialog() async {
    if (_selectedStaff == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('يرجى تحديد حساب الموظف أولاً!'),
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

  static IconData roleIcon(UserRole role) => switch (role) {
        UserRole.cashier => Icons.point_of_sale_rounded,
        UserRole.manager => Icons.inventory_2_rounded,
        UserRole.moderator => Icons.admin_panel_settings_rounded,
        UserRole.driver => Icons.local_shipping_rounded,
        _ => Icons.person_rounded,
      };

  static String roleLabel(UserRole role) => switch (role) {
        UserRole.cashier => 'كاشير',
        UserRole.manager => 'مدير المخزن',
        UserRole.moderator => 'مشرف عام',
        UserRole.driver => 'سائق توصيل',
        _ => 'موظف',
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final staffAsync = ref.watch(liveStaffUsersProvider);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 720;

    // Hardware Keyboard shortcuts
    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.backspace): () =>
          _pressKeypadKey('back'),
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          _pressKeypadKey('C'),
      const SingleActivator(LogicalKeyboardKey.delete): () =>
          _pressKeypadKey('C'),
      const SingleActivator(LogicalKeyboardKey.digit0): () =>
          _pressKeypadKey('0'),
      const SingleActivator(LogicalKeyboardKey.digit1): () =>
          _pressKeypadKey('1'),
      const SingleActivator(LogicalKeyboardKey.digit2): () =>
          _pressKeypadKey('2'),
      const SingleActivator(LogicalKeyboardKey.digit3): () =>
          _pressKeypadKey('3'),
      const SingleActivator(LogicalKeyboardKey.digit4): () =>
          _pressKeypadKey('4'),
      const SingleActivator(LogicalKeyboardKey.digit5): () =>
          _pressKeypadKey('5'),
      const SingleActivator(LogicalKeyboardKey.digit6): () =>
          _pressKeypadKey('6'),
      const SingleActivator(LogicalKeyboardKey.digit7): () =>
          _pressKeypadKey('7'),
      const SingleActivator(LogicalKeyboardKey.digit8): () =>
          _pressKeypadKey('8'),
      const SingleActivator(LogicalKeyboardKey.digit9): () =>
          _pressKeypadKey('9'),
      const SingleActivator(LogicalKeyboardKey.numpad0): () =>
          _pressKeypadKey('0'),
      const SingleActivator(LogicalKeyboardKey.numpad1): () =>
          _pressKeypadKey('1'),
      const SingleActivator(LogicalKeyboardKey.numpad2): () =>
          _pressKeypadKey('2'),
      const SingleActivator(LogicalKeyboardKey.numpad3): () =>
          _pressKeypadKey('3'),
      const SingleActivator(LogicalKeyboardKey.numpad4): () =>
          _pressKeypadKey('4'),
      const SingleActivator(LogicalKeyboardKey.numpad5): () =>
          _pressKeypadKey('5'),
      const SingleActivator(LogicalKeyboardKey.numpad6): () =>
          _pressKeypadKey('6'),
      const SingleActivator(LogicalKeyboardKey.numpad7): () =>
          _pressKeypadKey('7'),
      const SingleActivator(LogicalKeyboardKey.numpad8): () =>
          _pressKeypadKey('8'),
      const SingleActivator(LogicalKeyboardKey.numpad9): () =>
          _pressKeypadKey('9'),
    };

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: true,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: colors.obsidian,
            body: SafeArea(
              child: Column(
                children: [
                  _buildTopBar(colors),
                  Divider(
                      color: colors.goldBorder.withValues(alpha: 0.35),
                      height: 1),
                  Expanded(
                    child: staffAsync.when(
                      data: (staffList) {
                        final activeStaff =
                            staffList.where((u) => u.active).toList();

                        // Pre-select staff if none selected
                        if (_selectedStaff == null && activeStaff.isNotEmpty) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted && _selectedStaff == null) {
                              setState(
                                  () => _selectedStaff = activeStaff.first);
                            }
                          });
                        }

                        // Apply search & role filters
                        final filtered = activeStaff.where((u) {
                          final matchesSearch = _searchQuery.isEmpty ||
                              u.name
                                  .toLowerCase()
                                  .contains(_searchQuery.toLowerCase()) ||
                              u.phone.contains(_searchQuery);
                          final matchesRole =
                              _filterRole == null || u.role == _filterRole;
                          return matchesSearch && matchesRole;
                        }).toList();

                        return isWide
                            ? _buildDesktopLayout(colors, activeStaff, filtered)
                            : _buildMobileLayout(colors, activeStaff);
                      },
                      loading: () => Center(
                        child: AppStates.loading(
                            message: 'جاري تحميل طاقم العمل...'),
                      ),
                      error: (err, _) => Center(
                        child: AppStates.error(
                          'تعذر الاتصال بالخادم وتحميل بيانات الموظفين',
                          onRetry: () => ref.invalidate(liveStaffUsersProvider),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TOP BAR
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildTopBar(AppColors colors) {
    final t = _currentTime;
    final timeStr =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
    final isOnline = ConnectivityService.instance.isOnline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: colors.obsidianSurface,
      child: Row(
        children: [
          // VIP Logo Emblem
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: AppGradients.gold,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [AppShadows.goldGlowSm],
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: Color(0xFF1A1400),
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'منظومة متجر الجملة VIP',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: colors.onGold,
                  ),
                ),
                Text(
                  'تسجيل دخول الموظفين برمز PIN',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: colors.onGold.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),

          // Online / Offline Status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (isOnline ? colors.success : colors.warning)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: (isOnline ? colors.success : colors.warning)
                    .withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isOnline ? colors.success : colors.warning,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  isOnline ? 'متصل' : 'محلي (Offline)',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isOnline ? colors.success : colors.warning,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Clock Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colors.obsidianCard,
              borderRadius: BorderRadius.circular(6),
              border:
                  Border.all(color: colors.goldBorder.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.access_time_rounded, size: 12, color: colors.gold),
                const SizedBox(width: 5),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: colors.gold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // DESKTOP / TABLET DUAL-PANE LAYOUT
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildDesktopLayout(
    AppColors colors,
    List<UserEntity> allStaff,
    List<UserEntity> filteredStaff,
  ) {
    return Row(
      children: [
        // Staff Directory (Right in LTR, Left in RTL)
        Expanded(
          flex: 5,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left:
                    BorderSide(color: colors.goldBorder.withValues(alpha: 0.35)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'طاقم العمل والورديات',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: colors.onGold,
                            ),
                          ),
                          Text(
                            '${filteredStaff.length} موظف',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colors.gold,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Search input
                      TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _searchQuery = v),
                        style: TextStyle(fontSize: 12.5, color: colors.onGold),
                        decoration: InputDecoration(
                          hintText: 'ابحث عن موظف بالاسم أو الهاتف...',
                          hintStyle: TextStyle(
                            fontSize: 11.5,
                            color: colors.onGold.withValues(alpha: 0.45),
                          ),
                          prefixIcon: Icon(Icons.search_rounded,
                              size: 17, color: colors.gold),
                          isDense: true,
                          filled: true,
                          fillColor: colors.obsidianSurface,
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: colors.goldBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color: colors.goldBorder.withValues(alpha: 0.4)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                BorderSide(color: colors.gold, width: 1.5),
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 15),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Role filter chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip(colors, label: 'الكل', role: null),
                            const SizedBox(width: 6),
                            _buildFilterChip(colors,
                                label: 'كاشير', role: UserRole.cashier),
                            const SizedBox(width: 6),
                            _buildFilterChip(colors,
                                label: 'مدير مخزن', role: UserRole.manager),
                            const SizedBox(width: 6),
                            _buildFilterChip(colors,
                                label: 'مشرف عام', role: UserRole.moderator),
                            const SizedBox(width: 6),
                            _buildFilterChip(colors,
                                label: 'سائق', role: UserRole.driver),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                    color: colors.goldBorder.withValues(alpha: 0.25),
                    height: 1),

                // Staff Cards Grid
                Expanded(
                  child: filteredStaff.isEmpty
                      ? Center(
                          child: Text(
                            'لم يتم العثور على موظف مطابق',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.onGold.withValues(alpha: 0.5),
                            ),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(14),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 210,
                            mainAxisExtent: 82,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: filteredStaff.length,
                          itemBuilder: (_, i) =>
                              _buildStaffCard(colors, filteredStaff[i]),
                        ),
                ),
              ],
            ),
          ),
        ),

        // PIN Terminal Pane
        Expanded(
          flex: 4,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: _buildPinTerminalCard(colors),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(AppColors colors,
      {required String label, required UserRole? role}) {
    final isSelected = _filterRole == role;
    return InkWell(
      onTap: () => setState(() => _filterRole = role),
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.gold.withValues(alpha: 0.18)
              : colors.obsidianCard,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? colors.gold
                : colors.goldBorder.withValues(alpha: 0.4),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color:
                isSelected ? colors.gold : colors.onGold.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }

  Widget _buildStaffCard(AppColors colors, UserEntity staff) {
    final isSelected = _selectedStaff?.id == staff.id;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedStaff = staff;
          _errorMessage = null;
          _pinController.clear();
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.gold.withValues(alpha: 0.12)
              : colors.obsidianSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? colors.gold
                : colors.goldBorder.withValues(alpha: 0.4),
            width: isSelected ? 1.6 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: colors.gold.withValues(alpha: 0.18),
                    blurRadius: 10,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isSelected ? AppGradients.gold : null,
                color: isSelected ? null : colors.obsidianCard,
                border: Border.all(
                  color: isSelected
                      ? colors.gold
                      : colors.goldBorder.withValues(alpha: 0.6),
                ),
              ),
              child: Icon(
                roleIcon(staff.role),
                size: 15,
                color: isSelected ? const Color(0xFF1A1400) : colors.gold,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    staff.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected ? colors.gold : colors.onGold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    roleLabel(staff.role),
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.onGold.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: colors.gold, size: 15),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // MOBILE SINGLE-PANE LAYOUT
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildMobileLayout(AppColors colors, List<UserEntity> staffList) {
    return Center(
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Mobile Staff Selector Bar
              _buildMobileStaffSelector(colors, staffList),
              const SizedBox(height: 12),

              // PIN Terminal Card
              _buildPinTerminalCard(colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileStaffSelector(
      AppColors colors, List<UserEntity> staffList) {
    final staff = _selectedStaff;

    return InkWell(
      onTap: () => _showStaffPickerBottomSheet(colors, staffList),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.obsidianSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.goldBorder.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppGradients.gold,
              ),
              child: Icon(
                staff != null ? roleIcon(staff.role) : Icons.person_rounded,
                size: 16,
                color: const Color(0xFF1A1400),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    staff?.name ?? 'اضغط لاختيار الموظف',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: colors.onGold,
                    ),
                  ),
                  if (staff != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      roleLabel(staff.role),
                      style: TextStyle(
                        fontSize: 10,
                        color: colors.gold,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: colors.gold.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colors.gold.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_horiz_rounded, size: 13, color: colors.gold),
                  const SizedBox(width: 4),
                  Text(
                    'تبديل',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: colors.gold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showStaffPickerBottomSheet(
      AppColors colors, List<UserEntity> staffList) {
    String query = '';
    UserRole? roleFilter;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.obsidianSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = staffList.where((u) {
              final matchesQuery = query.isEmpty ||
                  u.name.toLowerCase().contains(query.toLowerCase()) ||
                  u.phone.contains(query);
              final matchesRole = roleFilter == null || u.role == roleFilter;
              return matchesQuery && matchesRole;
            }).toList();

            return Directionality(
              textDirection: TextDirection.rtl,
              child: Container(
                height: MediaQuery.sizeOf(context).height * 0.70,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'اختر موظف الوردية',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: colors.onGold,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded,
                              size: 18,
                              color: colors.onGold.withValues(alpha: 0.6)),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Search field
                    TextField(
                      onChanged: (v) => setSheetState(() => query = v),
                      style: TextStyle(fontSize: 12.5, color: colors.onGold),
                      decoration: InputDecoration(
                        hintText: 'بحث عن موظف بالاسم أو الهاتف...',
                        hintStyle: TextStyle(
                          fontSize: 11.5,
                          color: colors.onGold.withValues(alpha: 0.45),
                        ),
                        prefixIcon: Icon(Icons.search_rounded,
                            size: 16, color: colors.gold),
                        isDense: true,
                        filled: true,
                        fillColor: colors.obsidianCard,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: colors.goldBorder),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Role filter chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildSheetFilterChip(colors, 'الكل', null,
                              roleFilter, (r) => setSheetState(() => roleFilter = r)),
                          const SizedBox(width: 6),
                          _buildSheetFilterChip(colors, 'كاشير',
                              UserRole.cashier, roleFilter,
                              (r) => setSheetState(() => roleFilter = r)),
                          const SizedBox(width: 6),
                          _buildSheetFilterChip(colors, 'مدير مخزن',
                              UserRole.manager, roleFilter,
                              (r) => setSheetState(() => roleFilter = r)),
                          const SizedBox(width: 6),
                          _buildSheetFilterChip(colors, 'مشرف عام',
                              UserRole.moderator, roleFilter,
                              (r) => setSheetState(() => roleFilter = r)),
                          const SizedBox(width: 6),
                          _buildSheetFilterChip(colors, 'سائق',
                              UserRole.driver, roleFilter,
                              (r) => setSheetState(() => roleFilter = r)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Staff List
                    Expanded(
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final s = filtered[i];
                          final isSelected = _selectedStaff?.id == s.id;

                          return ListTile(
                            dense: true,
                            onTap: () {
                              setState(() {
                                _selectedStaff = s;
                                _errorMessage = null;
                                _pinController.clear();
                              });
                              Navigator.of(ctx).pop();
                            },
                            tileColor: isSelected
                                ? colors.gold.withValues(alpha: 0.12)
                                : colors.obsidianCard,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: isSelected
                                    ? colors.gold
                                    : colors.goldBorder
                                        .withValues(alpha: 0.3),
                              ),
                            ),
                            leading: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient:
                                    isSelected ? AppGradients.gold : null,
                                color:
                                    isSelected ? null : colors.obsidianSurface,
                              ),
                              child: Icon(
                                roleIcon(s.role),
                                size: 16,
                                color: isSelected
                                    ? const Color(0xFF1A1400)
                                    : colors.gold,
                              ),
                            ),
                            title: Text(
                              s.name,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: isSelected ? colors.gold : colors.onGold,
                              ),
                            ),
                            subtitle: Text(
                              '${roleLabel(s.role)} • ${s.phone}',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: colors.onGold.withValues(alpha: 0.6),
                              ),
                            ),
                            trailing: isSelected
                                ? Icon(Icons.check_circle_rounded,
                                    color: colors.gold, size: 16)
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSheetFilterChip(
    AppColors colors,
    String label,
    UserRole? role,
    UserRole? activeRole,
    ValueChanged<UserRole?> onSelect,
  ) {
    final isSelected = activeRole == role;
    return InkWell(
      onTap: () => onSelect(role),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.gold.withValues(alpha: 0.2)
              : colors.obsidianCard,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? colors.gold
                : colors.goldBorder.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color:
                isSelected ? colors.gold : colors.onGold.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // PIN TERMINAL CARD & KEYPAD
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildPinTerminalCard(AppColors colors) {
    final staff = _selectedStaff;

    final pinBase = PinTheme(
      width: 46,
      height: 48,
      textStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: colors.gold,
      ),
      decoration: BoxDecoration(
        color: colors.obsidianCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.goldBorder.withValues(alpha: 0.6)),
      ),
    );

    final pinFocused = pinBase.copyWith(
      decoration: BoxDecoration(
        color: colors.obsidianCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.gold, width: 1.8),
        boxShadow: const [AppShadows.goldGlowSm],
      ),
    );

    final pinError = pinBase.copyWith(
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.error, width: 1.8),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: colors.obsidianSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.goldBorder.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Active Staff Avatar & Identity
          if (staff != null) ...[
            Center(
              child: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppGradients.gold,
                  boxShadow: [AppShadows.goldGlowSm],
                ),
                child: Icon(
                  roleIcon(staff.role),
                  size: 24,
                  color: const Color(0xFF1A1400),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              staff.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: colors.onGold,
              ),
            ),
            const SizedBox(height: 3),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  roleLabel(staff.role),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: colors.gold,
                  ),
                ),
              ),
            ),
          ] else ...[
            Center(
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.obsidianCard,
                  border: Border.all(color: colors.goldBorder),
                ),
                child: Icon(Icons.lock_outline_rounded,
                    size: 24, color: colors.gold),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'تسجيل الدخول',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: colors.onGold,
              ),
            ),
          ],

          const SizedBox(height: 10),
          Text(
            'أدخل رمز PIN لتسجيل الدخول',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: colors.onGold.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 10),

          // Pinput Display (Native Keyboard Suppressed)
          Center(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Pinput(
                controller: _pinController,
                focusNode: _focusNode,
                autofocus: false,
                useNativeKeyboard: false, // Prevents system keyboard from popping up
                showCursor: false,
                length: 4,
                obscureText: true,
                obscuringCharacter: '◆',
                defaultPinTheme: pinBase,
                focusedPinTheme: pinFocused,
                errorPinTheme: pinError,
                hapticFeedbackType: HapticFeedbackType.mediumImpact,
                onCompleted: _handlePinLogin,
                onChanged: (_) {
                  if (_errorMessage != null) {
                    setState(() => _errorMessage = null);
                  }
                },
              ),
            ),
          ),

          // Error notification banner
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline_rounded,
                    size: 13, color: colors.error),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: colors.error,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 12),

          // Virtual Numeric Keypad
          _buildNumericKeypad(colors),

          const SizedBox(height: 6),

          // Actions / Change PIN
          Center(
            child: TextButton.icon(
              onPressed: _openChangePinDialog,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              icon: Icon(Icons.password_rounded, size: 14, color: colors.gold),
              label: Text(
                'تغيير رمز PIN',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: colors.gold,
                ),
              ),
            ),
          ),

          if (_isAuthenticating) ...[
            const SizedBox(height: 6),
            Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.gold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNumericKeypad(AppColors colors) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['C', '0', 'back'],
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Column(
        children: rows.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((k) {
                final isAction = k == 'C' || k == 'back';
                return _KeypadButton(
                  label: k,
                  isAction: isAction,
                  colors: colors,
                  onTap: () => _pressKeypadKey(k),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _KeypadButton extends StatefulWidget {
  final String label;
  final bool isAction;
  final AppColors colors;
  final VoidCallback onTap;

  const _KeypadButton({
    required this.label,
    required this.isAction,
    required this.colors,
    required this.onTap,
  });

  @override
  State<_KeypadButton> createState() => _KeypadButtonState();
}

class _KeypadButtonState extends State<_KeypadButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;

    Widget childWidget;
    if (widget.label == 'back') {
      childWidget =
          Icon(Icons.backspace_outlined, size: 17, color: colors.gold);
    } else if (widget.label == 'C') {
      childWidget = Text(
        'مسح',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: colors.error,
        ),
      );
    } else {
      childWidget = Text(
        widget.label,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: colors.onGold,
        ),
      );
    }

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
            width: 70,
            height: 44,
            decoration: BoxDecoration(
              color: widget.isAction
                  ? colors.obsidianSurface
                  : (_ctrl.value > 0.5
                      ? colors.gold.withValues(alpha: 0.15)
                      : colors.obsidianCard),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.isAction
                    ? colors.goldBorder.withValues(alpha: 0.35)
                    : (_ctrl.value > 0.5 ? colors.gold : colors.goldBorder),
              ),
              boxShadow: _ctrl.value > 0.5
                  ? [
                      BoxShadow(
                        color: colors.gold.withValues(alpha: 0.25),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: childWidget,
          ),
        ),
      ),
    );
  }
}
