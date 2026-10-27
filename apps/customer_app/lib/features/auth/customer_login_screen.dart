import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/customer_providers.dart';

/// Customer entry point: phone + password login — Algomend brand identity.
///
/// Uses Supabase Auth `signInWithPassword(phone, password)`. The server
/// resolves the customer profile from the JWT. No phone number or customer id
/// is trusted from the client.
class CustomerLoginScreen extends ConsumerStatefulWidget {
  const CustomerLoginScreen({super.key});

  @override
  ConsumerState<CustomerLoginScreen> createState() =>
      _CustomerLoginScreenState();
}

class _CustomerLoginScreenState extends ConsumerState<CustomerLoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;

  // ── Algomend brand colors ─────────────────────────────────────────────────
  static const _green = Color(0xFF1DAB61);    // Wrench Green
  static const _teal = Color(0xFF034F40);     // Circuit Teal
  static const _black = Color(0xFF111111);    // Typography Black
  static const _gray = Color(0xFF333333);     // Tagline Gray

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    if (phone.isEmpty) {
      setState(() => _error = 'أدخل رقم هاتفك أولاً.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'أدخل كلمة المرور.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(customerAuthStateProvider.notifier)
          .signIn(phone: phone, password: password);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendly(e);
      });
    }
  }

  String _friendly(Object error) {
    final message = error.toString();
    if (message.contains('Invalid login credentials')) {
      return 'رقم الهاتف أو كلمة المرور غير صحيحة.';
    }
    if (message.contains('Email not confirmed') ||
        message.contains('Phone not confirmed')) {
      return 'الحساب غير مفعّل. راجع المتجر.';
    }
    if (message.contains('Signups not allowed')) {
      return 'التسجيل مغلق حالياً. راجع المتجر.';
    }
    if (message.contains('Too many requests')) {
      return 'محاولات كثيرة جداً، يرجى الانتظار قليلاً.';
    }
    return message
        .replaceFirst('AuthException(message: ', '')
        .replaceFirst('Exception: ', '')
        .split(',')
        .first
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceBg =
        isDark ? const Color(0xFF0B130F) : const Color(0xFFF6FAF7);
    final cardBg =
        isDark ? const Color(0xFF131B16) : Colors.white;
    final borderColor =
        isDark ? const Color(0xFF2C352F) : const Color(0xFFD7E5DC);
    final onSurface = isDark ? const Color(0xFFDCE9E1) : _black;
    final onSurfaceVariant =
        isDark ? const Color(0xFFB2C9BC) : _gray;
    final inputFill = isDark ? const Color(0xFF171F1A) : const Color(0xFFEEF5F0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: surfaceBg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Algomend Logo SVG ─────────────────────────────────
                    _AlgomendLogo(size: 80),
                    const SizedBox(height: 16),
                    // ── Brand name ────────────────────────────────────────
                    Text(
                      'Algomend',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'DIGITAL SYSTEMS & ENTERPRISE SOLUTIONS',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'OpenSans',
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _teal,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 48,
                      height: 3,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_green, _teal],
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'تسجيل الدخول',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'ادخل برقم هاتفك وكلمة المرور للوصول إلى حسابك.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'OpenSans',
                        fontSize: 13,
                        color: onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    // ── Login card ────────────────────────────────────────
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderColor),
                        boxShadow: isDark
                            ? null
                            : [
                                BoxShadow(
                                  color: _green.withValues(alpha: 0.08),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Phone ─────────────────────────────────────
                          _AlgomendTextField(
                            controller: _phoneController,
                            enabled: !_busy,
                            keyboardType: TextInputType.phone,
                            textDirection: TextDirection.ltr,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [
                              AutofillHints.telephoneNumber,
                            ],
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9+]'),
                              ),
                            ],
                            onSubmitted: (_) =>
                                _passwordFocus.requestFocus(),
                            labelText: 'رقم الهاتف',
                            hintText: '0550123456',
                            prefixIcon: Icons.phone_iphone_rounded,
                            fillColor: inputFill,
                            borderColor: borderColor,
                            focusColor: _green,
                            isDark: isDark,
                            onSurfaceVariant: onSurfaceVariant,
                          ),
                          const SizedBox(height: 14),
                          // ── Password ──────────────────────────────────
                          _AlgomendTextField(
                            controller: _passwordController,
                            focusNode: _passwordFocus,
                            enabled: !_busy,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onSubmitted: (_) => _signIn(),
                            labelText: 'كلمة المرور',
                            hintText: '••••••••',
                            prefixIcon: Icons.lock_outline_rounded,
                            fillColor: inputFill,
                            borderColor: borderColor,
                            focusColor: _green,
                            isDark: isDark,
                            onSurfaceVariant: onSurfaceVariant,
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'إظهار كلمة المرور'
                                  : 'إخفاء كلمة المرور',
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: onSurfaceVariant,
                                size: 20,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          // ── Sign-in button ────────────────────────────
                          SizedBox(
                            height: 50,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: _busy
                                    ? null
                                    : const LinearGradient(
                                        colors: [_green, _teal],
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      ),
                                color: _busy
                                    ? (_green.withValues(alpha: 0.5))
                                    : null,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: _busy
                                    ? null
                                    : [
                                        BoxShadow(
                                          color: _green.withValues(
                                              alpha: 0.38),
                                          blurRadius: 14,
                                          offset: const Offset(0, 5),
                                        ),
                                      ],
                              ),
                              child: ElevatedButton(
                                onPressed: _busy ? null : _signIn,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: const [
                                          Icon(Icons.login_rounded, size: 18),
                                          SizedBox(width: 8),
                                          Text(
                                            'تسجيل الدخول',
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFDAD6),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: const Color(0xFFFF6B6B),
                                    width: 0.8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.error_outline_rounded,
                                    color: Color(0xFFBA1A1A),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: const TextStyle(
                                        color: Color(0xFF410002),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // ── Footer note ───────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'كلمة المرور تُقدَّم من Algomend عند إنشاء حسابك.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'OpenSans',
                              fontSize: 12,
                              color: onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Algomend "A + Circuit + Wrench" logo rendered in Flutter via CustomPainter.
// ─────────────────────────────────────────────────────────────────────────────
class _AlgomendLogo extends StatelessWidget {
  final double size;
  const _AlgomendLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1DAB61).withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: EdgeInsets.all(size * 0.12),
      child: CustomPaint(
        painter: _AlgomendLogoPainter(),
      ),
    );
  }
}

class _AlgomendLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Gradient for the wrench (green side)
    final gradientPaint = Paint()
      ..shader = LinearGradient(
        colors: const [Color(0xFF1DAB61), Color(0xFF034F40)],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075;

    // Dark paint for the "A" letter body
    final darkPaint = Paint()
      ..color = const Color(0xFF111111)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075;

    // ── Draw the "A" shape (circuit-style) ──────────────────────────────────
    // Left leg of A
    final aPath = Path()
      ..moveTo(w * 0.15, h * 0.85)
      ..lineTo(w * 0.50, h * 0.08)
      ..lineTo(w * 0.85, h * 0.85);
    canvas.drawPath(aPath, darkPaint);

    // Crossbar of A
    final crossbar = Path()
      ..moveTo(w * 0.30, h * 0.55)
      ..lineTo(w * 0.70, h * 0.55);
    canvas.drawPath(crossbar, darkPaint);

    // ── Circuit nodes on left leg ──────────────────────────────────────────
    final nodePaint = Paint()
      ..color = const Color(0xFF111111)
      ..style = PaintingStyle.fill;
    final r = w * 0.04;
    canvas.drawCircle(Offset(w * 0.25, h * 0.67), r, nodePaint);
    canvas.drawCircle(Offset(w * 0.38, h * 0.40), r, nodePaint);

    // ── Wrench handle (green diagonal) ────────────────────────────────────
    final wrenchPath = Path()
      ..moveTo(w * 0.62, h * 0.12)
      ..lineTo(w * 0.90, h * 0.42);
    canvas.drawPath(wrenchPath, gradientPaint);

    // Wrench head circle
    final wrenchHeadPaint = Paint()
      ..color = const Color(0xFF1DAB61)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.88, h * 0.16), w * 0.12, wrenchHeadPaint);
    // Inner hole
    final holePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.88, h * 0.16), w * 0.055, holePaint);

    // Circuit nodes on right side (green)
    final greenNodePaint = Paint()
      ..color = const Color(0xFF1DAB61)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.75, h * 0.67), r, greenNodePaint);
    canvas.drawCircle(Offset(w * 0.63, h * 0.35), r, greenNodePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom text field styled for Algomend brand.
// ─────────────────────────────────────────────────────────────────────────────
class _AlgomendTextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextDirection? textDirection;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;
  final String labelText;
  final String hintText;
  final IconData prefixIcon;
  final Widget? suffixIcon;
  final Color fillColor;
  final Color borderColor;
  final Color focusColor;
  final bool isDark;
  final Color onSurfaceVariant;

  const _AlgomendTextField({
    required this.controller,
    required this.labelText,
    required this.hintText,
    required this.prefixIcon,
    required this.fillColor,
    required this.borderColor,
    required this.focusColor,
    required this.isDark,
    required this.onSurfaceVariant,
    this.focusNode,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.textDirection,
    this.textInputAction,
    this.autofillHints,
    this.inputFormatters,
    this.onSubmitted,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textDirection: textDirection,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      inputFormatters: inputFormatters,
      onSubmitted: onSubmitted,
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        color: isDark ? const Color(0xFFDCE9E1) : const Color(0xFF111111),
      ),
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        filled: true,
        fillColor: fillColor,
        labelStyle: TextStyle(
          fontFamily: 'OpenSans',
          color: onSurfaceVariant,
          fontSize: 13,
        ),
        hintStyle: TextStyle(
          fontFamily: 'OpenSans',
          color: onSurfaceVariant.withValues(alpha: 0.6),
          fontSize: 13,
        ),
        prefixIcon: Icon(prefixIcon, size: 20, color: onSurfaceVariant),
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: focusColor, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}
