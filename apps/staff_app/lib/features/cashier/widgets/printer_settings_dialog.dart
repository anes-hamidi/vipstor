import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:ui_kit/ui_kit.dart';
import '../services/thermal_hardware_service.dart';

final activeUsbPrinterProvider = StateProvider<Printer?>((ref) => null);
final activeNetworkPrinterIpProvider =
    StateProvider<String>((ref) => '192.168.1.200');

/// A responsive, high-fidelity screen for discovering, testing, and managing thermal receipt printers.
class PrinterSettingsDialog extends ConsumerStatefulWidget {
  final bool autoScan;

  const PrinterSettingsDialog({super.key, this.autoScan = true});

  /// Opens printer settings as a dedicated fullscreen screen route.
  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const PrinterSettingsDialog(),
      ),
    );
  }

  @override
  ConsumerState<PrinterSettingsDialog> createState() =>
      _PrinterSettingsDialogState();
}

class _PrinterSettingsDialogState extends ConsumerState<PrinterSettingsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '9100');

  bool _isScanning = false;
  bool _isTesting = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _ipController.text = ref.read(activeNetworkPrinterIpProvider);
    if (widget.autoScan) {
      _startScanning();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ipController.dispose();
    _portController.dispose();
    unawaited(ThermalHardwareService.stopScan());
    super.dispose();
  }

  void _startScanning() async {
    setState(() => _isScanning = true);
    await ThermalHardwareService.startScan();
    if (mounted) {
      setState(() => _isScanning = false);
    }
  }

  Future<void> _testNetworkPrinter() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 9100;
    if (ip.isEmpty) return;

    setState(() {
      _isTesting = true;
      _statusMessage = null;
    });

    final testBytes = [
      0x1B, 0x40,
      0x1B, 0x61, 0x01,
      ...'VIP POS SYSTEM\n'.codeUnits,
      ...'LAN PRINTER TEST OK\n'.codeUnits,
      ...'PORT 9100 CONNECTED\n'.codeUnits,
      ...'--------------------------------\n'.codeUnits,
      0x1B, 0x64, 0x03,
      0x1D, 0x56, 0x41, 0x00,
    ];

    final success = await ThermalHardwareService.printOverNetwork(
      ipAddress: ip,
      port: port,
      bytes: testBytes,
    );

    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _statusMessage = success
          ? '✓ تم الاتصال والطباعة بنجاح!'
          : '❌ فشل الاتصال بالطابعة عبر الشبكة';
    });

    if (success) {
      ref.read(activeNetworkPrinterIpProvider.notifier).state = ip;
    }
  }

  Future<void> _testDrawerKick() async {
    final activeUsb = ref.read(activeUsbPrinterProvider);
    final ip = _ipController.text.trim();

    final ok = await ThermalHardwareService.triggerCashDrawer(
      usbPrinter: activeUsb,
      networkIp: ip.isNotEmpty ? ip : null,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? '✓ تم إرسال نبضة فتح درج النقود!'
            : 'تعذر فتح درج النقود، تأكد من توصيل الطابعة'),
        backgroundColor: ok
            ? context.appColors.success
            : Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colors = context.appColors;
    final role = context.roleTheme;
    final brand = role.roleBrandColor;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: colorScheme.surface,
          appBar: AppBar(
            elevation: 0,
            scrolledUnderElevation: 2,
            backgroundColor: colorScheme.surfaceContainer,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'رجوع [Esc]',
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: role.badgeBackground,
                    borderRadius: AppRadius.smAll,
                    border: Border.all(color: brand.withValues(alpha: 0.30)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.print_rounded,
                        size: 20, color: role.badgeText),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'إعدادات طابعات الإيصالات الحرارية',
                        style:
                            TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'اكتشاف وتوصيل طابعات USB / Bluetooth وطابعات LAN 9100',
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding:
                    const EdgeInsetsDirectional.only(end: AppSpacing.md),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.point_of_sale_rounded, size: 16),
                  label: const Text('اختبار فتح الدرج (Kick)'),
                  onPressed: _testDrawerKick,
                ),
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 840;

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Column: USB & Bluetooth Printers
                    Expanded(
                      flex: 5,
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          border: BorderDirectional(
                            end: BorderSide(
                              color: colorScheme.outlineVariant
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                        child: _buildUsbBleTab(theme, colorScheme, colors, brand),
                      ),
                    ),
                    // Right Column: LAN Network Settings
                    Expanded(
                      flex: 4,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 500),
                            child: _buildNetworkTab(
                                theme, colorScheme, colors, brand),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              // Mobile Layout
              return Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(
                        icon: Icon(Icons.usb_rounded, size: 18),
                        text: 'طابعات USB / Bluetooth',
                      ),
                      Tab(
                        icon: Icon(Icons.lan_rounded, size: 18),
                        text: 'طابعة الشبكة LAN (IP)',
                      ),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: _buildUsbBleTab(
                              theme, colorScheme, colors, brand),
                        ),
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: _buildNetworkTab(
                              theme, colorScheme, colors, brand),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildUsbBleTab(ThemeData theme, ColorScheme colorScheme,
      dynamic colors, Color brand) {
    final activeUsb = ref.watch(activeUsbPrinterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'الطابعات المتصلة والمكتشفة تلقائيًا:',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton.tonalIcon(
              icon: _isScanning
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('تحديث المنافذ'),
              onPressed: _isScanning ? null : _startScanning,
            ),
          ],
        ),
        AppSpacing.gapMd,
        Expanded(
          child: StreamBuilder<List<Printer>>(
            stream: ThermalHardwareService.devicesStream,
            builder: (context, snapshot) {
              final printers = snapshot.data ?? [];

              if (printers.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.print_disabled_outlined,
                          size: 56, color: colorScheme.outlineVariant),
                      AppSpacing.gapSm,
                      const Text(
                        'لم يتم العثور على طابعات USB أو Bluetooth متصلة',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'تأكد من توصيل كابل USB للطابعة وتشغيلها ثم اضغط زر التحديث',
                        style: theme.textTheme.bodySmall,
                      ),
                      AppSpacing.gapMd,
                      FilledButton.tonalIcon(
                        onPressed: _startScanning,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('البحث الآن'),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                itemCount: printers.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, idx) {
                  final printer = printers[idx];
                  final isSelected = activeUsb?.name == printer.name;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSelected
                          ? colors.successContainer
                          : colorScheme.surfaceContainerHighest,
                      child: Icon(
                        printer.connectionType == ConnectionType.USB
                            ? Icons.usb_rounded
                            : Icons.bluetooth_rounded,
                        color: isSelected
                            ? colors.onSuccessContainer
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    title: Text(
                      printer.name ?? 'طابعة إيصالات حرارية 80mm',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'النوع: ${printer.connectionType?.name ?? "USB"} | الحالة: ${printer.isConnected == true ? "متصل" : "جاهز"}',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (printer.isConnected == true)
                          OutlinedButton(
                            onPressed: () async {
                              final testBytes = [
                                0x1B, 0x40,
                                0x1B, 0x61, 0x01,
                                ...'VIP THERMAL PRINTER TEST\n'.codeUnits,
                                ...'USB/BLE CONNECTION OK\n'.codeUnits,
                                0x1B, 0x64, 0x03,
                                0x1D, 0x56, 0x41, 0x00,
                              ];
                              await ThermalHardwareService.printRawBytes(
                                  printer: printer, bytes: testBytes);
                            },
                            child: const Text('طباعة تجريبية',
                                style: TextStyle(fontSize: 11)),
                          ),
                        const SizedBox(width: AppSpacing.xs),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                isSelected ? colors.success : colorScheme.primary,
                          ),
                          onPressed: () async {
                            if (printer.isConnected != true) {
                              await ThermalHardwareService.connectPrinter(
                                  printer);
                            }
                            ref.read(activeUsbPrinterProvider.notifier).state =
                                printer;
                            setState(() {});
                          },
                          child: Text(isSelected ? '✓ المحددة' : 'تحديد'),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkTab(ThemeData theme, ColorScheme colorScheme,
      dynamic colors, Color brand) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ربط طابعة إيصالات عبر كابل الشبكة LAN (Port 9100):',
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'تتيح الطباعة المباشرة من أجهزة التابلت والهواتف عبر بروتوكول Raw TCP',
          style: theme.textTheme.bodySmall,
        ),
        AppSpacing.gapLg,
        TextField(
          controller: _ipController,
          decoration: InputDecoration(
            labelText: 'عنوان IP للطابعة في الشبكة المحلية *',
            hintText: 'مثال: 192.168.1.200',
            prefixIcon: const Icon(Icons.settings_ethernet_rounded),
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
            border: const OutlineInputBorder(borderRadius: AppRadius.mdAll),
          ),
        ),
        AppSpacing.gapMd,
        TextField(
          controller: _portController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'منفذ الطباعة (Port) *',
            hintText: '9100',
            prefixIcon: const Icon(Icons.numbers_rounded),
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
            border: const OutlineInputBorder(borderRadius: AppRadius.mdAll),
          ),
        ),
        AppSpacing.gapLg,
        if (_statusMessage != null) ...[
          Container(
            padding: const EdgeInsetsDirectional.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: _statusMessage!.startsWith('✓')
                  ? colors.successContainer
                  : colorScheme.errorContainer,
              borderRadius: AppRadius.mdAll,
            ),
            child: Text(
              _statusMessage!,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _statusMessage!.startsWith('✓')
                    ? colors.onSuccessContainer
                    : colorScheme.onErrorContainer,
              ),
            ),
          ),
          AppSpacing.gapMd,
        ],
        GoldButton.icon(
          onPressed: _isTesting ? null : _testNetworkPrinter,
          icon: _isTesting
              ? Icons.hourglass_top_rounded
              : Icons.print_rounded,
          label: _isTesting
              ? 'جاري اختبار الاتصال...'
              : 'اختبار اتصال وطباعة إيصال تجريبي',
        ),
      ],
    );
  }
}
