import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';

class PdfInvoiceService {
  static pw.ThemeData? _cachedTheme;

  /// Loads Arabic fonts with full Unicode and fallback support (Cairo, Amiri, Noto Sans Arabic)
  static Future<pw.ThemeData> getArabicTheme() async {
    if (_cachedTheme != null) return _cachedTheme!;
    try {
      final cairo = await PdfGoogleFonts.cairoRegular();
      final cairoBold = await PdfGoogleFonts.cairoBold();
      final amiri = await PdfGoogleFonts.amiriRegular();
      final noto = await PdfGoogleFonts.notoSansArabicRegular();

      _cachedTheme = pw.ThemeData.withFont(
        base: cairo,
        bold: cairoBold,
        fontFallback: [cairo, cairoBold, amiri, noto],
      );
      return _cachedTheme!;
    } catch (_) {
      try {
        final cairo = await PdfGoogleFonts.cairoRegular();
        final cairoBold = await PdfGoogleFonts.cairoBold();
        _cachedTheme = pw.ThemeData.withFont(
          base: cairo,
          bold: cairoBold,
          fontFallback: [cairo, cairoBold],
        );
        return _cachedTheme!;
      } catch (_) {
        return pw.ThemeData.base();
      }
    }
  }

  /// Generates and previews/prints an Official Bilingual Delivery Note (وصل تسليم بضاعة / Bon de Livraison)
  static Future<void> printDeliverySlip(OrderEntity order) async {
    final doc = await buildDeliverySlipDocument(order);
    final orderNum = order.orderNumber ?? (order.id.length > 8 ? order.id.substring(0, 8) : order.id);
    await Printing.layoutPdf(
      name: 'Bon_Livraison_$orderNum.pdf',
      onLayout: (PdfPageFormat format) async => doc.save(),
    );
  }

  /// Builds the Document for Delivery Slip
  static Future<pw.Document> buildDeliverySlipDocument(OrderEntity order) async {
    final theme = await getArabicTheme();
    final doc = pw.Document(theme: theme);
    final orderNum = order.orderNumber ?? (order.id.length > 8 ? order.id.substring(0, 8) : order.id);

    final customerName = order.customerName ??
        order.customerSnapshot?['customer_name'] ??
        order.customerSnapshot?['store_name'] ??
        order.customerSnapshot?['name'] ??
        'زبون مسجل';
    final customerPhone = order.customerPhone ??
        order.customerSnapshot?['phone'] ??
        order.customerSnapshot?['customer_phone'] ??
        '';
    final addressText = order.customerSnapshot?['address'] ??
        order.customerSnapshot?['address_text'] ??
        '';
    final wilaya = order.customerSnapshot?['wilaya'] ?? '';
    final commune = order.customerSnapshot?['commune'] ?? '';
    final fullAddress = [addressText, commune, wilaya].where((s) => s.toString().trim().isNotEmpty).join(' - ');

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(16),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // Header Banner
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blueGrey50,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                    border: pw.Border.all(color: PdfColors.blueGrey200, width: 0.8),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'مؤسسة VIP للتجارة والتوزيع بالجملة',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13, color: PdfColors.blue900),
                          ),
                          pw.Text(
                            'VIP WHOLESALE & LOGISTICS DISTRIBUTION',
                            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                          ),
                          pw.Text(
                            'الهاتف: 0550000000 | الجزائر العاصمة',
                            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                          ),
                        ],
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.blue800,
                          borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                        ),
                        child: pw.Column(
                          children: [
                            pw.Text(
                              'وصل تسليم بضاعة',
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.white),
                            ),
                            pw.Text(
                              'BON DE LIVRAISON',
                              style: const pw.TextStyle(fontSize: 7, color: PdfColors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),

                // Order and Customer Meta Box
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Order Details
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Row(
                              children: [
                                pw.Text('رقم الطلبية / N°: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                                pw.Text('#$orderNum', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.blue800)),
                              ],
                            ),
                            pw.SizedBox(height: 2),
                            pw.Text('التاريخ: ${order.createdAt.toLocal().toString().split('.').first}', style: const pw.TextStyle(fontSize: 8)),
                            pw.Text('القناة: ${order.channel == OrderChannel.online ? "طلب تطبيق إلكتروني" : "مبيعات المتجر"}', style: const pw.TextStyle(fontSize: 8)),
                            if (order.driverName != null)
                              pw.Text('السائق المكلف: ${order.driverName}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.blue900)),
                          ],
                        ),
                      ),
                      pw.Container(width: 0.8, height: 50, color: PdfColors.grey300),
                      pw.SizedBox(width: 8),
                      // Customer Details
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('الزبون: $customerName', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                            if (customerPhone.isNotEmpty)
                              pw.Text('الهاتف: $customerPhone', style: const pw.TextStyle(fontSize: 8)),
                            if (fullAddress.isNotEmpty)
                              pw.Text('العنوان: $fullAddress', style: const pw.TextStyle(fontSize: 8)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),

                // Items Table
                pw.Text('قائمة السلع والكميات / Liste des Articles:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                pw.SizedBox(height: 4),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(0.6), // Index
                    1: const pw.FlexColumnWidth(3.8), // Product Name
                    2: const pw.FlexColumnWidth(2.0), // Qty + Unit
                    3: const pw.FlexColumnWidth(1.8), // Unit Price
                    4: const pw.FlexColumnWidth(1.8), // Line Total
                  },
                  children: [
                    // Table Header
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        _th('#'),
                        _th('السلعة / Désignation'),
                        _th('الكمية والنوع / Qté'),
                        _th('السعر (دج)'),
                        _th('المجموع (دج)'),
                      ],
                    ),
                    // Table Rows
                    ...order.items.asMap().entries.map((entry) {
                      final idx = entry.key + 1;
                      final it = entry.value;
                      final isEven = idx % 2 == 0;
                      return pw.TableRow(
                        decoration: isEven ? const pw.BoxDecoration(color: PdfColors.grey50) : const pw.BoxDecoration(),
                        children: [
                          _td('$idx', align: pw.TextAlign.center),
                          _td(it.productName, bold: true),
                          _td(it.formattedQuantityWithUnit, align: pw.TextAlign.center),
                          _td(DzdFormatter.formatCentimes(it.unitPriceCentimes)),
                          _td(DzdFormatter.formatCentimes(it.lineTotalCentimes), bold: true),
                        ],
                      );
                    }),
                  ],
                ),
                pw.SizedBox(height: 8),

                // Financial Summary
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('عدد الأصناف: ${order.items.length}', style: const pw.TextStyle(fontSize: 8)),
                          if (order.paidAmountCentimes > 0)
                            pw.Text('المدفوع نقداً: ${DzdFormatter.formatCentimes(order.paidAmountCentimes)}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.green800)),
                          if (order.dueAmountCentimes > 0)
                            pw.Text('المتبقي على الحساب (دين): ${DzdFormatter.formatCentimes(order.dueAmountCentimes)}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
                        ],
                      ),
                      pw.Row(
                        children: [
                          pw.Text('المبلغ الإجمالي المستحق:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                          pw.SizedBox(width: 8),
                          pw.Text(
                            DzdFormatter.formatCentimes(order.totalAmountCentimes),
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.blue900),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                 pw.Spacer(),

                // Barcode and Footer Signatures
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.BarcodeWidget(
                          barcode: pw.Barcode.code128(),
                          data: order.id,
                          height: 22,
                          width: 120,
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text('ID: ${order.id}', style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
                      ],
                    ),
                    pw.Container(
                      width: 140,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Text('توقيع واستلام الزبون', style: const pw.TextStyle(fontSize: 8)),
                          pw.SizedBox(height: 20),
                          pw.Container(height: 0.5, color: PdfColors.grey400),
                        ],
                      ),
                    ),
                    pw.Container(
                      width: 140,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Text('خاتم وتوقيع الإدارة', style: const pw.TextStyle(fontSize: 8)),
                          pw.SizedBox(height: 20),
                          pw.Container(height: 0.5, color: PdfColors.grey400),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Center(
                  child: pw.Text(
                    'شكراً لتعاملكم معنا - VIP Wholesale Management System',
                    style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return doc;
  }

  /// Generates and prints a Supplier Purchase Receiving Voucher (وصل استلام المشتريات)
  static Future<void> printPurchaseReceivingVoucher({
    required String invoiceNo,
    required String supplierName,
    required List<Map<String, dynamic>> items,
    required int totalCentimes,
    required String receivedByName,
  }) async {
    final theme = await getArabicTheme();
    final doc = pw.Document(theme: theme);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(16),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.amber50,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                    border: pw.Border.all(color: PdfColors.amber300, width: 0.8),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'مؤسسة VIP للتجارة والتوزيع',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13, color: PdfColors.amber900),
                          ),
                          pw.Text(
                            'وصل استلام مشتريات ودخول المخزون (Réception Achat)',
                            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                          ),
                        ],
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.amber800,
                          borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                        ),
                        child: pw.Text(
                          'BON DE RÉCEPTION',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('المورد: $supplierName', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      pw.Text('رقم فاتورة المورد: $invoiceNo', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      pw.Text('التاريخ: ${DateTime.now().toString().substring(0, 10)}', style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text('السلع المستلمة والمضافة لبطاقة المخزون:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                pw.SizedBox(height: 4),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(0.6),
                    1: const pw.FlexColumnWidth(3.8),
                    2: const pw.FlexColumnWidth(1.8),
                    3: const pw.FlexColumnWidth(1.8),
                    4: const pw.FlexColumnWidth(1.8),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        _th('#'),
                        _th('السلعة'),
                        _th('الكمية والنوع'),
                        _th('سعر الشراء (دج)'),
                        _th('المجموع (دج)'),
                      ],
                    ),
                    ...items.asMap().entries.map((entry) {
                      final idx = entry.key + 1;
                      final it = entry.value;
                      final name = it['product_name'] ?? it['name'] ?? '';
                      final qty = (it['qty'] ?? it['quantity'] ?? 1) as int;
                      final cost = (it['unit_cost'] ?? 0) as int;
                      final rawUnit = it['unit']?.toString();
                      final unitLabel = formatUnit(rawUnit);
                      final qtyDisplay = unitLabel.isNotEmpty ? '$qty $unitLabel' : '$qty';
                      final lineTotal = qty * cost;
                      return pw.TableRow(
                        children: [
                          _td('$idx', align: pw.TextAlign.center),
                          _td(name.toString(), bold: true),
                          _td(qtyDisplay, align: pw.TextAlign.center),
                          _td(DzdFormatter.formatCentimes(cost)),
                          _td(DzdFormatter.formatCentimes(lineTotal), bold: true),
                        ],
                      );
                    }),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('المسؤول المستلم: $receivedByName', style: const pw.TextStyle(fontSize: 8)),
                    pw.Row(
                      children: [
                        pw.Text('المجموع الإجمالي للفاتورة:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.SizedBox(width: 8),
                        pw.Text(
                          DzdFormatter.formatCentimes(totalCentimes),
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.amber900),
                        ),
                      ],
                    ),
                  ],
                ),
                 pw.Spacer(),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('توقيع مسؤول المخزن', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('توقيع وموافقة المورد', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                pw.SizedBox(height: 15),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      name: 'Reception_$invoiceNo.pdf',
      onLayout: (format) async => doc.save(),
    );
  }

  static String formatUnit(String? unit) {
    if (unit == null || unit.trim().isEmpty) return '';
    final u = unit.trim().toLowerCase();
    if (u.contains('boit') || u.contains('box') || u.contains('علب') || u.contains('صندوق')) {
      return 'علبة (Boîte)';
    } else if (u.contains('carton') || u.contains('كرتون')) {
      return 'كرتون (Carton)';
    } else if (u.contains('pack') || u.contains('طرد') || u.contains('حزم')) {
      return 'طرد (Pack)';
    } else if (u == 'kg' || u.contains('كغ') || u.contains('كيلو')) {
      return 'كغ (Kg)';
    } else if (u == 'g' || u.contains('غرام') || u == 'غ') {
      return 'غ (g)';
    } else if (u == 'l' || u.contains('لتر') || u.contains('litre')) {
      return 'لتر (L)';
    } else {
      return 'قطعة (Pièce)';
    }
  }

  static pw.Widget _th(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
      ),
    );
  }

  static pw.Widget _td(String text, {pw.TextAlign align = pw.TextAlign.start, bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(fontSize: 7.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
      ),
    );
  }
}
