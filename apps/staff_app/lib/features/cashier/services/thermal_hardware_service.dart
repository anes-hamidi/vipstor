import 'dart:async';
import 'dart:io';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';

class ThermalHardwareService {
  static final _instance = FlutterThermalPrinter.instance;

  static Stream<List<Printer>> get devicesStream => _instance.devicesStream;

  /// 1. Start scanning for USB & BLE printers
  static Future<void> startScan() async {
    try {
      await _instance.getPrinters(connectionTypes: [
        ConnectionType.USB,
        ConnectionType.BLE,
      ]);
    } catch (_) {}
  }

  /// 2. Stop scanning
  static Future<void> stopScan() async {
    try {
      await _instance.stopScan();
    } catch (_) {}
  }

  /// 3. Connect to printer
  static Future<bool> connectPrinter(Printer printer) async {
    try {
      return await _instance.connect(printer);
    } catch (_) {
      return false;
    }
  }

  /// 4. Disconnect from printer
  static Future<void> disconnectPrinter(Printer printer) async {
    try {
      await _instance.disconnect(printer);
    } catch (_) {}
  }

  /// 5. Direct Raw Socket Print (LAN / Network Thermal Printer on Port 9100)
  static Future<bool> printOverNetwork({
    required String ipAddress,
    int port = 9100,
    required List<int> bytes,
  }) async {
    try {
      final socket = await Socket.connect(
        ipAddress,
        port,
        timeout: const Duration(seconds: 4),
      );
      socket.add(bytes);
      await socket.flush();
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 6. Trigger Cash Drawer Kick (ESC p 0 25 250)
  static Future<bool> triggerCashDrawer({
    Printer? usbPrinter,
    String? networkIp,
  }) async {
    // ESC/POS Cash Drawer Kick Pin 2: ESC p 0 25 250
    final drawerKickBytes = [0x1B, 0x70, 0x00, 0x19, 0xFA];

    if (usbPrinter != null && usbPrinter.isConnected == true) {
      try {
        await _instance.printData(usbPrinter, drawerKickBytes);
        return true;
      } catch (_) {}
    }

    if (networkIp != null && networkIp.isNotEmpty) {
      return await printOverNetwork(ipAddress: networkIp, bytes: drawerKickBytes);
    }

    return false;
  }

  /// 7. Print Raw ESC/POS Receipt Bytes
  static Future<bool> printRawBytes({
    Printer? printer,
    String? networkIp,
    required List<int> bytes,
  }) async {
    if (printer != null && printer.isConnected == true) {
      try {
        await _instance.printData(printer, bytes);
        return true;
      } catch (_) {}
    }

    if (networkIp != null && networkIp.isNotEmpty) {
      return await printOverNetwork(ipAddress: networkIp, bytes: bytes);
    }

    return false;
  }
}
