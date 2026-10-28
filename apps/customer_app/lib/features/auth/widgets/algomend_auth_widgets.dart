import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Algomend brand colors shared by the customer auth screens.
const Color algomendGreen = Color(0xFF1DAB61);
const Color algomendTeal = Color(0xFF034F40);
const Color algomendBlack = Color(0xFF111111);
const Color algomendGray = Color(0xFF333333);

/// Common scaffold/header/card used by login, registration, and recovery.
class AlgomendAuthShell extends StatelessWidget {
  const AlgomendAuthShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.bottom,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceBg =
        isDark ? const Color(0xFF0B130F) : const Color(0xFFF6FAF7);
    final cardBg = isDark ? const Color(0xFF131B16) : Colors.white;
    final borderColor =
        isDark ? const Color(0xFF2C352F) : const Color(0xFFD7E5DC);
    final onSurface = isDark ? const Color(0xFFDCE9E1) : algomendBlack;
    final onSurfaceVariant = isDark ? const Color(0xFFB2C9BC) : algomendGray;

    return Scaffold(
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
                  const AlgomendLogo(size: 80),
                  const SizedBox(height: 16),
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
                  const Text(
                    'DIGITAL SYSTEMS & ENTERPRISE SOLUTIONS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'OpenSans',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: algomendTeal,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 48,
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [algomendGreen, algomendTeal],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'OpenSans',
                      fontSize: 13,
                      color: onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderColor),
                      boxShadow: isDark
                          ? null
                          : [
                              BoxShadow(
                                color: algomendGreen.withValues(alpha: 0.08),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                  if (bottom != null) ...[
                    const SizedBox(height: 20),
                    bottom!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AlgomendGradientButton extends StatelessWidget {
  const AlgomendGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.login_rounded,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: busy
              ? null
              : const LinearGradient(
                  colors: [algomendGreen, algomendTeal],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          color: busy ? algomendGreen.withValues(alpha: 0.5) : null,
          borderRadius: BorderRadius.circular(12),
          boxShadow: busy
              ? null
              : [
                  BoxShadow(
                    color: algomendGreen.withValues(alpha: 0.38),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
        ),
        child: ElevatedButton(
          onPressed: busy ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class AlgomendAuthError extends StatelessWidget {
  const AlgomendAuthError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFDAD6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFF6B6B), width: 0.8),
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
              message,
              style: const TextStyle(
                color: Color(0xFF410002),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Algomend "A + Circuit + Wrench" logo rendered in Flutter via CustomPainter.
// ─────────────────────────────────────────────────────────────────────────────
class AlgomendLogo extends StatelessWidget {
  final double size;

  const AlgomendLogo({super.key, required this.size});

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
            color: algomendGreen.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: EdgeInsets.all(size * 0.12),
      child: CustomPaint(painter: _AlgomendLogoPainter()),
    );
  }
}

class _AlgomendLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final gradientPaint = Paint()
      ..shader = const LinearGradient(
        colors: [algomendGreen, algomendTeal],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075;

    final darkPaint = Paint()
      ..color = algomendBlack
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075;

    final aPath = Path()
      ..moveTo(w * 0.15, h * 0.85)
      ..lineTo(w * 0.50, h * 0.08)
      ..lineTo(w * 0.85, h * 0.85);
    canvas.drawPath(aPath, darkPaint);

    final crossbar = Path()
      ..moveTo(w * 0.30, h * 0.55)
      ..lineTo(w * 0.70, h * 0.55);
    canvas.drawPath(crossbar, darkPaint);

    final nodePaint = Paint()
      ..color = algomendBlack
      ..style = PaintingStyle.fill;
    final r = w * 0.04;
    canvas.drawCircle(Offset(w * 0.25, h * 0.67), r, nodePaint);
    canvas.drawCircle(Offset(w * 0.38, h * 0.40), r, nodePaint);

    final wrenchPath = Path()
      ..moveTo(w * 0.62, h * 0.12)
      ..lineTo(w * 0.90, h * 0.42);
    canvas.drawPath(wrenchPath, gradientPaint);

    final wrenchHeadPaint = Paint()
      ..color = algomendGreen
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.88, h * 0.16), w * 0.12, wrenchHeadPaint);
    final holePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.88, h * 0.16), w * 0.055, holePaint);

    final greenNodePaint = Paint()
      ..color = algomendGreen
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
class AlgomendAuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextDirection? textDirection;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
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

  const AlgomendAuthTextField({
    super.key,
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
    this.textCapitalization = TextCapitalization.none,
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
      textCapitalization: textCapitalization,
      autofillHints: autofillHints,
      inputFormatters: inputFormatters,
      onSubmitted: onSubmitted,
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        color: isDark ? const Color(0xFFDCE9E1) : algomendBlack,
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
