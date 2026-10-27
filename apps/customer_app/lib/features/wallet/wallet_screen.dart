import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domain/domain.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../models/customer_models.dart';
import '../../providers/customer_providers.dart';
import '../profile/profile_form_screen.dart';

/// Customer credit wallet: debt, available credit, unpaid orders and ledger.
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  Future<void> _refresh(WidgetRef ref) =>
      ref.read(customerWalletProvider.notifier).refresh();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(customerWalletProvider);
    final online = ref.watch(customerIsOnlineProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF1DAB61), Color(0xFF034F40)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: AppRadius.smAll,
                boxShadow: [BoxShadow(color: Color(0x3D1DAB61), blurRadius: 8, offset: Offset(0,3))],
              ),
              child: Padding(
                padding: EdgeInsets.all(5),
                child: Icon(Icons.account_balance_wallet_rounded,
                    size: 16, color: Colors.white),
              ),
            ),
            SizedBox(width: AppSpacing.sm),
            Text('محفظتي'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _refresh(ref),
          ),
        ],
      ),
      body: walletAsync.when(
        loading: () => const _WalletSkeleton(),
        error: (error, _) => ContentConstrainedBox.dashboard(
          padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
          child: AppStates.error(
            'تعذر تحميل المحفظة. ${error.toString().replaceFirst('Exception: ', '')}',
            title: 'المحفظة غير متاحة الآن',
            onRetry: () => _refresh(ref),
          ),
        ),
        data: (snapshot) => _WalletBody(
          snapshot: snapshot,
          online: online,
          onRefresh: () => _refresh(ref),
        ),
      ),
    );
  }
}

class _WalletBody extends ConsumerWidget {
  final WalletSnapshot snapshot;
  final bool online;
  final Future<void> Function() onRefresh;

  const _WalletBody({
    required this.snapshot,
    required this.online,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final profile = ref.watch(customerProfileProvider);
    final offline = !online || snapshot.isOffline;
    final hasAccount = profile.hasAccount;

    return RefreshIndicator(
      color: const Color(0xFF1DAB61),
      backgroundColor:
          isDark ? const Color(0xFF131B16) : const Color(0xFFEEF5F0),
      onRefresh: onRefresh,
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
            if (!hasAccount)
              _NoAccountCard(
                onComplete: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ProfileFormScreen(),
                  ),
                ),
              )
            else ...[
              _WalletHero(
                snapshot: snapshot,
                name: profile.name.isNotEmpty
                    ? profile.name
                    : snapshot.customerName,
                offline: offline,
              ),
              const SizedBox(height: AppSpacing.md),
              _CreditSummary(snapshot: snapshot),
              if (offline || snapshot.lastError != null) ...[
                const SizedBox(height: AppSpacing.md),
                _WalletNotice(
                  offline: offline,
                  message: snapshot.lastError,
                  fetchedAt: snapshot.fetchedAt,
                  onRetry: onRefresh,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              SectionHeader(
                title: 'طلبيات غير مسددة',
                trailing: snapshot.unpaidOrders.isEmpty
                    ? null
                    : Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 1.5),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF1DAB61).withValues(alpha: 0.14),
                          borderRadius: AppRadius.pillAll,
                        ),
                        child: Text(
                          '${snapshot.unpaidOrders.length}',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? const Color(0xFF72DFA0)
                                : const Color(0xFF0A6B3A),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (snapshot.unpaidOrders.isEmpty)
                const _EmptySection(
                  icon: Icons.verified_rounded,
                  title: 'لا توجد مبالغ مستحقة',
                  description:
                      'كل طلبياتك مسددة. شكراً لتعاملك مع متجر VIP.',
                  success: true,
                )
              else
                ...snapshot.unpaidOrders.map(
                  (order) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _UnpaidOrderCard(
                      order: order,
                      isDark: isDark,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader(title: 'سجل الحركات'),
              const SizedBox(height: AppSpacing.sm),
              if (snapshot.ledger.isEmpty)
                const _EmptySection(
                  icon: Icons.receipt_long_outlined,
                  title: 'لا توجد حركات بعد',
                  description:
                      'ستظهر هنا عمليات الشراء بالأجل والتسديدات.',
                )
              else
                ...snapshot.ledger
                    .take(40)
                    .map(
                      (entry) => Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: _LedgerRow(entry: entry),
                      ),
                    ),
              const SizedBox(height: AppSpacing.lg),
              _PaymentHint(isDark: isDark),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Hero ──────────────────────────────────────────────────────────────────────

class _WalletHero extends StatelessWidget {
  final WalletSnapshot snapshot;
  final String name;
  final bool offline;

  const _WalletHero({
    required this.snapshot,
    required this.name,
    required this.offline,
  });

  @override
  Widget build(BuildContext context) {
    final usage = snapshot.creditUsage;
    final usageColor = usage > 0.85
        ? const Color(0xFFFF7A7A)
        : usage > 0.6
            ? const Color(0xFFFBBF24)
            : const Color(0xFF34D399);

    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppGradients.obsidianHero,
        borderRadius: AppRadius.xlAll,
        border: Border.all(color: const Color(0x401DAB61)),
        boxShadow: AppShadows.cardElevatedDark,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GoldBadge(
                label: 'VIP WALLET',
                icon: Icons.diamond_rounded,
                small: true,
              ),
              const Spacer(),
              if (offline)
                const Row(
                  children: [
                    Icon(Icons.wifi_off_rounded,
                        size: 11, color: Color(0xFFFBBF24)),
                    SizedBox(width: 3),
                    Text(
                      'آخر نسخة محفوظة',
                      style: TextStyle(
                          fontSize: 8.5, color: Color(0xFFB8A882)),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            name.isEmpty ? 'حسابي' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFFBF8F0),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'الدين الحالي',
            style: TextStyle(color: Color(0xFFB8A882), fontSize: 10),
          ),
          const SizedBox(height: 2),
          DzdPriceTag.hero(
            centimes: snapshot.currentDebtCentimes,
            color: snapshot.currentDebtCentimes > 0
                ? const Color(0xFFFFE4A3)
                : const Color(0xFF7EE7B0),
            style: const TextStyle(fontSize: 30),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(height: 0.7, margin: const EdgeInsets.symmetric(vertical: 8), decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0x001DAB61), Color(0xFF1DAB61), Color(0x001DAB61)]))),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _HeroMetric(
                  label: 'سقف الائتمان',
                  value: DzdFormatter.formatCentimes(
                      snapshot.creditLimitCentimes),
                  muted: true,
                ),
              ),
              Container(
                width: 1,
                height: 28,
                color: const Color(0x301DAB61),
              ),
              Expanded(
                child: _HeroMetric(
                  label: 'المتاح للطلب',
                  value: DzdFormatter.formatCentimes(
                      snapshot.remainingCreditCentimes),
                  valueColor: const Color(0xFF7EE7B0),
                ),
              ),
            ],
          ),
          if (snapshot.creditLimitCentimes > 0) ...[
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: AppRadius.pillAll,
              child: Stack(
                children: [
                  Container(
                    height: 6,
                    color: const Color(0x22FFFFFF),
                  ),
                  FractionallySizedBox(
                    widthFactor: usage,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            usageColor,
                            usageColor.withValues(alpha: 0.55),
                          ],
                        ),
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
                  'مستخدم ${(usage * 100).round()}%',
                  style: const TextStyle(
                      color: Color(0xFFB8A882), fontSize: 8.5),
                ),
                const Spacer(),
                if (usage >= 0.85)
                  const Text(
                    'اقتربت من سقف الائتمان',
                    style: TextStyle(
                        color: Color(0xFFFFB4B4),
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  final String label;
  final String value;
  final bool muted;
  final Color? valueColor;

  const _HeroMetric({
    required this.label,
    required this.value,
    this.muted = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFFB8A882), fontSize: 9),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: valueColor ??
                (muted ? const Color(0xFFB8A882) : const Color(0xFFFBF8F0)),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _CreditSummary extends StatelessWidget {
  final WalletSnapshot snapshot;

  const _CreditSummary({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final overLimit = snapshot.currentDebtCentimes >
        snapshot.creditLimitCentimes &&
        snapshot.creditLimitCentimes > 0;

    return Row(
      children: [
        Expanded(
          child: KpiCard(
            title: 'إجمالي الدين',
            value: DzdFormatter.formatCentimes(snapshot.currentDebtCentimes),
            icon: Icons.account_balance_wallet_outlined,
            accentColor: overLimit ? colors.cancelled : const Color(0xFF1DAB61),
            subtitle: overLimit ? 'تجاوز السقف المسموح' : 'على الحساب',
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: KpiCard(
            title: 'طلبيات مستحقة',
            value: '${snapshot.unpaidOrders.length}',
            icon: Icons.pending_actions_outlined,
            accentColor: snapshot.unpaidOrders.isEmpty
                ? colors.success
                : const Color(0xFFB8860B),
            subtitle: snapshot.unpaidOrders.isEmpty
                ? 'لا مستحقات'
                : 'بانتظار التسديد',
          ),
        ),
      ],
    );
  }
}

// ── Lists ─────────────────────────────────────────────────────────────────────

class _UnpaidOrderCard extends StatelessWidget {
  final CustomerUnpaidOrderEntity order;
  final bool isDark;

  const _UnpaidOrderCard({required this.order, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final short = order.orderId.length > 8
        ? order.orderId.substring(0, 8)
        : order.orderId;

    return LuxuryCard(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF1DAB61)
                      .withValues(alpha: isDark ? 0.16 : 0.10),
                  borderRadius: AppRadius.smAll,
                ),
                child: const Icon(Icons.receipt_long_outlined,
                    size: 16, color: const Color(0xFF1DAB61)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'طلب #$short',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    Text(
                      _fmtDate(order.orderDate),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 9.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              DzdPriceTag(
                centimes: order.remainingDebtCentimes,
                gold: true,
              ),
            ],
          ),
          if (order.itemsSummary.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              order.itemsSummary.take(3).join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 9.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Text(
                'الإجمالي ${DzdFormatter.formatCentimes(order.totalAmountCentimes)}',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
              ),
              const Spacer(),
              Text(
                'مدفوع ${DzdFormatter.formatCentimes(order.paidAmountCentimes)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 9,
                  color: context.appColors.success,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  final CustomerLedgerEntryEntity entry;

  const _LedgerRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final increase = entry.amountChangeCentimes > 0;
    final color = increase ? colors.cancelled : colors.success;
    final icon = switch (entry.refType) {
      'payment' => Icons.payments_outlined,
      'return_refund' => Icons.assignment_return_outlined,
      'manual_adjustment' => Icons.tune_rounded,
      _ => Icons.shopping_bag_outlined,
    };
    final label = switch (entry.refType) {
      'payment' => 'تسديد دفعة',
      'return_refund' => 'مرتجع',
      'manual_adjustment' => 'تعديل يدوي',
      'order_credit' => 'شراء بالأجل',
      _ => 'حركة حساب',
    };

    return LuxuryCard(
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: AppRadius.smAll,
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600),
                ),
                Text(
                  [
                    _fmtDate(entry.createdAt),
                    if (entry.notes != null &&
                        entry.notes!.trim().isNotEmpty)
                      entry.notes!.trim(),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 8.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${increase ? '+' : '−'}${DzdFormatter.formatCentimes(entry.amountChangeCentimes.abs())}',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Notices / empty ───────────────────────────────────────────────────────────

class _WalletNotice extends StatelessWidget {
  final bool offline;
  final String? message;
  final DateTime? fetchedAt;
  final Future<void> Function() onRetry;

  const _WalletNotice({
    required this.offline,
    required this.message,
    required this.fetchedAt,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFF72DFA0) : const Color(0xFF0A6B3A);
    final local = fetchedAt?.toLocal();
    final stamp = local == null
        ? ''
        : ' · آخر تحديث ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1F18) : const Color(0xFFE8F7EF),
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: const Color(0xFF1DAB61).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            offline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
            size: 16,
            color: accent,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              offline
                  ? 'وضع عدم الاتصال — تُعرض آخر أرقام محفوظة.$stamp'
                  : '${message ?? 'تعذر تحديث المحفظة الآن.'}$stamp',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'إعادة المحاولة',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool success;

  const _EmptySection({
    required this.icon,
    required this.title,
    required this.description,
    this.success = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final color = success ? colors.success : const Color(0xFF1DAB61);
    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF131B16)
            : const Color(0xFFEEF5F0),
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: const Color(0xFF1DAB61).withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: AppRadius.smAll,
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 9.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoAccountCard extends StatelessWidget {
  final VoidCallback onComplete;

  const _NoAccountCard({required this.onComplete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LuxuryCard(
      goldAccent: true,
      padding: const EdgeInsetsDirectional.all(AppSpacing.xl),
      child: Column(
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1DAB61), Color(0xFF034F40)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x501DAB61), blurRadius: 14, offset: Offset(0,5))],
            ),
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Icon(Icons.account_balance_wallet_rounded,
                  size: 30, color: Colors.white),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'محفظتك جاهزة بعد أول طلبية',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'أكمل بيانات التوصيل لإنشاء حسابك، ثم تابع دينك وسقفك الائتماني هنا.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 10.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          GoldButton.icon(
            icon: Icons.person_pin_circle_outlined,
            label: 'إكمال البيانات',
            onPressed: onComplete,
            width: double.infinity,
          ),
        ],
      ),
    );
  }
}

class _PaymentHint extends StatelessWidget {
  final bool isDark;

  const _PaymentHint({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131B16) : const Color(0xFFDFF7EC),
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: const Color(0xFF1DAB61).withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 16, color: const Color(0xFF1DAB61)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'تسديد الدين يتم لدى نقطة البيع أو مع السائق عند التسليم. '
              'تظهر كل دفعة هنا مباشرة بعد تسجيلها من المتجر.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 9.5,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletSkeleton extends StatelessWidget {
  const _WalletSkeleton();

  @override
  Widget build(BuildContext context) {
    return ContentConstrainedBox.dashboard(
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      child: ListView(
        children: [
          AppStates.skeleton(height: 210, borderRadius: AppRadius.xlAll),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: AppStates.skeleton(
                    height: 130, borderRadius: AppRadius.lgAll),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppStates.skeleton(
                    height: 130, borderRadius: AppRadius.lgAll),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppStates.skeleton(height: 90, borderRadius: AppRadius.lgAll),
          const SizedBox(height: AppSpacing.sm),
          AppStates.skeleton(height: 90, borderRadius: AppRadius.lgAll),
        ],
      ),
    );
  }
}

String _fmtDate(DateTime dt) {
  final l = dt.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
}
