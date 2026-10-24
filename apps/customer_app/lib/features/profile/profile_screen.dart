import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domain/domain.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../models/customer_models.dart';
import '../../providers/customer_providers.dart';
import '../common/widgets/app_update_dialog.dart';
import 'profile_form_screen.dart';

/// Account hub: identity, delivery details, wallet snapshot and app actions.
class ProfileScreen extends ConsumerStatefulWidget {
  final ValueChanged<int>? onNavigate;
  final VoidCallback? onExit;

  const ProfileScreen({super.key, this.onNavigate, this.onExit});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _checkingUpdate = false;
  bool _syncing = false;

  Future<void> _refreshAll() async {
    await ref.read(customerSyncCoordinatorProvider).refreshAll();
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    if (!ref.read(customerIsOnlineProvider)) {
      _toast('لا يوجد اتصال حالياً. ستتم المزامنة تلقائياً عند عودته.');
      return;
    }
    setState(() => _syncing = true);
    try {
      await _refreshAll();
      if (!mounted) return;
      _toast('تمت مزامنة بياناتك مع المتجر.');
    } catch (e) {
      if (!mounted) return;
      _toast('تعذرت المزامنة: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _checkForUpdate({bool force = false}) async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      final service = ref.read(customerAppUpdateServiceProvider);
      final result = await service.checkForUpdate(force: force);
      if (!mounted) return;
      if (result.newRelease != null && (result.hasUpdate || force)) {
        await AppUpdateDialog.show(
          context,
          release: result.newRelease!,
          currentVersion: result.currentVersion,
          currentBuild: result.currentBuild,
          updateService: service,
          force: force || result.isForceUpdate,
        );
      } else {
        _toast('أنت تستخدم أحدث إصدار من التطبيق.');
      }
    } catch (e) {
      if (!mounted) return;
      _toast('تعذر التحقق من التحديثات.');
      debugPrint('[Profile] update check failed: $e');
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _showAbout() async {
    String version = '1.0.0';
    String build = '1';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build = info.buildNumber;
    } catch (_) {}
    if (!mounted) return;
    showAboutDialog(
      context: context,
      applicationName: 'VIP Wholesale',
      applicationVersion: 'v$version ($build)',
      applicationLegalese:
          'متجر الجملة VIP — تجربة طلب راقية وسريعة.\nجميع الحقوق محفوظة.',
      applicationIcon: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppGradients.gold,
          borderRadius: AppRadius.mdAll,
          boxShadow: [AppShadows.goldGlowSm],
        ),
        child: Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.diamond_rounded,
              size: 26, color: Color(0xFF1A1400)),
        ),
      ),
      children: [
        const SizedBox(height: AppSpacing.md),
        Text(
          'تطبيق الزبائن: تصفح الكتالوج، اطلب بسرعة، تتبع السائق، '
          'وتابع محفظتك — حتى دون اتصال.',
          style: TextStyle(
            fontSize: 11,
            height: 1.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(message, style: const TextStyle(fontSize: 12)),
        ),
      );
  }

  void _editProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileFormScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final profile = ref.watch(customerProfileProvider);
    final wallet = ref.watch(customerWalletProvider).valueOrNull;
    final orders = ref.watch(customerOrdersProvider).valueOrNull;
    final online = ref.watch(customerIsOnlineProvider);

    final pendingOrders = orders?.pendingCount ?? 0;
    final activeOrders = orders?.activeOrders.length ?? 0;
    final totalOrders = orders?.orders.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppGradients.gold,
                borderRadius: AppRadius.smAll,
                boxShadow: [AppShadows.goldGlowSm],
              ),
              child: Padding(
                padding: EdgeInsets.all(5),
                child: Icon(Icons.person_rounded,
                    size: 16, color: Color(0xFF1A1400)),
              ),
            ),
            SizedBox(width: AppSpacing.sm),
            Text('حسابي'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'تعديل البيانات',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _editProfile,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFFD4AF37),
        backgroundColor:
            isDark ? const Color(0xFF1A1814) : const Color(0xFFFFFDF8),
        onRefresh: _refreshAll,
        child: ContentConstrainedBox.dashboard(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            children: [
              _ProfileHero(
                profile: profile,
                online: online,
                onEdit: _editProfile,
              ),
              if (!profile.isComplete) ...[
                const SizedBox(height: AppSpacing.md),
                _CompleteProfileBanner(onEdit: _editProfile),
              ],
              const SizedBox(height: AppSpacing.md),
              _StatsRow(
                totalOrders: totalOrders,
                activeOrders: activeOrders,
                debtCentimes: wallet?.currentDebtCentimes ?? 0,
                onOrders: widget.onNavigate == null
                    ? null
                    : () => widget.onNavigate!(1),
              ),
              if (profile.isComplete) ...[
                const SizedBox(height: AppSpacing.md),
                _WalletMiniCard(
                  wallet: wallet,
                  onTap: widget.onNavigate == null
                      ? null
                      : () => widget.onNavigate!(2),
                ),
                const SizedBox(height: AppSpacing.md),
                _AddressCard(profile: profile, onEdit: _editProfile),
              ],
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader(title: 'حسابي والمتجر'),
              const SizedBox(height: AppSpacing.sm),
              _ActionTile(
                icon: Icons.receipt_long_rounded,
                title: 'طلبياتي',
                subtitle: activeOrders > 0
                    ? '$activeOrders طلبية جارية · $totalOrders إجمالاً'
                    : '$totalOrders طلبية',
                onTap: widget.onNavigate == null
                    ? null
                    : () => widget.onNavigate!(1),
              ),
              _ActionTile(
                icon: Icons.account_balance_wallet_rounded,
                title: 'محفظتي',
                subtitle: wallet != null && wallet.creditLimitCentimes > 0
                    ? 'المتاح ${DzdFormatter.formatCentimes(wallet.remainingCreditCentimes)}'
                    : 'تابع دينك وسقفك الائتماني',
                onTap: widget.onNavigate == null
                    ? null
                    : () => widget.onNavigate!(2),
              ),
              _ActionTile(
                icon: Icons.location_on_rounded,
                title: 'بيانات التوصيل',
                subtitle: profile.isComplete
                    ? [profile.wilaya, profile.commune]
                        .where((part) => part.isNotEmpty)
                        .join(' · ')
                    : 'أكمل اسم المحل والعنوان',
                onTap: _editProfile,
              ),
              _ActionTile(
                icon: pendingOrders > 0
                    ? Icons.cloud_upload_outlined
                    : Icons.sync_rounded,
                title: 'مزامنة البيانات الآن',
                subtitle: !online
                    ? 'بانتظار عودة الاتصال'
                    : pendingOrders > 0
                        ? '$pendingOrders طلبية محفوظة في انتظار الإرسال'
                        : 'كل بياناتك محدّثة',
                trailing: _syncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                accent: pendingOrders > 0,
                onTap: _syncNow,
              ),
              _ActionTile(
                icon: Icons.system_update_alt_rounded,
                title: 'التحقق من التحديثات',
                subtitle: 'احصل على أحدث مزايا التطبيق (اضغط مطولاً لفرض التحديث)',
                trailing: _checkingUpdate
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: () => _checkForUpdate(force: false),
                onLongPress: () => _checkForUpdate(force: true),
              ),
              _ActionTile(
                icon: Icons.info_outline_rounded,
                title: 'عن التطبيق',
                subtitle: 'VIP Wholesale · تطبيق الزبائن',
                onTap: _showAbout,
              ),
              if (widget.onExit != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _ActionTile(
                  icon: Icons.logout_rounded,
                  title: 'الخروج من المتجر',
                  subtitle: 'العودة إلى التطبيق الرئيسي',
                  destructive: true,
                  onTap: widget.onExit!,
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              const _Footer(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Hero ──────────────────────────────────────────────────────────────────────

class _ProfileHero extends StatelessWidget {
  final CustomerProfileInfo profile;
  final bool online;
  final VoidCallback onEdit;

  const _ProfileHero({
    required this.profile,
    required this.online,
    required this.onEdit,
  });

  String get _tierLabel {
    switch (profile.priceTier) {
      case PriceTier.retail:
        return 'تجزئة';
      case PriceTier.wholesale:
        return 'جملة';
      case PriceTier.bulk:
        return 'جملة كبيرة';
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = profile.name.trim().isNotEmpty
        ? profile.name.trim().substring(0, 1)
        : 'V';

    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppGradients.obsidianHero,
        borderRadius: AppRadius.xlAll,
        border: Border.all(color: const Color(0x40D4AF37)),
        boxShadow: AppShadows.cardElevatedDark,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  gradient: AppGradients.gold,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0x66FFFFFF),
                    width: 1.5,
                  ),
                  boxShadow: const [AppShadows.goldGlow],
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1400),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name.isNotEmpty ? profile.name : 'مرحباً بك',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFBF8F0),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (profile.phone.isNotEmpty)
                      Text(
                        profile.phone,
                        style: const TextStyle(
                          color: Color(0xFFB8A882),
                          fontSize: 11,
                        ),
                      ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        GoldBadge(
                          label: profile.isSynced
                              ? 'عضوية $_tierLabel'
                              : 'حساب غير مكتمل',
                          icon: profile.isSynced
                              ? Icons.workspace_premium_rounded
                              : Icons.info_outline_rounded,
                          small: true,
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: online
                                ? const Color(0xFF34D399)
                                : const Color(0xFFFBBF24),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          online ? 'متصل' : 'محلي',
                          style: const TextStyle(
                            color: Color(0xFFB8A882),
                            fontSize: 8.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  side: const BorderSide(
                      color: Color(0x66D4AF37), width: 1),
                  shape: const RoundedRectangleBorder(
                      borderRadius: AppRadius.mdAll),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                onPressed: onEdit,
                child: const Text(
                  'تعديل',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFF3D278),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const GoldDivider(height: 0.7),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(Icons.verified_user_outlined,
                  size: 12, color: Color(0xFFB8A882)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  profile.isSynced
                      ? 'حسابك مرتبط بجهازك ومحمي برمز الجهاز.'
                      : 'أكمل بياناتك لتفعيل أسعار الجملة والتوصيل.',
                  style: const TextStyle(
                      color: Color(0xFFB8A882), fontSize: 9),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompleteProfileBanner extends StatelessWidget {
  final VoidCallback onEdit;

  const _CompleteProfileBanner({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.warningContainer,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.person_pin_circle_outlined,
              size: 20, color: colors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'بيانات التوصيل غير مكتملة',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: colors.onWarningContainer,
                  ),
                ),
                Text(
                  'أكملها مرة واحدة لتفعيل الطلب بأسعار الجملة.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 9.5,
                    color: colors.onWarningContainer,
                  ),
                ),
              ],
            ),
          ),
          GoldButton.icon(
            icon: Icons.arrow_forward_rounded,
            label: 'إكمال',
            onPressed: onEdit,
            compact: true,
          ),
        ],
      ),
    );
  }
}

// ── Stats / wallet / address ──────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final int totalOrders;
  final int activeOrders;
  final int debtCentimes;
  final VoidCallback? onOrders;

  const _StatsRow({
    required this.totalOrders,
    required this.activeOrders,
    required this.debtCentimes,
    this.onOrders,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'الطلبيات',
            value: '$totalOrders',
            icon: Icons.receipt_long_outlined,
            onTap: onOrders,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatTile(
            label: 'الجارية',
            value: '$activeOrders',
            icon: Icons.local_shipping_outlined,
            accent: activeOrders > 0,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatTile(
            label: 'الدين',
            value: DzdFormatter.formatCentimes(debtCentimes),
            icon: Icons.account_balance_wallet_outlined,
            accent: debtCentimes > 0,
            smallValue: true,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool accent;
  final bool smallValue;
  final VoidCallback? onTap;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    this.accent = false,
    this.smallValue = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = accent
        ? (dark ? const Color(0xFFF3D278) : const Color(0xFFC59B27))
        : theme.colorScheme.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.mdAll,
        child: Container(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color:
                dark ? const Color(0xFF1A1814) : const Color(0xFFFFFDF8),
            borderRadius: AppRadius.mdAll,
            border: Border.all(
              color: const Color(0xFFD4AF37)
                  .withValues(alpha: dark ? 0.24 : 0.16),
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: smallValue ? 9.5 : 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 8.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalletMiniCard extends StatelessWidget {
  final WalletSnapshot? wallet;
  final VoidCallback? onTap;

  const _WalletMiniCard({required this.wallet, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final debt = wallet?.currentDebtCentimes ?? 0;
    final limit = wallet?.creditLimitCentimes ?? 0;
    final remaining = wallet?.remainingCreditCentimes ?? 0;
    final usage = wallet?.creditUsage ?? 0;

    return LuxuryCard(
      onTap: onTap,
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  gradient: AppGradients.gold,
                  borderRadius: AppRadius.smAll,
                  boxShadow: [AppShadows.goldGlowSm],
                ),
                child: const Icon(Icons.account_balance_wallet_rounded,
                    size: 17, color: Color(0xFF1A1400)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'محفظة VIP',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      limit > 0
                          ? 'سقف ${DzdFormatter.formatCentimes(limit)}'
                          : 'لم يُحدد سقف ائتمان بعد',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 9.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'الدين',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 8.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  DzdPriceTag(
                    centimes: debt,
                    gold: debt > 0,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
          if (limit > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: AppRadius.pillAll,
              child: Stack(
                children: [
                  Container(
                    height: 5,
                    color: isDark
                        ? const Color(0xFF2A2518)
                        : const Color(0xFFEDE3B8),
                  ),
                  FractionallySizedBox(
                    widthFactor: usage,
                    child: Container(
                      height: 5,
                      decoration: const BoxDecoration(
                        gradient: AppGradients.goldLuminous,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'المتاح ${DzdFormatter.formatCentimes(remaining)}',
                  style: TextStyle(
                    fontSize: 9,
                    color: isDark
                        ? const Color(0xFFB8A882)
                        : const Color(0xFF9A8A60),
                  ),
                ),
                const Spacer(),
                Text(
                  'عرض المحفظة',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? const Color(0xFFF3D278)
                        : const Color(0xFF9A7319),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  final CustomerProfileInfo profile;
  final VoidCallback onEdit;

  const _AddressCard({required this.profile, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return LuxuryCard(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on_outlined,
              size: 18, color: Color(0xFFD4AF37)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'عنوان التوصيل',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 9.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  [
                    profile.wilaya,
                    profile.commune,
                    profile.addressText,
                  ].where((part) => part.trim().isNotEmpty).join(' · '),
                  style: const TextStyle(fontSize: 11.5),
                ),
                if (profile.latitude != null && profile.longitude != null)
                  Text(
                    'GPS: ${profile.latitude!.toStringAsFixed(4)}, '
                    '${profile.longitude!.toStringAsFixed(4)}',
                    style: TextStyle(
                      fontSize: 8.5,
                      color: isDark
                          ? const Color(0xFF34D399)
                          : const Color(0xFF059669),
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: onEdit,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('تعديل', style: TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }
}

// ── Actions ───────────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final bool accent;
  final bool destructive;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.accent = false,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = context.appColors;
    final color = destructive
        ? colors.cancelled
        : accent
            ? (isDark ? const Color(0xFFF3D278) : const Color(0xFFC59B27))
            : (isDark ? const Color(0xFFF3D278) : const Color(0xFF9A7319));

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: AppRadius.mdAll,
          child: Container(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color:
                  isDark ? const Color(0xFF1A1814) : const Color(0xFFFFFDF8),
              borderRadius: AppRadius.mdAll,
              border: Border.all(
                color: const Color(0xFFD4AF37)
                    .withValues(alpha: isDark ? 0.20 : 0.14),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: AppRadius.smAll,
                    border: Border.all(
                        color: color.withValues(alpha: 0.22)),
                  ),
                  child: Icon(icon, size: 17, color: color),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: destructive ? color : null,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 9.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null)
                  trailing!
                else if (onTap != null)
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 11,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.6),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(
          Icons.diamond_outlined,
          size: 18,
          color: const Color(0xFFD4AF37).withValues(alpha: 0.50),
        ),
        const SizedBox(height: 4),
        Text(
          'VIP WHOLESALE',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            color: const Color(0xFFD4AF37).withValues(alpha: 0.65),
          ),
        ),
        Text(
          'تجربة طلب راقية · جميع الحقوق محفوظة',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 8.5,
            color: theme.colorScheme.onSurfaceVariant
                .withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
