import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:ui_kit/ui_kit.dart';
import '../../providers/customer_providers.dart';
import '../catalog/catalog_screen.dart';

/// App entry: shows the setup form until the customer has real info saved.
class ProfileGate extends ConsumerWidget {
  final VoidCallback? onExit;
  const ProfileGate({super.key, this.onExit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final complete = ref.watch(customerProfileProvider.select((p) => p.isComplete));
    return complete
        ? CatalogScreen(onExit: onExit)
        : ProfileFormScreen(isSetup: true, onExit: onExit);
  }
}

/// Used for first-time setup (isSetup: true) and for editing later (from cart).
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
    _phone = TextEditingController(text: p.phone);
    _name = TextEditingController(text: p.name);
    _wilaya = TextEditingController(text: p.wilaya);
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null;

  String? _validatePhone(String? v) {
    if (v == null || v.trim().isEmpty) return 'هذا الحقل مطلوب';
    if (!CustomerProfileInfo.isValidPhone(v)) {
      return 'أدخل رقماً صحيحاً مثل 0550123456';
    }
    return null;
  }

  Future<void> _detectGps() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
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
      _lat = pos.latitude;
      _lng = pos.longitude;
      try {
        final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (marks.isNotEmpty) {
          final m = marks.first;
          if ((m.administrativeArea ?? '').isNotEmpty) _wilaya.text = m.administrativeArea!;
          if ((m.locality ?? '').isNotEmpty) _commune.text = m.locality!;
          if ((m.street ?? '').isNotEmpty) {
            _address.text = '${m.street}, ${m.subLocality ?? ""}'.trim();
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
    if (!CustomerProfileInfo.isValidPhone(_phone.text)) {
      _toast('أدخل رقم هاتف صحيحاً أولاً');
      return;
    }
    setState(() => _lookingUp = true);
    try {
      final found = await ref
          .read(customerProfileProvider.notifier)
          .lookupCustomerByPhone(_phone.text);
      if (!mounted) return; // in setup mode the gate may already have moved on
      if (found) {
        final p = ref.read(customerProfileProvider);
        _name.text = p.name;
        _wilaya.text = p.wilaya;
        _commune.text = p.commune;
        _address.text = p.addressText;
        _lat = p.latitude;
        _lng = p.longitude;
        _toast('تم استرجاع بيانات حسابك');
      } else {
        _toast('لا يوجد حساب بهذا الرقم، أكمل البيانات لإنشاء حساب جديد');
      }
    } catch (_) {
      _toast('تعذر البحث الآن، تحقق من الاتصال');
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final notifier = ref.read(customerProfileProvider.notifier);
    // Saved on the device immediately; in setup mode the gate opens the catalog now.
    notifier.updateProfile(
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      wilaya: _wilaya.text.trim(),
      commune: _commune.text.trim(),
      addressText: _address.text.trim(),
      latitude: _lat,
      longitude: _lng,
    );
    try {
      await notifier.syncWithDatabase();
    } catch (_) {
      // Kept locally; checkout will sync again.
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (!widget.isSetup) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isSetup,
        leading: widget.isSetup && widget.onExit != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'العودة إلى البوابة',
                onPressed: widget.onExit,
              )
            : null,
        title: Text(widget.isSetup ? 'أكمل بياناتك' : 'بيانات التوصيل'),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(widget.isSetup ? 'حفظ والبدء بالتسوق' : 'حفظ التعديلات'),
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (widget.isSetup) ...[
                  Text('أهلاً بك في متجر الجملة',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(
                    'نحتاج بيانات محلك الحقيقية لتوصيل طلبيتك. تُدخلها مرة واحدة وتُحفظ على جهازك.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  AppSpacing.gapLg,
                ],
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  validator: _validatePhone,
                  decoration: InputDecoration(
                    labelText: 'رقم الهاتف *',
                    helperText: 'لديك حساب سابق؟ اضغط البحث لاسترجاع بياناتك',
                    prefixIcon: const Icon(Icons.phone),
                    suffixIcon: IconButton(
                      tooltip: 'بحث عن حساب مسجل',
                      onPressed: _lookingUp ? null : _lookup,
                      icon: _lookingUp
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator.adaptive(strokeWidth: 2))
                          : const Icon(Icons.search),
                    ),
                  ),
                ),
                AppSpacing.gapMd,
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  validator: _required,
                  decoration: const InputDecoration(
                      labelText: 'اسم المحل / الزبون *', prefixIcon: Icon(Icons.store)),
                ),
                AppSpacing.gapMd,
                OutlinedButton.icon(
                  onPressed: _locating ? null : _detectGps,
                  icon: _locating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator.adaptive(strokeWidth: 2))
                      : const Icon(Icons.my_location),
                  label: Text(_locating ? 'جاري تحديد الموقع...' : 'تحديد موقعي تلقائياً'),
                ),
                if (_lat != null && _lng != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'تم حفظ الإحداثيات (${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)})',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.primary),
                    ),
                  ),
                AppSpacing.gapMd,
                TextFormField(
                  controller: _wilaya,
                  textInputAction: TextInputAction.next,
                  validator: _required,
                  decoration: const InputDecoration(
                      labelText: 'الولاية *', prefixIcon: Icon(Icons.map)),
                ),
                AppSpacing.gapMd,
                TextFormField(
                  controller: _commune,
                  textInputAction: TextInputAction.next,
                  validator: _required,
                  decoration: const InputDecoration(
                      labelText: 'البلدية *', prefixIcon: Icon(Icons.location_city)),
                ),
                AppSpacing.gapMd,
                TextFormField(
                  controller: _address,
                  textInputAction: TextInputAction.done,
                  validator: _required,
                  decoration: const InputDecoration(
                      labelText: 'العنوان الدقيق / أقرب معلم *',
                      prefixIcon: Icon(Icons.location_on)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}