import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import '../models/pos_models.dart';

import '../../manager/services/pdf_invoice_service.dart';

class PosThermalPrinterService {
  static const roll80mm = PdfPageFormat(
    80 * PdfPageFormat.mm,
    double.infinity,
    marginAll: 4 * PdfPageFormat.mm,
  );

  static Future<pw.ThemeData> _getThermalTheme() async {
    return PdfInvoiceService.getArabicTheme();
  }

  /// 1. Print Standard Sales Receipt (80mm)
  static Future<void> printSalesReceipt({
    required String orderId,
    required String cashierName,
    required CustomerProfileEntity? customer,
    required List<PosCartItem> items,
    required int totalCentimes,
    required int paidCashCentimes,
    required int onAccountCentimes,
  }) async {
    final theme = await _getThermalTheme();
    final doc = pw.Document(theme: theme);

    doc.addPage(
      pw.Page(
        pageFormat: roll80mm,
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  'مؤسسة VIP للتجارة والتوزيع',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
                  textAlign: pw.TextAlign.center,
                ),
                pw.Text(
                  'وصل بيع',
                  style: const pw.TextStyle(fontSize: 9),
                  textAlign: pw.TextAlign.center,
                ),
                pw.Divider(thickness: 0.5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('وصل: #${orderId.length > 8 ? orderId.substring(0, 8) : orderId}',
                        style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(DateTime.now().toString().substring(0, 16),
                        style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('الكاشير: $cashierName', style: const pw.TextStyle(fontSize: 8)),
                    if (customer != null)
                      pw.Text('الزبون: ${customer.name}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                  ],
                ),
                pw.Divider(thickness: 0.5),
                pw.Table(
                  columnWidths: {
                    0: const pw.FlexColumnWidth(3.0),
                    1: const pw.FlexColumnWidth(1.6),
                    2: const pw.FlexColumnWidth(1.8),
                  },
                  children: [
                    pw.TableRow(
                      children: [
                        pw.Text('السلعة',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                        pw.Text('الكمية',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                        pw.Text('السعر',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),    
                        pw.Text('الإجمالي',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                      ],
                    ),
                    ...items.map((i) => pw.TableRow(
                          children: [
                            pw.Text(
                              i.nameAr.isNotEmpty ? i.nameAr : i.nameFr,
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                            pw.Text('${i.quantity} ${i.unit.invoiceLabel}',
                                style: const pw.TextStyle(fontSize: 8)),
                            pw.Text(DzdFormatter.formatCentimes(i.baseUnitPriceCentimes),
                                style: const pw.TextStyle(fontSize: 8)),
                            pw.Text(DzdFormatter.formatCentimes(i.lineTotalCentimes),
                                style: const pw.TextStyle(fontSize: 8)),

                          ],
                        )),
                  ],
                ),
                pw.Divider(thickness: 0.5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('المجموع المستحق:',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text(DzdFormatter.formatCentimes(totalCentimes),
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('المدفوع نقدًا:', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(DzdFormatter.formatCentimes(paidCashCentimes),
                        style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                if (onAccountCentimes > 0)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('(دين):',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                      pw.Text(DzdFormatter.formatCentimes(onAccountCentimes),
                          style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                pw.SizedBox(height: 6),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.code128(),
                  data: orderId,
                  height: 24,
                  width: 130,
                ),
                pw.SizedBox(height: 4),
                pw.Text('شكراً لزيارتكم',
                    style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
  }

  /// 2. Print Z-Report (End-of-Day Shift Close)
  static Future<void> printZReport(ZReportSummary z) async {
    final theme = await _getThermalTheme();
    final doc = pw.Document(theme: theme);

    doc.addPage(
      pw.Page(
        pageFormat: roll80mm,
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('التقرير المالي اليومي (Z-REPORT)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                pw.Text('رقم التقرير: #${z.zNumber.toString().padLeft(6, '0')}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                pw.Divider(thickness: 0.5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('الكاشير: ${z.cashierName}', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(z.closedAt.toString().substring(0, 16), style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                pw.Divider(thickness: 0.5),
                _zRow('الرصيد الافتتاحي للصندوق:', z.openingFloatCentimes),
                _zRow('مبيعات نقدية (Espèces):', z.cashSalesCentimes),
                _zRow('مبيعات بالدين (Crédit):', z.creditSalesCentimes),
                _zRow('إجمالي المبيعات:', z.totalSalesCentimes, isBold: true),
                if (z.collectedDebtCashCentimes > 0)
                  _zRow('تحصيلات ديون نقدية:', z.collectedDebtCashCentimes),
                if (z.driverSettlementCashCentimes > 0)
                  _zRow('تسويات عهدة السائقين (+):', z.driverSettlementCashCentimes),
                _zRow('مرتجعات مبيعات:', -z.returnsCentimes),
                pw.Divider(thickness: 0.5),
                _zRow('السيولة النقدية المتوقعة:', z.expectedCashCentimes, isBold: true),
                _zRow('السيولة الفعلية المحسوبة:', z.countedCashCentimes, isBold: true),
                pw.Divider(thickness: 0.5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('الفارق (عجز / فائض):', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                    pw.Text(
                      '${z.varianceCentimes >= 0 ? '+' : ''}${DzdFormatter.formatCentimes(z.varianceCentimes)}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Text('توقيع الكاشير المسؤول', style: const pw.TextStyle(fontSize: 7)),
                pw.SizedBox(height: 20),
                pw.Text('-----------------------------------', style: const pw.TextStyle(fontSize: 7)),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
  }

  /// 3. Print Customer Debt Repayment Voucher (سند قبض دين 80mm)
  static Future<void> printCustomerDebtVoucher({
    required CustomerDebtPaymentResult result,
    required CustomerProfileEntity customer,
    required String cashierName,
  }) async {
    final theme = await _getThermalTheme();
    final doc = pw.Document(theme: theme);

    doc.addPage(
      pw.Page(
        pageFormat: roll80mm,
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('مؤسسة VIP للتجارة والتوزيع', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                pw.Text('سند قبض وتحصيل دين / BON DE PAIEMENT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                pw.Divider(thickness: 0.5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('وصل: #${result.paymentId.length > 8 ? result.paymentId.substring(0, 8) : result.paymentId}', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(result.timestamp.toString().substring(0, 16), style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('الكاشير: $cashierName', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('طريقة الدفع: ${result.paymentMethod.toUpperCase()}', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                pw.Divider(thickness: 0.5),
                pw.Container(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('الزبون: ${customer.name}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      if (customer.phone.isNotEmpty) pw.Text('الهاتف: ${customer.phone}', style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Divider(thickness: 0.5),
                _zRow('الرصيد السابق (دين):', result.previousBalanceCentimes),
                _zRow('المبلغ المدفوع (المحصل):', result.paidAmountCentimes, isBold: true),
                pw.Divider(thickness: 0.5),
                _zRow('الدين المتبقي الحالي:', result.remainingBalanceCentimes, isBold: true),
                if (result.notes != null && result.notes!.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text('ملاحظات: ${result.notes}', style: const pw.TextStyle(fontSize: 8)),
                ],
                pw.SizedBox(height: 8),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.code128(),
                  data: result.paymentId,
                  height: 22,
                  width: 120,
                ),
                pw.SizedBox(height: 12),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('توقيع الزبون', style: const pw.TextStyle(fontSize: 7)),
                    pw.Text('ختم وتوقيع الصندوق', style: const pw.TextStyle(fontSize: 7)),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.Text('-----------------------------------', style: const pw.TextStyle(fontSize: 7)),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
  }

  /// 4. Print Customer Detailed Statement (كشف حساب زبون 80mm)
  static Future<void> printCustomerAccountStatement({
    required CustomerProfileEntity customer,
    required List<CustomerLedgerEntryEntity> entries,
    required String cashierName,
  }) async {
    final theme = await _getThermalTheme();
    final doc = pw.Document(theme: theme);

    doc.addPage(
      pw.Page(
        pageFormat: roll80mm,
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('مؤسسة VIP للتجارة والتوزيع', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                pw.Text('كشف حساب الزبون / EXTRAIT DE COMPTE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                pw.Divider(thickness: 0.5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('الزبون: ${customer.name}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                    pw.Text(DateTime.now().toString().substring(0, 10), style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                if (customer.phone.isNotEmpty)
                  pw.Container(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text('الهاتف: ${customer.phone}', style: const pw.TextStyle(fontSize: 8)),
                  ),
                pw.Divider(thickness: 0.5),
                pw.Table(
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2),
                    1: const pw.FlexColumnWidth(2),
                    2: const pw.FlexColumnWidth(2),
                  },
                  children: [
                    pw.TableRow(
                      children: [
                        pw.Text('التاريخ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                        pw.Text('العملية', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                        pw.Text('المبلغ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                      ],
                    ),
                    ...entries.take(15).map((e) => pw.TableRow(
                          children: [
                            pw.Text(e.createdAt.toString().substring(5, 10), style: const pw.TextStyle(fontSize: 7)),
                            pw.Text(e.isDebtPayment ? 'تسديد دفعة' : 'شراء بالدين', style: const pw.TextStyle(fontSize: 7)),
                            pw.Text(
                              '${e.isDebtPayment ? '-' : '+'}${DzdFormatter.formatCentimes(e.amountChangeCentimes.abs())}',
                              style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
                            ),
                          ],
                        )),
                  ],
                ),
                pw.Divider(thickness: 0.5),
                _zRow('الدين المستحق الحالي:', customer.currentDebtCentimes, isBold: true),
                _zRow('سقف الائتمان المسموح:', customer.creditLimitCentimes),
                pw.SizedBox(height: 10),
                pw.Text('تحرير بواسطة: $cashierName', style: const pw.TextStyle(fontSize: 7)),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
  }

  /// 6. Print Supplier Cash Payment Voucher (80mm) - سند صرف ودفع نقدي للمورد
  static Future<void> printSupplierPaymentVoucher({
    required SupplierPaymentResult result,
    required SupplierProfileEntity supplier,
    required String payerName,
    required String payerRole,
  }) async {
    final theme = await _getThermalTheme();
    final doc = pw.Document(theme: theme);

    doc.addPage(
      pw.Page(
        pageFormat: roll80mm,
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  'مؤسسة VIP للتجارة والتوزيع',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 2),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(width: 1),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    'سند صرف ودفع نقدي للمورد (CASH)',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Divider(thickness: 0.5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('رقم السند: #${result.paymentId.length > 8 ? result.paymentId.substring(0, 8) : result.paymentId}',
                        style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(result.timestamp.toString().substring(0, 16),
                        style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('المسؤول الصارف: $payerName ($payerRole)', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('طريقة الدفع: نقدًا (CASH)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                  ],
                ),
                pw.Divider(thickness: 0.5),
                pw.Container(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('اسم المورد: ${supplier.name}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      if (supplier.phone.isNotEmpty)
                        pw.Text('الهاتف: ${supplier.phone}', style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ),
                pw.Divider(thickness: 0.5),
                _zRow('الرصيد السابق المستحق:', result.previousBalanceCentimes),
                pw.Container(
                  margin: const pw.EdgeInsets.symmetric(vertical: 4),
                  padding: const pw.EdgeInsets.all(6),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('المبلغ المدفوع نقدًا:',
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.Text(
                        DzdFormatter.formatCentimes(result.paidAmountCentimes),
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                _zRow('الرصيد المتبقي بذمة المؤسسة:', result.remainingBalanceCentimes, isBold: true),
                if (result.notes != null && result.notes!.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text('ملاحظات: ${result.notes}', style: const pw.TextStyle(fontSize: 7)),
                  ),
                ],
                pw.Divider(thickness: 0.5),
                pw.SizedBox(height: 12),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      children: [
                        pw.Text('توقيع المستلم (المورد):', style: const pw.TextStyle(fontSize: 7)),
                        pw.SizedBox(height: 20),
                        pw.Text('................................', style: const pw.TextStyle(fontSize: 7)),
                      ],
                    ),
                    pw.Column(
                      children: [
                        pw.Text('توقيع الصارف ($payerRole):', style: const pw.TextStyle(fontSize: 7)),
                        pw.SizedBox(height: 20),
                        pw.Text('................................', style: const pw.TextStyle(fontSize: 7)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Text('وثيقة رسمية صادرة من نظام VIP Smart POS',
                    style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700),
                    textAlign: pw.TextAlign.center),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
  }

  /// 6. Print Driver Wallet Settlement Voucher (80mm)
  static Future<void> printDriverSettlementVoucher({
    required SettlementEntity settlement,
    String? driverPhone,
    int? unsettledOrdersCount,
    String receiverRole = 'أمين الصندوق',
  }) async {
    final theme = await _getThermalTheme();
    final doc = pw.Document(theme: theme);

    final statusText = settlement.status == 'settled'
        ? 'مطابقة تامة'
        : (settlement.differenceCentimes < 0 ? 'عجز في العهدة' : 'فائض في العهدة');

    doc.addPage(
      pw.Page(
        pageFormat: roll80mm,
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  'مؤسسة VIP للتجارة والتوزيع',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
                  textAlign: pw.TextAlign.center,
                ),
                pw.Text(
                  'وصل تسوية عهدة سائق توصيل (End-of-Shift Cash Close)',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
                pw.Divider(thickness: 0.5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'رقم التسوية: #${settlement.id.length > 8 ? settlement.id.substring(0, 8) : settlement.id}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    pw.Text(
                      settlement.createdAt.toString().substring(0, 16),
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('المستلم ($receiverRole): ${settlement.cashierName}',
                        style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('الحالة: $statusText',
                        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.Divider(thickness: 0.5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('السائق: ${settlement.driverName}',
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    if (driverPhone != null && driverPhone.isNotEmpty)
                      pw.Text(driverPhone, style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                if (unsettledOrdersCount != null && unsettledOrdersCount > 0)
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text('عدد الطلبات المشمولة: $unsettledOrdersCount طلبات',
                        style: const pw.TextStyle(fontSize: 8)),
                  ),
                pw.SizedBox(height: 4),
                _zRow('الكاش المتوقع بالعهدة (Expected):', settlement.expectedAmountCentimes),
                pw.Container(
                  margin: const pw.EdgeInsets.symmetric(vertical: 4),
                  padding: const pw.EdgeInsets.all(5),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('المبلغ المسلم فعلياً (Counted):',
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.Text(
                        DzdFormatter.formatCentimes(settlement.countedAmountCentimes),
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                _zRow('الفارق (Difference):', settlement.differenceCentimes, isBold: true),
                if (settlement.notes != null && settlement.notes!.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text('ملاحظات: ${settlement.notes}', style: const pw.TextStyle(fontSize: 7)),
                  ),
                ],
                pw.Divider(thickness: 0.5),
                pw.SizedBox(height: 12),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      children: [
                        pw.Text('توقيع السائق:', style: const pw.TextStyle(fontSize: 7)),
                        pw.SizedBox(height: 20),
                        pw.Text('................................', style: const pw.TextStyle(fontSize: 7)),
                      ],
                    ),
                    pw.Column(
                      children: [
                        pw.Text('توقيع المستلم ($receiverRole):', style: const pw.TextStyle(fontSize: 7)),
                        pw.SizedBox(height: 20),
                        pw.Text('................................', style: const pw.TextStyle(fontSize: 7)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Text('وثيقة رسمية صادرة من نظام VIP Smart POS',
                    style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700),
                    textAlign: pw.TextAlign.center),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
  }

  static pw.Widget _zRow(String label, int centimes, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 8, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(
            DzdFormatter.formatCentimes(centimes),
            style: pw.TextStyle(fontSize: 8, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal),
          ),
        ],
      ),
    );
  }
}
