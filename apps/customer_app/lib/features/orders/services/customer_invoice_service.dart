import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';


class CustomerInvoiceService {
  static pw.ThemeData? _cachedTheme;

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

  /// Customer Invoice Print & PDF Export
  static Future<void> printCustomerOrderInvoice(OrderEntity order) async {
    final theme = await getArabicTheme();
    final doc = pw.Document(theme: theme);
    final orderNum = order.orderNumber ?? (order.id.length > 8 ? order.id.substring(0, 8) : order.id);

    final customerName = order.customerName ??
        order.customerSnapshot?['customer_name'] ??
        order.customerSnapshot?['store_name'] ??
        'زبون مسجل';
    final customerPhone = order.customerPhone ??
        order.customerSnapshot?['phone'] ??
        '';
    final fullAddress = [
      order.customerSnapshot?['address'] ?? order.customerSnapshot?['address_text'],
      order.customerSnapshot?['commune'],
      order.customerSnapshot?['wilaya'],
    ].where((s) => s != null && s.toString().trim().isNotEmpty).join(' - ');

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
                // Header
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
                            'فاتورة طلبية زبون / Facture Client',
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
                        child: pw.Text(
                          'FACTURE #$orderNum',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),

                // Order Meta
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('رقم الطلب: #$orderNum', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                            pw.Text('التاريخ: ${order.createdAt.toLocal().toString().split('.').first}', style: const pw.TextStyle(fontSize: 8)),
                            if (order.driverName != null)
                              pw.Text('السائق المكلف: ${order.driverName}', style: const pw.TextStyle(fontSize: 8)),
                          ],
                        ),
                      ),
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
                pw.Text('السلع المطلوبة:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                pw.SizedBox(height: 4),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(0.8),
                    1: const pw.FlexColumnWidth(4.0),
                    2: const pw.FlexColumnWidth(1.2),
                    3: const pw.FlexColumnWidth(2.0),
                    4: const pw.FlexColumnWidth(2.0),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        _th('#'),
                        _th('السلعة / المنتج'),
                        _th('الكمية'),
                        _th('السعر (دج)'),
                        _th('المجموع (دج)'),
                      ],
                    ),
                    ...order.items.asMap().entries.map((entry) {
                      final idx = entry.key + 1;
                      final it = entry.value;
                      return pw.TableRow(
                        children: [
                          _td('$idx', align: pw.TextAlign.center),
                          _td(it.productName, bold: true),
                          _td('${it.quantity}', align: pw.TextAlign.center),
                          _td(DzdFormatter.formatCentimes(it.unitPriceCentimes)),
                          _td(DzdFormatter.formatCentimes(it.lineTotalCentimes), bold: true),
                        ],
                      );
                    }),
                  ],
                ),
                pw.SizedBox(height: 8),

                // Totals
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('المبلغ الإجمالي المستحق:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.Text(
                        DzdFormatter.formatCentimes(order.totalAmountCentimes),
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.blue900),
                      ),
                    ],
                  ),
                ),
                 pw.Spacer(),
                pw.Center(
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.code128(),
                    data: order.id,
                    height: 22,
                    width: 120,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Center(
                  child: pw.Text(
                    'تطبيق VIP للطلبات بالجملة - شكراً لثقتكم بنا',
                    style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      name: 'Facture_Commande_$orderNum.pdf',
      onLayout: (format) async => doc.save(),
    );
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
