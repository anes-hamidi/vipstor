import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:ui_kit/ui_kit.dart';
import '../services/thermal_hardware_service.dart';

final activeUsbPrinterProvider = StateProvider<Printer?>((ref) => null);
final activeNetworkPrinterIpProvider = StateProvider<String>((ref) => '192.168.1.200');

class PrinterSettingsDialog extends ConsumerStatefulWidget {
  const PrinterSettingsDialog({super.key});

  @override
  ConsumerState<PrinterSettingsDialog> createState() => _PrinterSettingsDialogState();
}

class _PrinterSettingsDialogState extends ConsumerState<PrinterSettingsDialog> with SingleTickerProviderStateMixin {
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
    _startScanning();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ipController.dispose();
    _portController.dispose();
    ThermalHardwareService.stopScan();
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

    // Simple test receipt raw ESC/POS bytes
    final testBytes = [
      0x1B, 0x40, // Init
      0x1B, 0x61, 0x01, // Center
      ... 'VIP POS SYSTEM\n'.codeUnits,
      ... 'LAN PRINTER TEST OK\n'.codeUnits,
      ... 'PORT 9100 CONNECTED\n'.codeUnits,
      ... '--------------------------------\n'.codeUnits,
      0x1B, 0x64, 0x03, // Feed 3 lines
      0x1D, 0x56, 0x41, 0x00, // Cut paper
    ];

    final success = await ThermalHardwareService.printOverNetwork(
      ipAddress: ip,
      port: port,
      bytes: testBytes,
    );

    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _statusMessage = success ? '✓ تم الاتصال والطباعة بنجاح!' : '❌ فشل الاتصال بالطابعة عبر الشبكة';
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
        content: Text(ok ? '✓ تم إرسال نبضة فتح درج النقود!' : 'تعذر فتح درج النقود، تأكد من توصيل الطابعة'),
        backgroundColor: ok ? context.appColors.success : Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colors = context.appColors;

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsetsDirectional.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: AppRadius.smAll,
                    ),
                    child: Icon(Icons.print_outlined, color: colorScheme.onPrimaryContainer, size: 24),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'إعدادات واكتشاف طابعات الإيصالات الحرارية',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),

              // Tabs
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.usb, size: 18), text: 'طابعات USB / Bluetooth'),
                  Tab(icon: Icon(Icons.lan_outlined, size: 18), text: 'طابعة الشبكة LAN (IP)'),
                ],
              ),
              AppSpacing.gapMd,

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: USB / BLE Auto-Discovery
                    _buildUsbBleTab(theme, colorScheme, colors),

                    // Tab 2: Network LAN IP
                    _buildNetworkTab(theme, colorScheme, colors),
                  ],
                ),
              ),

              // Bottom Actions
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  OutlinedButton.icon(
                    onPressed: _testDrawerKick,
                    icon: const Icon(Icons.point_of_sale_outlined, size: 18),
                    label: const Text('اختبار فتح درج النقود (Cash Drawer)'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('حفظ وإغلاق'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUsbBleTab(ThemeData theme, ColorScheme colorScheme, AppColors colors) {
    final activeUsb = ref.watch(activeUsbPrinterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'الطابعات المتصلة والمكتشفة تلقائياً:',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            IconButton.filledTonal(
              tooltip: 'إعادة البحث عن الطابعات',
              icon: _isScanning
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator.adaptive(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 18),
              onPressed: _isScanning ? null : _startScanning,
            ),
          ],
        ),
        AppSpacing.gapSm,
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
                      Icon(Icons.print_disabled_outlined, size: 48, color: colorScheme.outlineVariant),
                      AppSpacing.gapSm,
                      const Text('لم يتم العثور على طابعات USB أو Bluetooth متصلة'),
                      const SizedBox(height: 4),
                      Text(
                        'تأكد من توصيل كابل USB للطابعة وتشغيلها ثم اضغط زر التحديث',
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                      AppSpacing.gapMd,
                      FilledButton.tonalIcon(
                        onPressed: _startScanning,
                        icon: const Icon(Icons.refresh, size: 16),
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
                      backgroundColor: isSelected ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
                      child: Icon(
                        printer.connectionType == ConnectionType.USB ? Icons.usb : Icons.bluetooth,
                        color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      printer.name ?? 'طابعة إيصالات حرارية',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    subtitle: Text(
                      'النوع: ${printer.connectionType?.name ?? "USB"} | الحالة: ${printer.isConnected == true ? "متصل" : "جاهز"}',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (printer.isConnected == true)
                          FilledButton.tonal(
                            onPressed: () async {
                              final testBytes = [
                                0x1B, 0x40,
                                0x1B, 0x61, 0x01,
                                ...'VIP THERMAL PRINTER TEST\n'.codeUnits,
                                ...'USB/BLE CONNECTION OK\n'.codeUnits,
                                0x1B, 0x64, 0x03,
                                0x1D, 0x56, 0x41, 0x00,
                              ];
                              await ThermalHardwareService.printRawBytes(printer: printer, bytes: testBytes);
                            },
                            child: const Text('طباعة تجريبية', style: TextStyle(fontSize: 11)),
                          ),
                        const SizedBox(width: AppSpacing.xs),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: isSelected ? colors.success : colorScheme.primary,
                          ),
                          onPressed: () async {
                            if (printer.isConnected != true) {
                              await ThermalHardwareService.connectPrinter(printer);
                            }
                            ref.read(activeUsbPrinterProvider.notifier).state = printer;
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

  Widget _buildNetworkTab(ThemeData theme, ColorScheme colorScheme, AppColors colors) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSpacing.gapMd,
          Text(
            'ربط طابعة إيصالات عبر كابل الشبكة LAN (Port 9100):',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          AppSpacing.gapMd,
          TextField(
            controller: _ipController,
            decoration: const InputDecoration(
              labelText: 'عنوان IP للطابعة في الشبكة المحلية *',
              hintText: 'مثال: 192.168.1.200',
              prefixIcon: Icon(Icons.settings_ethernet),
              border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
            ),
          ),
          AppSpacing.gapMd,
          TextField(
            controller: _portController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'منفذ الطباعة (Port) *',
              hintText: '9100',
              prefixIcon: Icon(Icons.numbers),
              border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
            ),
          ),
          AppSpacing.gapLg,
          if (_statusMessage != null) ...[
            Container(
              padding: const EdgeInsetsDirectional.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: _statusMessage!.startsWith('✓') ? colors.successContainer : colorScheme.errorContainer,
                borderRadius: AppRadius.mdAll,
              ),
              child: Text(
                _statusMessage!,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _statusMessage!.startsWith('✓') ? colors.onSuccessContainer : colorScheme.onErrorContainer,
                ),
              ),
            ),
            AppSpacing.gapMd,
          ],
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _isTesting ? null : _testNetworkPrinter,
            icon: _isTesting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator.adaptive(strokeWidth: 2))
                : const Icon(Icons.print),
            label: Text(_isTesting ? 'جاري اختبار الاتصال بالطابعة...' : 'اختبار اتصال وطباعة إيصال تجريبي'),
          ),
        ],
      ),
    );
  }
}
