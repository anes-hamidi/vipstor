import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PosKeyboardDispatcher extends StatelessWidget {
  final Widget child;
  final VoidCallback onF1Search;
  final VoidCallback onF2Customer;
  final VoidCallback onF3CustomItem;
  final VoidCallback onF4HoldCart;
  final VoidCallback onF5ResumeCart;
  final VoidCallback? onF6PrinterSettings;
  final VoidCallback? onF7CollectDebt;
  final VoidCallback onF8SalesHistory;
  final VoidCallback onF9Returns;
  final VoidCallback onF10ZReport;
  final VoidCallback? onF11LockScreen;
  final VoidCallback onF12Checkout;
  final VoidCallback onEscapeClear;

  const PosKeyboardDispatcher({
    super.key,
    required this.child,
    required this.onF1Search,
    required this.onF2Customer,
    required this.onF3CustomItem,
    required this.onF4HoldCart,
    required this.onF5ResumeCart,
    this.onF6PrinterSettings,
    this.onF7CollectDebt,
    required this.onF8SalesHistory,
    required this.onF9Returns,
    required this.onF10ZReport,
    this.onF11LockScreen,
    required this.onF12Checkout,
    required this.onEscapeClear,
  });

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.f1): onF1Search,
        const SingleActivator(LogicalKeyboardKey.f2): onF2Customer,
        const SingleActivator(LogicalKeyboardKey.f3): onF3CustomItem,
        const SingleActivator(LogicalKeyboardKey.f4): onF4HoldCart,
        const SingleActivator(LogicalKeyboardKey.f5): onF5ResumeCart,
        if (onF6PrinterSettings != null)
          const SingleActivator(LogicalKeyboardKey.f6): onF6PrinterSettings!,
        if (onF7CollectDebt != null)
          const SingleActivator(LogicalKeyboardKey.f7): onF7CollectDebt!,
        const SingleActivator(LogicalKeyboardKey.f8): onF8SalesHistory,
        const SingleActivator(LogicalKeyboardKey.f9): onF9Returns,
        const SingleActivator(LogicalKeyboardKey.f10): onF10ZReport,
        if (onF11LockScreen != null)
          const SingleActivator(LogicalKeyboardKey.f11): onF11LockScreen!,
        const SingleActivator(LogicalKeyboardKey.f12): onF12Checkout,
        const SingleActivator(LogicalKeyboardKey.escape): onEscapeClear,
      },
      child: Focus(
        autofocus: true,
        child: child,
      ),
    );
  }
}
