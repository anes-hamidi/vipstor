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
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text('VIP WHOLESALE & DISTRIBUTION', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
              pw.Text('RECEIPT / TICKET DE CAISSE', style: const pw.TextStyle(fontSize: 9)),
              pw.Divider(thickness: 0.5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TICKET: #${orderId.length > 8 ? orderId.substring(0, 8) : orderId}', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(DateTime.now().toString().substring(0, 16), style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('CASHIER: $cashierName', style: const pw.TextStyle(fontSize: 8)),
                  if (customer != null) pw.Text('CLIENT: ${customer.name}', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Divider(thickness: 0.5),
              pw.Table(
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(2),
                },
                children: [
                  pw.TableRow(
                    children: [
                      pw.Text('ITEM', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                      pw.Text('QTY', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                      pw.Text('TOTAL', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                    ],
                  ),
                  ...items.map((i) => pw.TableRow(
                        children: [
                          pw.Text(i.nameFr.isNotEmpty ? i.nameFr : i.nameAr, style: const pw.TextStyle(fontSize: 8)),
                          pw.Text('${i.quantity} ${i.unit.name}', style: const pw.TextStyle(fontSize: 8)),
                          pw.Text(DzdFormatter.formatCentimes(i.lineTotalCentimes), style: const pw.TextStyle(fontSize: 8)),
                        ],
                      )),
                ],
              ),
              pw.Divider(thickness: 0.5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL DUE:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.Text(DzdFormatter.formatCentimes(totalCentimes), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('CASH PAID:', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(DzdFormatter.formatCentimes(paidCashCentimes), style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              if (onAccountCentimes > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('ON ACCOUNT (DEBT):', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                    pw.Text(DzdFormatter.formatCentimes(onAccountCentimes), style: const pw.TextStyle(fontSize: 8)),
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
              pw.Text('THANK YOU FOR YOUR VISIT', style: const pw.TextStyle(fontSize: 7)),
            ],
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
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text('DAILY FINANCIAL Z-REPORT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.Text('Z-COUNTER: #${z.zNumber.toString().padLeft(6, '0')}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
              pw.Divider(thickness: 0.5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('CASHIER: ${z.cashierName}', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(z.closedAt.toString().substring(0, 16), style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Divider(thickness: 0.5),
              _zRow('OPENING FLOAT:', z.openingFloatCentimes),
              _zRow('CASH SALES:', z.cashSalesCentimes),
              _zRow('CREDIT SALES:', z.creditSalesCentimes),
              _zRow('TOTAL SALES:', z.totalSalesCentimes, isBold: true),
              if (z.collectedDebtCashCentimes > 0)
                _zRow('DEBT COLLECTED (CASH):', z.collectedDebtCashCentimes),
              _zRow('REFUNDS / RETURNS:', -z.returnsCentimes),
              pw.Divider(thickness: 0.5),
              _zRow('EXPECTED CASH IN DRAWER:', z.expectedCashCentimes, isBold: true),
              _zRow('COUNTED CASH:', z.countedCashCentimes, isBold: true),
              pw.Divider(thickness: 0.5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('VARIANCE (OVER/SHORT):', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                  pw.Text(
                    '${z.varianceCentimes >= 0 ? '+' : ''}${DzdFormatter.formatCentimes(z.varianceCentimes)}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Text('CASHIER SIGNATURE', style: const pw.TextStyle(fontSize: 7)),
              pw.SizedBox(height: 20),
              pw.Text('-----------------------------------', style: const pw.TextStyle(fontSize: 7)),
            ],
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
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text('VIP WHOLESALE & DISTRIBUTION', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
              pw.Text('PAYMENT RECEIPT / BON DE PAIEMENT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
              pw.Text('RECU DE REGLEMENT DE CREANCE', style: const pw.TextStyle(fontSize: 8)),
              pw.Divider(thickness: 0.5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('RECEIPT: #${result.paymentId.length > 8 ? result.paymentId.substring(0, 8) : result.paymentId}', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(result.timestamp.toString().substring(0, 16), style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('CASHIER: $cashierName', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('METHOD: ${result.paymentMethod.toUpperCase()}', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Divider(thickness: 0.5),
              pw.Container(
                alignment: pw.Alignment.centerLeft,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('CLIENT / CUSTOMER: ${customer.name}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    if (customer.phone.isNotEmpty) pw.Text('PHONE: ${customer.phone}', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 0.5),
              _zRow('PREVIOUS DEBT BALANCE:', result.previousBalanceCentimes),
              _zRow('AMOUNT RECEIVED / PAYE:', result.paidAmountCentimes, isBold: true),
              pw.Divider(thickness: 0.5),
              _zRow('REMAINING DEBT / RESTE:', result.remainingBalanceCentimes, isBold: true),
              if (result.notes != null && result.notes!.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Text('NOTES: ${result.notes}', style: const pw.TextStyle(fontSize: 8)),
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
                  pw.Text('SIGNATURE CLIENT', style: const pw.TextStyle(fontSize: 7)),
                  pw.Text('CACHEUR / CAISSE', style: const pw.TextStyle(fontSize: 7)),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Text('-----------------------------------', style: const pw.TextStyle(fontSize: 7)),
            ],
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
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text('VIP WHOLESALE & DISTRIBUTION', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
              pw.Text('EXTRAIT DE COMPTE CLIENT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
              pw.Text('كشف حساب الزبون', style: const pw.TextStyle(fontSize: 8)),
              pw.Divider(thickness: 0.5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('CLIENT: ${customer.name}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                  pw.Text(DateTime.now().toString().substring(0, 10), style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              if (customer.phone.isNotEmpty)
                pw.Container(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text('TEL: ${customer.phone}', style: const pw.TextStyle(fontSize: 8)),
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
                      pw.Text('DATE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                      pw.Text('OPERATION', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                      pw.Text('MONTANT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                    ],
                  ),
                  ...entries.take(15).map((e) => pw.TableRow(
                        children: [
                          pw.Text(e.createdAt.toString().substring(5, 10), style: const pw.TextStyle(fontSize: 7)),
                          pw.Text(e.isDebtPayment ? 'Paiement' : 'Credit Vente', style: const pw.TextStyle(fontSize: 7)),
                          pw.Text(
                            '${e.isDebtPayment ? '-' : '+'}${DzdFormatter.formatCentimes(e.amountChangeCentimes.abs())}',
                            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
                          ),
                        ],
                      )),
                ],
              ),
              pw.Divider(thickness: 0.5),
              _zRow('SOLDE ACTUEL DU (DEBT):', customer.currentDebtCentimes, isBold: true),
              _zRow('PLAFOND DE CREDIT:', customer.creditLimitCentimes),
              pw.SizedBox(height: 10),
              pw.Text('EDITE PAR: $cashierName', style: const pw.TextStyle(fontSize: 7)),
            ],
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
