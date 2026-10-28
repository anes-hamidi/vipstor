import 'dart:async';

import 'package:core/core.dart' show themeModeProvider, Success, FailureResult;
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../providers/staff_providers.dart';
import '../../router/staff_router.dart';
import 'widgets/auth_theme.dart';
import 'widgets/change_pin_dialog.dart';

/// Tactile staff sign-in terminal.
///
/// The screen is fully themed: every surface, border, glow and text colour is
/// derived from the active [ColorScheme] and role accent, so it stays legible
/// in light and dark mode and follows the workspace palette. The on-screen
/// keypad remains the only PIN entry surface (the native keyboard is disabled)
/// while physical keyboard shortcuts stay available for desktop terminals.
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
        _pinController.text = _pinController.text.substring(
          0,
          _pinController.text.length - 1,
        );
        if (_errorMessage != null) {
          setState(() => _errorMessage = null);
        }
      }
    } else if (_pinController.text.length < 4) {
      _pinController.text = _pinController.text + key;
      if (_errorMessage != null) {
        setState(() => _errorMessage = null);
      }
      if (_pinController.text.length == 4) {
        _handlePinLogin(_pinController.text);
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
      final result = await repo.verifyPin(
        userId: _selectedStaff!.id,
        pin: pin,
      );

      if (!mounted) return;

      switch (result) {
        case Success(:final value) when value:
          final staff = _selectedStaff!;
          await ref.read(staffLocalAuthStoreProvider).saveLastActiveUser(staff);
          ref.read(staffAuditLoggerProvider).logLogin(user: staff);
          ref.read(authStateProvider.notifier).state = staff;
        case Success():
          setState(() {
            _isAuthenticating = false;
            _errorMessage = 'رمز PIN غير صحيح!';
            _pinController.clear();
          });
        case FailureResult(:final error):
          setState(() {
            _isAuthenticating = false;
            _errorMessage = error.message;
            _pinController.clear();
          });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAuthenticating = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _pinController.clear();
      });
    }
  }

  void _openChangePinDialog() {
    if (_selectedStaff == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تحديد حساب الموظف أولاً!')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => ChangePinDialog(staffMember: _selectedStaff!),
    );
  }

  void _toggleTheme() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    ref.read(themeModeProvider.notifier).state =
        isDark ? ThemeMode.light : ThemeMode.dark;
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
    final AuthPalette p = context.authPalette;
    final staffAsync = ref.watch(liveStaffUsersProvider);
    final double width = MediaQuery.sizeOf(context).width;
    final bool isWide = width >= 760;

    // Hardware keyboard shortcuts.
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
            backgroundColor: p.background,
            body: AuthBackdrop(
              child: SafeArea(
                child: Column(
                  children: [
                    _buildTopBar(p, width),
                    Expanded(
                      child: staffAsync.when(
                        data: (staffList) {
                          final activeStaff =
                              staffList.where((u) => u.active).toList();

                          if (_selectedStaff == null &&
                              activeStaff.isNotEmpty) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted && _selectedStaff == null) {
                                setState(
                                  () => _selectedStaff = activeStaff.first,
                                );
                              }
                            });
                          }

                          final filtered = activeStaff.where((u) {
                            final matchesSearch = _searchQuery.isEmpty ||
                                u.name.toLowerCase().contains(
                                      _searchQuery.toLowerCase(),
                                    ) ||
                                u.phone.contains(_searchQuery);
                            final matchesRole =
                                _filterRole == null || u.role == _filterRole;
                            return matchesSearch && matchesRole;
                          }).toList();

                          return isWide
                              ? _buildDesktopLayout(p, filtered)
                              : _buildMobileLayout(p, activeStaff);
                        },
                        loading: () => Center(
                          child: AppStates.loading(
                            message: 'جاري تحميل طاقم العمل...',
                          ),
                        ),
                        error: (err, _) => Center(
                          child: AppStates.error(
                            'تعذر الاتصال بالخادم وتحميل بيانات الموظفين',
                            onRetry: () =>
                                ref.invalidate(liveStaffUsersProvider),
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
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TOP BAR
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildTopBar(AuthPalette p, double width) {
    final ThemeData theme = p.theme;
    final t = _currentTime;
    final String timeStr =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
    final bool isOnline = ConnectivityService.instance.isOnline;
    final bool isDark = theme.brightness == Brightness.dark;
    final bool showSubtitle = width >= 600;
    final bool showClock = width >= 520;
    final bool compactStatus = width < 560;

    return Container(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: width < 520 ? AppSpacing.md : AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: p.panel.withValues(alpha: 0.94),
        border: Border(bottom: BorderSide(color: p.border)),
        boxShadow: [
          BoxShadow(
            color: p.shadow.withValues(alpha: p.isDark ? 0.28 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: p.accentGradient,
              borderRadius: AppRadius.lgAll,
              boxShadow: p.accentGlow,
            ),
            child: Icon(Icons.storefront_rounded, color: p.onAccent, size: 18),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'منظومة متجر الجملة VIP',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: p.text,
                  ),
                ),
                if (showSubtitle)
                  Text(
                    'تسجيل دخول الموظفين برمز PIN',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10.5,
                      color: p.muted,
                    ),
                  ),
              ],
            ),
          ),
          AuthStatusPill(
            label: isOnline ? 'متصل' : 'محلي (Offline)',
            color: isOnline ? p.success : p.warning,
            compact: compactStatus,
          ),
          if (showClock) ...[
            const SizedBox(width: AppSpacing.sm),
            _buildClockPill(p, timeStr),
          ],
          const SizedBox(width: AppSpacing.xs),
          _buildThemeToggle(p, isDark),
        ],
      ),
    );
  }

  Widget _buildClockPill(AuthPalette p, String timeStr) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded, size: 12, color: p.accent),
          const SizedBox(width: 5),
          Text(
            timeStr,
            style: p.theme.textTheme.labelSmall?.copyWith(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: p.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeToggle(AuthPalette p, bool isDark) {
    return Tooltip(
      message:
          isDark ? 'التبديل إلى المظهر الفاتح' : 'التبديل إلى المظهر الداكن',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggleTheme,
          borderRadius: AppRadius.pillAll,
          child: Ink(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: p.field,
              shape: BoxShape.circle,
              border: Border.all(color: p.border),
            ),
            child: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              size: 17,
              color: p.accent,
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // DESKTOP / TABLET DUAL-PANE LAYOUT
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildDesktopLayout(AuthPalette p, List<UserEntity> filteredStaff) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: AuthPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildDirectoryHeader(p, filteredStaff.length),
                  Divider(color: p.border, height: 1),
                  Expanded(
                    child: filteredStaff.isEmpty
                        ? _buildEmptyDirectory(p)
                        : GridView.builder(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 220,
                              mainAxisExtent: 78,
                              crossAxisSpacing: AppSpacing.sm,
                              mainAxisSpacing: AppSpacing.sm,
                            ),
                            itemCount: filteredStaff.length,
                            itemBuilder: (_, i) =>
                                _buildStaffCard(p, filteredStaff[i]),
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            flex: 4,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.symmetric(
                  vertical: AppSpacing.sm,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: _buildPinTerminalCard(p),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectoryHeader(AuthPalette p, int count) {
    final ThemeData theme = p.theme;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: p.accentSoft,
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(color: p.accent.withValues(alpha: 0.24)),
                ),
                child: Icon(Icons.groups_rounded, size: 16, color: p.accent),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'طاقم العمل والورديات',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: p.text,
                      ),
                    ),
                    Text(
                      'اختر حساب الموظف ثم أدخل رمز PIN',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: p.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: p.accentSoft,
                  borderRadius: AppRadius.pillAll,
                  border: Border.all(color: p.accent.withValues(alpha: 0.24)),
                ),
                child: Text(
                  '$count موظف',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10.5,
                    color: p.accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            cursorColor: p.accent,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12.5,
              color: p.text,
            ),
            decoration: _searchDecoration(
              p,
              hint: 'ابحث عن موظف بالاسم أو الهاتف...',
              showClear: _searchQuery.isNotEmpty,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _AuthFilterChip(
                  label: 'الكل',
                  selected: _filterRole == null,
                  onTap: () => setState(() => _filterRole = null),
                ),
                const SizedBox(width: 6),
                _AuthFilterChip(
                  label: 'كاشير',
                  selected: _filterRole == UserRole.cashier,
                  onTap: () => setState(() => _filterRole = UserRole.cashier),
                ),
                const SizedBox(width: 6),
                _AuthFilterChip(
                  label: 'مدير مخزن',
                  selected: _filterRole == UserRole.manager,
                  onTap: () => setState(() => _filterRole = UserRole.manager),
                ),
                const SizedBox(width: 6),
                _AuthFilterChip(
                  label: 'مشرف عام',
                  selected: _filterRole == UserRole.moderator,
                  onTap: () => setState(() => _filterRole = UserRole.moderator),
                ),
                const SizedBox(width: 6),
                _AuthFilterChip(
                  label: 'سائق',
                  selected: _filterRole == UserRole.driver,
                  onTap: () => setState(() => _filterRole = UserRole.driver),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _searchDecoration(
    AuthPalette p, {
    required String hint,
    bool showClear = false,
  }) {
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: AppRadius.mdAll,
      borderSide: BorderSide(color: p.border),
    );

    return InputDecoration(
      hintText: hint,
      hintStyle: p.theme.textTheme.bodySmall?.copyWith(
        fontSize: 11.5,
        color: p.faint,
      ),
      prefixIcon: Icon(Icons.search_rounded, size: 17, color: p.accent),
      isDense: true,
      filled: true,
      fillColor: p.field,
      contentPadding: const EdgeInsetsDirectional.symmetric(
        vertical: AppSpacing.sm,
        horizontal: AppSpacing.md,
      ),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: p.accent, width: 1.4),
      ),
      suffixIcon: showClear
          ? IconButton(
              tooltip: 'مسح البحث',
              onPressed: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
              icon: Icon(Icons.close_rounded, size: 15, color: p.muted),
            )
          : null,
    );
  }

  Widget _buildEmptyDirectory(AuthPalette p) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search_rounded, size: 34, color: p.faint),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'لم يتم العثور على موظف مطابق',
              textAlign: TextAlign.center,
              style: p.theme.textTheme.bodySmall?.copyWith(color: p.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffCard(AuthPalette p, UserEntity staff) {
    final ThemeData theme = p.theme;
    final bool isSelected = _selectedStaff?.id == staff.id;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedStaff = staff;
            _errorMessage = null;
            _pinController.clear();
          });
        },
        borderRadius: AppRadius.lgAll,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.moveCurve,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: isSelected ? p.accentSoft : p.panelAlt,
            borderRadius: AppRadius.lgAll,
            border: Border.all(
              color: isSelected ? p.accent : p.border,
              width: isSelected ? 1.4 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: p.accent.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isSelected ? p.accentGradient : null,
                  color: isSelected ? null : p.field,
                  border: Border.all(color: isSelected ? p.accent : p.border),
                ),
                child: Icon(
                  roleIcon(staff.role),
                  size: 16,
                  color: isSelected ? p.onAccent : p.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      staff.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12.5,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? p.accent : p.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      roleLabel(staff.role),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: p.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle_rounded, color: p.accent, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // MOBILE SINGLE-PANE LAYOUT
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildMobileLayout(AuthPalette p, List<UserEntity> staffList) {
    return Center(
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildMobileStaffSelector(p, staffList),
              const SizedBox(height: AppSpacing.md),
              _buildPinTerminalCard(p),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileStaffSelector(AuthPalette p, List<UserEntity> staffList) {
    final ThemeData theme = p.theme;
    final UserEntity? staff = _selectedStaff;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showStaffPickerBottomSheet(staffList),
        borderRadius: AppRadius.xlAll,
        child: Container(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            gradient: p.panelGradient,
            borderRadius: AppRadius.xlAll,
            border: Border.all(color: p.border),
            boxShadow: p.panelShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: p.accentGradient,
                  boxShadow: p.accentGlow,
                ),
                child: Icon(
                  staff != null ? roleIcon(staff.role) : Icons.person_rounded,
                  size: 18,
                  color: p.onAccent,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      staff?.name ?? 'اضغط لاختيار الموظف',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: p.text,
                      ),
                    ),
                    if (staff != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        roleLabel(staff.role),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: p.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: p.accentSoft,
                  borderRadius: AppRadius.pillAll,
                  border: Border.all(color: p.accent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swap_horiz_rounded, size: 13, color: p.accent),
                    const SizedBox(width: 4),
                    Text(
                      'تبديل',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: p.accent,
                      ),
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

  Future<void> _showStaffPickerBottomSheet(List<UserEntity> staffList) async {
    final AuthPalette p = context.authPalette;
    String query = '';
    UserRole? roleFilter;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: p.shadow.withValues(alpha: 0.48),
      isScrollControlled: true,
      builder: (sheetContext) {
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
                height: MediaQuery.sizeOf(context).height * 0.72,
                decoration: BoxDecoration(
                  gradient: p.panelGradient,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.xxl),
                  ),
                  border: Border(top: BorderSide(color: p.border)),
                ),
                child: SafeArea(
                  top: false,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          AppSpacing.lg,
                          AppSpacing.sm,
                          AppSpacing.lg,
                          AppSpacing.lg,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Container(
                                width: 38,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: p.borderStrong,
                                  borderRadius: AppRadius.pillAll,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              children: [
                                Icon(
                                  Icons.groups_rounded,
                                  size: 18,
                                  color: p.accent,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    'اختر موظف الوردية',
                                    style:
                                        p.theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: p.text,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'إغلاق',
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: p.muted,
                                  ),
                                  onPressed: () =>
                                      Navigator.of(sheetContext).pop(),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextField(
                              onChanged: (v) => setSheetState(() => query = v),
                              cursorColor: p.accent,
                              style: p.theme.textTheme.bodySmall?.copyWith(
                                fontSize: 12.5,
                                color: p.text,
                              ),
                              decoration: _searchDecoration(
                                p,
                                hint: 'بحث عن موظف بالاسم أو الهاتف...',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _AuthFilterChip(
                                    label: 'الكل',
                                    selected: roleFilter == null,
                                    onTap: () =>
                                        setSheetState(() => roleFilter = null),
                                  ),
                                  const SizedBox(width: 6),
                                  _AuthFilterChip(
                                    label: 'كاشير',
                                    selected: roleFilter == UserRole.cashier,
                                    onTap: () => setSheetState(
                                      () => roleFilter = UserRole.cashier,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  _AuthFilterChip(
                                    label: 'مدير مخزن',
                                    selected: roleFilter == UserRole.manager,
                                    onTap: () => setSheetState(
                                      () => roleFilter = UserRole.manager,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  _AuthFilterChip(
                                    label: 'مشرف عام',
                                    selected: roleFilter == UserRole.moderator,
                                    onTap: () => setSheetState(
                                      () => roleFilter = UserRole.moderator,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  _AuthFilterChip(
                                    label: 'سائق',
                                    selected: roleFilter == UserRole.driver,
                                    onTap: () => setSheetState(
                                      () => roleFilter = UserRole.driver,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Expanded(
                              child: filtered.isEmpty
                                  ? _buildEmptyDirectory(p)
                                  : ListView.separated(
                                      itemCount: filtered.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 6),
                                      itemBuilder: (_, i) {
                                        final staff = filtered[i];
                                        final isSelected =
                                            _selectedStaff?.id == staff.id;

                                        return Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: AppRadius.lgAll,
                                            onTap: () {
                                              setState(() {
                                                _selectedStaff = staff;
                                                _errorMessage = null;
                                                _pinController.clear();
                                              });
                                              Navigator.of(sheetContext).pop();
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsetsDirectional
                                                      .symmetric(
                                                horizontal: AppSpacing.md,
                                                vertical: AppSpacing.sm,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? p.accentSoft
                                                    : p.panelAlt,
                                                borderRadius: AppRadius.lgAll,
                                                border: Border.all(
                                                  color: isSelected
                                                      ? p.accent
                                                      : p.border,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 34,
                                                    height: 34,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      gradient: isSelected
                                                          ? p.accentGradient
                                                          : null,
                                                      color: isSelected
                                                          ? null
                                                          : p.field,
                                                    ),
                                                    child: Icon(
                                                      roleIcon(staff.role),
                                                      size: 16,
                                                      color: isSelected
                                                          ? p.onAccent
                                                          : p.accent,
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                    width: AppSpacing.md,
                                                  ),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          staff.name,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: p
                                                              .theme
                                                              .textTheme
                                                              .bodySmall
                                                              ?.copyWith(
                                                            fontSize: 12.5,
                                                            fontWeight:
                                                                isSelected
                                                                    ? FontWeight
                                                                        .w800
                                                                    : FontWeight
                                                                        .w600,
                                                            color: isSelected
                                                                ? p.accent
                                                                : p.text,
                                                          ),
                                                        ),
                                                        Text(
                                                          '${roleLabel(staff.role)} • ${staff.phone}',
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: p
                                                              .theme
                                                              .textTheme
                                                              .labelSmall
                                                              ?.copyWith(
                                                            color: p.muted,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  if (isSelected)
                                                    Icon(
                                                      Icons
                                                          .check_circle_rounded,
                                                      color: p.accent,
                                                      size: 17,
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // PIN TERMINAL CARD
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildPinTerminalCard(AuthPalette p) {
    final ThemeData theme = p.theme;
    final UserEntity? staff = _selectedStaff;

    return AuthPanel(
      radius: AppRadius.xxl,
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 14, color: p.muted),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'بوابة الدخول الآمن',
                style: theme.textTheme.labelSmall?.copyWith(color: p.muted),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: p.accentFaint,
                  borderRadius: AppRadius.smAll,
                  border: Border.all(color: p.accent.withValues(alpha: 0.22)),
                ),
                child: Text(
                  'PIN',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: p.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AnimatedSwitcher(
            duration: AppMotion.medium,
            switchInCurve: AppMotion.enterCurve,
            switchOutCurve: AppMotion.exitCurve,
            child: _buildStaffIdentity(p, staff),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'أدخل رمز PIN لتسجيل الدخول',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(color: p.muted),
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: AuthPinField(
              controller: _pinController,
              focusNode: _focusNode,
              isError: _errorMessage != null,
              obscuringCharacter: '◆',
              onCompleted: _handlePinLogin,
              onChanged: (_) {
                if (_errorMessage != null) {
                  setState(() => _errorMessage = null);
                }
              },
            ),
          ),
          AnimatedSize(
            duration: AppMotion.fast,
            curve: AppMotion.enterCurve,
            child: _errorMessage == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsetsDirectional.only(
                      top: AppSpacing.sm,
                    ),
                    child: AuthErrorBanner(message: _errorMessage!),
                  ),
          ),
          const SizedBox(height: AppSpacing.md),
          AuthNumericKeypad(
            maxWidth: 290,
            enabled: !_isAuthenticating,
            clearLabel: 'مسح',
            onDigit: _pressKeypadKey,
            onBackspace: () => _pressKeypadKey('back'),
            onClear: () => _pressKeypadKey('C'),
          ),
          const SizedBox(height: AppSpacing.sm),
          AnimatedSwitcher(
            duration: AppMotion.fast,
            child: _isAuthenticating
                ? Row(
                    key: const ValueKey('authenticating'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: p.accent,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'جارٍ التحقق من الرمز...',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: p.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : TextButton.icon(
                    key: const ValueKey('change-pin'),
                    onPressed: _openChangePinDialog,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: Icon(
                      Icons.password_rounded,
                      size: 14,
                      color: p.accent,
                    ),
                    label: Text(
                      'تغيير رمز PIN',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: p.accent,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffIdentity(AuthPalette p, UserEntity? staff) {
    final ThemeData theme = p.theme;

    if (staff == null) {
      return Column(
        key: const ValueKey('no-staff'),
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.field,
              border: Border.all(color: p.border),
            ),
            child: Icon(Icons.lock_outline_rounded, size: 27, color: p.accent),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'تسجيل الدخول',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: p.text,
            ),
          ),
        ],
      );
    }

    return Column(
      key: ValueKey('staff-${staff.id}'),
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: p.accentGradient,
            border: Border.all(
              color: p.accent.withValues(alpha: 0.5),
              width: 2,
            ),
            boxShadow: p.accentGlow,
          ),
          child: Icon(roleIcon(staff.role), size: 27, color: p.onAccent),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          staff.name,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: p.text,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: p.accentSoft,
            borderRadius: AppRadius.pillAll,
            border: Border.all(color: p.accent.withValues(alpha: 0.28)),
          ),
          child: Text(
            roleLabel(staff.role),
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: p.accent,
            ),
          ),
        ),
      ],
    );
  }
}

class _AuthFilterChip extends StatelessWidget {
  const _AuthFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AuthPalette p = context.authPalette;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.pillAll,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.md,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: selected ? p.accentSoft : p.panelAlt,
            borderRadius: AppRadius.pillAll,
            border: Border.all(
              color: selected ? p.accent : p.border,
              width: selected ? 1.3 : 1,
            ),
          ),
          child: Text(
            label,
            style: p.theme.textTheme.labelSmall?.copyWith(
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              color: selected ? p.accent : p.muted,
            ),
          ),
        ),
      ),
    );
  }
}
