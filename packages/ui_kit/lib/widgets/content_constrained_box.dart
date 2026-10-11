import 'package:flutter/material.dart';

/// Container constraining content width on large screens according to UX/UI Design Rules Section 2.2.
class ContentConstrainedBox extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry padding;

  const ContentConstrainedBox({
    super.key,
    required this.child,
    this.maxWidth = 640.0,
    this.alignment = Alignment.topCenter,
    this.padding = EdgeInsets.zero,
  });

  /// Standard form container (max 560-640 dp centered)
  const ContentConstrainedBox.form({
    super.key,
    required this.child,
    this.maxWidth = 560.0,
    this.alignment = Alignment.topCenter,
    this.padding = EdgeInsets.zero,
  });

  /// Standard dashboard container (max 1440 dp centered)
  const ContentConstrainedBox.dashboard({
    super.key,
    required this.child,
    this.maxWidth = 1440.0,
    this.alignment = Alignment.topCenter,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}
