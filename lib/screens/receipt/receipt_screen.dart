import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/constants.dart';
import '../../core/quantity_format.dart';
import '../../models/receipt_design.dart';
import '../../models/sale.dart';
import '../../providers/cart_provider.dart';
import '../../providers/receipt_design_provider.dart';
import '../../providers/settings_provider.dart';

Future<pw.Document> buildReceiptPdf({
  required Sale sale,
  required String currencySymbol,
  required String currencyLocale,
  required SettingsState settings,
  required ReceiptDesign design,
}) async {
  final document = pw.Document();
  final dateFormat = DateFormat('dd MMM yyyy  HH:mm');
  final currency = NumberFormat.currency(
    locale: currencyLocale,
    symbol: currencySymbol,
  );
  final small = design.compact ? 8.5 : 10.5;
  final normal = design.compact ? 9.5 : 11.5;
  final sectionGap = design.compact ? 5.0 : 10.0;
  final Uint8List? logoBytes = design.hasLogo
      ? base64Decode(design.logoBase64!)
      : null;
  final pw.MemoryImage? logo = logoBytes == null
      ? null
      : pw.MemoryImage(logoBytes);
  final regularFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSansBengali-Regular.ttf'),
  );
  final boldFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSansBengali-Bold.ttf'),
  );
  final pdfTheme = pw.ThemeData.withFont(
    base: regularFont,
    bold: boldFont,
    italic: regularFont,
    boldItalic: boldFont,
  );

  document.addPage(
    pw.MultiPage(
      theme: pdfTheme,
      pageFormat: design.pageFormat,
      margin: pw.EdgeInsets.all(design.compact ? 14 : 24),
      build: (context) => [
        if (logo != null) ...[
          pw.Center(
            child: pw.Image(
              logo,
              width: design.compact ? 38 : 52,
              height: design.compact ? 38 : 52,
            ),
          ),
          pw.SizedBox(height: sectionGap),
        ],
        if (settings.shopName.isNotEmpty)
          pw.Center(
            child: pw.Text(
              settings.shopName,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: design.compact ? 12 : 16,
              ),
            ),
          ),
        if (settings.shopAddress.isNotEmpty)
          pw.Center(
            child: pw.Text(
              settings.shopAddress,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: small),
            ),
          ),
        if (settings.shopPhone.isNotEmpty)
          pw.Center(
            child: pw.Text(
              settings.shopPhone,
              style: pw.TextStyle(fontSize: small),
            ),
          ),
        if (settings.shopName.isNotEmpty ||
            settings.shopAddress.isNotEmpty ||
            settings.shopPhone.isNotEmpty)
          pw.SizedBox(height: sectionGap),
        pw.Center(
          child: pw.Text(
            'RECEIPT',
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: design.compact ? 13 : 18,
            ),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            'Date: ${dateFormat.format(sale.createdAt)}',
            style: pw.TextStyle(fontSize: small),
          ),
        ),
        pw.SizedBox(height: sectionGap),
        pw.Divider(),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                'Item',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: normal,
                ),
              ),
            ),
            pw.SizedBox(width: design.compact ? 10 : 18),
            pw.Text(
              'Qty',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: normal,
              ),
            ),
            pw.SizedBox(width: design.compact ? 10 : 24),
            pw.Text(
              'Total',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: normal,
              ),
            ),
          ],
        ),
        pw.Divider(),
        ...sale.items.map((item) {
          final showVariant =
              item.variant.name.isNotEmpty && item.variant.name != 'Default';
          final label = showVariant
              ? '${item.product.name} (${item.variant.name})'
              : item.product.name;
          return pw.Padding(
            padding: pw.EdgeInsets.symmetric(vertical: design.compact ? 1 : 3),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Text(label, style: pw.TextStyle(fontSize: normal)),
                ),
                pw.SizedBox(width: design.compact ? 10 : 18),
                pw.Text(
                  formatQuantity(item.quantity, item.product.quantityPrecision),
                  style: pw.TextStyle(fontSize: normal),
                ),
                pw.SizedBox(width: design.compact ? 10 : 24),
                pw.Text(
                  currency.format(item.total),
                  style: pw.TextStyle(fontSize: normal),
                ),
              ],
            ),
          );
        }),
        pw.Divider(),
        if (settings.showTax && sale.taxAmount > 0) ...[
          _receiptAmountRow(
            'Subtotal',
            currency.format(sale.totalAmount - sale.taxAmount),
            small,
          ),
          pw.SizedBox(height: 3),
          _receiptAmountRow('Tax', currency.format(sale.taxAmount), small),
          pw.Divider(),
        ],
        _receiptAmountRow(
          'TOTAL',
          currency.format(sale.totalAmount),
          design.compact ? 11 : 14,
          bold: true,
        ),
        if (sale.payments.isNotEmpty) ...[
          pw.SizedBox(height: sectionGap),
          pw.Divider(),
          pw.Text(
            'Payment details',
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: normal,
            ),
          ),
          ...sale.payments.map(
            (payment) => pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3),
              child: _receiptAmountRow(
                payment.method.toUpperCase(),
                currency.format(payment.amount),
                small,
              ),
            ),
          ),
        ],
        if (design.footer.trim().isNotEmpty) ...[
          pw.SizedBox(height: design.compact ? 10 : 18),
          pw.Center(
            child: pw.Text(
              design.footer.trim(),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: normal),
            ),
          ),
        ],
      ],
    ),
  );
  return document;
}

pw.Widget _receiptAmountRow(
  String label,
  String amount,
  double fontSize, {
  bool bold = false,
}) => pw.Row(
  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
  children: [
    pw.Text(
      label,
      style: pw.TextStyle(
        fontSize: fontSize,
        fontWeight: bold ? pw.FontWeight.bold : null,
      ),
    ),
    pw.Text(
      amount,
      style: pw.TextStyle(
        fontSize: fontSize,
        fontWeight: bold ? pw.FontWeight.bold : null,
      ),
    ),
  ],
);

class ReceiptScreen extends ConsumerWidget {
  final Sale sale;
  final bool returnToHistory;

  const ReceiptScreen({
    super.key,
    required this.sale,
    this.returnToHistory = false,
  });

  void _goToPos(BuildContext context, WidgetRef ref) {
    if (returnToHistory) {
      context.go('/history');
      return;
    }
    ref.read(cartProvider.notifier).clearCart();
    context.go('/');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final design = ref.watch(receiptDesignProvider);
    final symbol = settings.currencySymbol;
    final locale = settings.currencyLocale;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _goToPos(context, ref);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(returnToHistory ? 'Receipt copy' : 'Receipt'),
        ),
        body: design.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              const Center(child: Text('Could not load receipt settings.')),
          data: (receiptDesign) => Column(
            children: [
              Expanded(
                child: PdfPreview(
                  build: (format) async {
                    final document = await buildReceiptPdf(
                      sale: sale,
                      currencySymbol: symbol,
                      currencyLocale: locale,
                      settings: settings,
                      design: receiptDesign,
                    );
                    return document.save();
                  },
                  allowPrinting: false,
                  allowSharing: false,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(kPadding),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _goToPos(context, ref),
                        child: Text(
                          returnToHistory ? 'Back to history' : 'New sale',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        icon: const Icon(Icons.share),
                        label: const Text('Share receipt'),
                        onPressed: () async {
                          final design = await ref.read(
                            receiptDesignProvider.future,
                          );
                          final document = await buildReceiptPdf(
                            sale: sale,
                            currencySymbol: symbol,
                            currencyLocale: locale,
                            settings: settings,
                            design: design,
                          );
                          await Printing.sharePdf(
                            bytes: await document.save(),
                            filename: 'receipt.pdf',
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
