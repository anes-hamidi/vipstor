import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:ui_kit/ui_kit.dart';
import '../../providers/customer_providers.dart';

/// Profile / delivery details form.
///
/// Used for first-time setup ([isSetup]: true) and for editing from the cart.
class ProfileFormScreen extends ConsumerStatefulWidget {
  final bool isSetup;
  final VoidCallback? onExit;
  const ProfileFormScreen({super.key, this.isSetup = false, this.onExit});

  @override
  ConsumerState<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends ConsumerState<ProfileFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phone;
  late final TextEditingController _name;
  late final TextEditingController _wilaya;
  late final TextEditingController _commune;
  late final TextEditingController _address;
  double? _lat;
  double? _lng;
  bool _locating = false;
  bool _lookingUp = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = ref.read(customerProfileProvider);
    _phone   = TextEditingController(text: p.phone);
    _name    = TextEditingController(text: p.name);
    _wilaya  = TextEditingController(text: p.wilaya);
    _commune = TextEditingController(text: p.commune);
    _address = TextEditingController(text: p.addressText);
    _lat = p.latitude;
    _lng = p.longitude;
  }

  @override
  void dispose() {
    for (final c in [_phone, _name, _wilaya, _commune, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null;

  String? _validatePhone(String? v) {
    if (v == null || v.trim().isEmpty) return 'هذا الحقل مطلوب';
    if (!CustomerProfileInfo.isValidPhone(v)) return 'أدخل رقماً صحيحاً مثل 0550123456';
    return null;
  }

  Future<void> _detectGps() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (!mounted) return;
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (!mounted) return;
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _toast('اسمح للتطبيق بالوصول إلى الموقع من الإعدادات');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );

      // GPS can take several seconds. If the user left this screen while the
      // request was in flight, both setState and the controllers are invalid.
      if (!mounted) return;

      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
      try {
        final marks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (!mounted) return;
        if (marks.isNotEmpty) {
          final m = marks.first;
          if ((m.administrativeArea ?? '').isNotEmpty) {
            _wilaya.text = m.administrativeArea!;
          }
          if ((m.locality ?? '').isNotEmpty) _commune.text = m.locality!;
          if ((m.street ?? '').isNotEmpty) {
            _address.text =
                '${m.street}, ${m.subLocality ?? ""}'.trim();
          }
        }
      } catch (_) {}
    } catch (_) {
      _toast('تعذر تحديد الموقع، أدخل العنوان يدوياً');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _lookup() async {
    if (_lookingUp) return;
    if (!CustomerProfileInfo.isValidPhone(_phone.text)) {
      _toast('أدخل رقم هاتف صحيحاً أولاً');
      return;
    }
    setState(() => _lookingUp = true);
    try {
      final found = await ref
          .read(customerProfileProvider.notifier)
          .lookupCustomerByPhone(_phone.text);
      if (!mounted) return;
      if (found) {
        final p = ref.read(customerProfileProvider);
        _name.text    = p.name;
        _wilaya.text  = p.wilaya;
        _commune.text = p.commune;
        _address.text = p.addressText;
        setState(() {
          _lat = p.latitude;
          _lng = p.longitude;
        });
        _toast('تم استرجاع بيانات حسابك بنجاح');
      } else {
        _toast('لا يوجد حساب بهذا الرقم، أكمل البيانات لإنشاء حساب جديد');
      }
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      _toast(msg.isNotEmpty ? msg : 'تعذر البحث الآن، تحقق من الاتصال');
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final notifier = ref.read(customerProfileProvider.notifier);
    final hadAccount = ref.read(customerProfileProvider).hasAccount;
    final online = ref.read(customerIsOnlineProvider);

    notifier.updateProfile(
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      wilaya: _wilaya.text.trim(),
      commune: _commune.text.trim(),
      addressText: _address.text.trim(),
      latitude: _lat,
      longitude: _lng,
    );

    // Existing accounts can be edited offline: the local change is kept and
    // the sync coordinator pushes it once connectivity returns.
    if (!online) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (hadAccount) {
        _toast('حُفظت التعديلات على جهازك وستُزامن تلقائياً عند عودة الاتصال.');
        if (!widget.isSetup && Navigator.of(context).canPop()) {
          Navigator.pop(context);
        }
      } else {
        _toast('إنشاء حساب جديد يحتاج اتصالاً بالإنترنت. تحقق من الشبكة ثم أعد المحاولة.');
      }
      return;
    }

    try {
      await notifier.syncWithDatabase();
      if (!mounted) return;
      setState(() => _saving = false);
      if (!widget.isSetup) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (hadAccount) {
        _toast('تعذر الاتصال بالمتجر. حُفظت التعديلات محلياً وستُزامن لاحقاً.');
        if (!widget.isSetup && Navigator.of(context).canPop()) {
          Navigator.pop(context);
        }
        return;
      }
      final msg = e.toString().replaceFirst('Exception: ', '');
      _toast(msg.isNotEmpty ? msg : 'تعذر حفظ البيانات');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isSetup,
        leading: widget.isSetup && widget.onExit != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'العودة',
                onPressed: widget.onExit,
              )
            : null,
        title: Text(widget.isSetup ? 'إنشاء الحساب' : 'بيانات التوصيل'),
      ),

      // ── Save button ───────────────────────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
          child: GoldButton.icon(
            icon: widget.isSetup
                ? Icons.rocket_launch_rounded
                : Icons.check_rounded,
            label: _saving
                ? 'جاري الحفظ...'
                : (widget.isSetup ? 'حفظ والبدء بالتسوق' : 'حفظ التعديلات'),
            onPressed: _saving ? null : _save,
            loading: _saving,
            width: double.infinity,
            height: 52,
          ),
        ),
      ),

      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
              children: [
                // ── Onboarding hero (setup mode only) ──────────────────
                if (widget.isSetup) ...[
                  _OnboardingHero(isDark: isDark, theme: theme),
                  const SizedBox(height: AppSpacing.xl),
                ],

                // ── Phone + lookup ─────────────────────────────────────
                const SectionHeader(title: 'رقم الهاتف'),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  validator: _validatePhone,
                  decoration: InputDecoration(
                    labelText: 'رقم الهاتف *',
                    helperText:
                        'لديك حساب سابق؟ اضغط بحث لاسترجاع بياناتك',
                    prefixIcon: const Icon(Icons.phone_rounded),
                    suffixIcon: _lookingUp
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator
                                    .adaptive(strokeWidth: 2)),
                          )
                        : IconButton(
                            tooltip: 'بحث عن حساب مسجل',
                            icon: const Icon(Icons.search_rounded),
                            onPressed: _lookup,
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // ── Name ───────────────────────────────────────────────
                const SectionHeader(title: 'بيانات المحل'),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  validator: _required,
                  decoration: const InputDecoration(
                    labelText: 'اسم المحل / الزبون *',
                    prefixIcon: Icon(Icons.store_rounded),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // ── GPS detection ──────────────────────────────────────
                const SectionHeader(title: 'موقع التوصيل'),
                const SizedBox(height: AppSpacing.sm),
                _GpsCard(
                  lat: _lat,
                  lng: _lng,
                  locating: _locating,
                  onDetect: _detectGps,
                  isDark: isDark,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _wilaya,
                  textInputAction: TextInputAction.next,
                  validator: _required,
                  decoration: const InputDecoration(
                    labelText: 'الولاية *',
                    prefixIcon: Icon(Icons.map_rounded),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _commune,
                  textInputAction: TextInputAction.next,
                  validator: _required,
                  decoration: const InputDecoration(
                    labelText: 'البلدية *',
                    prefixIcon: Icon(Icons.location_city_rounded),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _address,
                  textInputAction: TextInputAction.done,
                  validator: _required,
                  decoration: const InputDecoration(
                    labelText: 'العنوان الدقيق / أقرب معلم *',
                    prefixIcon: Icon(Icons.location_on_rounded),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Onboarding Hero ───────────────────────────────────────────────────────────

class _OnboardingHero extends StatelessWidget {
  final bool isDark;
  final ThemeData theme;
  const _OnboardingHero({required this.isDark, required this.theme});

  @override
  Widget build(BuildContext context) {
    return LuxuryCard(
      goldAccent: true,
      padding: const EdgeInsetsDirectional.all(AppSpacing.xl),
      child: Column(
        children: [
          // Gold icon
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppGradients.gold,
              shape: BoxShape.circle,
              boxShadow: [AppShadows.goldGlow],
            ),
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Icon(Icons.storefront_rounded,
                  size: 36, color: Color(0xFF1A1400)),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'أهلاً بك في متجر الجملة VIP',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'نحتاج بيانات محلك الحقيقية لتوصيل طلبيتك. تُدخلها مرة واحدة وتُحفظ على جهازك.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark
                  ? const Color(0xFFB8A882)
                  : const Color(0xFF9A8A60),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const GoldBadge(
            label: 'تسجيل مجاني · بدون كلمة مرور',
            icon: Icons.lock_open_rounded,
          ),
        ],
      ),
    );
  }
}

// ── GPS Card ──────────────────────────────────────────────────────────────────

class _GpsCard extends StatelessWidget {
  final double? lat;
  final double? lng;
  final bool locating;
  final VoidCallback onDetect;
  final bool isDark;

  const _GpsCard({
    required this.lat,
    required this.lng,
    required this.locating,
    required this.onDetect,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final hasLocation = lat != null && lng != null;
    final theme = Theme.of(context);
    final colors = context.appColors;

    return LuxuryCard(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      child: Row(
        children: [
          // Icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: hasLocation ? AppGradients.gold : null,
              color: hasLocation
                  ? null
                  : (isDark
                      ? const Color(0xFF2A2518)
                      : const Color(0xFFF3E8C8)),
              borderRadius: AppRadius.smAll,
              boxShadow: hasLocation ? [AppShadows.goldGlowSm] : null,
            ),
            child: Icon(
              hasLocation ? Icons.location_on_rounded : Icons.my_location_rounded,
              size: 20,
              color: hasLocation
                  ? const Color(0xFF1A1400)
                  : (isDark
                      ? const Color(0xFFF3D278)
                      : const Color(0xFFC59B27)),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasLocation ? 'تم حفظ الموقع' : 'تحديد الموقع تلقائياً',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: hasLocation
                        ? (isDark
                            ? const Color(0xFFF3D278)
                            : const Color(0xFFC59B27))
                        : null,
                  ),
                ),
                if (hasLocation)
                  Text(
                    '${lat!.toStringAsFixed(4)}, ${lng!.toStringAsFixed(4)}',
                    style: TextStyle(
                        fontSize: 11, color: colors.success),
                  )
                else
                  Text(
                    'يساعد السائق على التوصيل بدقة',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          locating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : GoldIconButton(
                  icon: hasLocation
                      ? Icons.refresh_rounded
                      : Icons.gps_fixed_rounded,
                  tooltip: hasLocation ? 'تحديث الموقع' : 'تحديد الموقع',
                  onPressed: onDetect,
                  size: 36,
                  filled: hasLocation,
                ),
        ],
      ),
    );
  }
}
