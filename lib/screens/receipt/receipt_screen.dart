import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../models/sale.dart';
import '../../providers/cart_provider.dart';
import '../../providers/settings_provider.dart';
import '../../core/constants.dart';
import '../../core/quantity_format.dart';

class ReceiptScreen extends ConsumerWidget {
  final Sale sale;
  final bool returnToHistory;

  const ReceiptScreen({
    super.key,
    required this.sale,
    this.returnToHistory = false,
  });

  Future<pw.Document> _buildPdf(
    String symbol,
    String locale,
    SettingsState settings,
  ) async {
    final doc = pw.Document();
    final dateFormat = DateFormat('dd MMM yyyy  HH:mm');
    final cf = NumberFormat.currency(locale: locale, symbol: symbol);

    doc.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              if (settings.shopName.isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    settings.shopName,
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              if (settings.shopAddress.isNotEmpty)
                pw.Center(child: pw.Text(settings.shopAddress)),
              if (settings.shopPhone.isNotEmpty)
                pw.Center(child: pw.Text(settings.shopPhone)),
              if (settings.shopName.isNotEmpty ||
                  settings.shopAddress.isNotEmpty ||
                  settings.shopPhone.isNotEmpty)
                pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  'RECEIPT',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text('Date: ${dateFormat.format(sale.createdAt)}'),
              ),
              pw.SizedBox(height: 12),
              pw.Divider(),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      'Item',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.Text(
                    'Qty',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(width: 24),
                  pw.Text(
                    'Total',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.Divider(),
              ...sale.items.map((item) {
                final showVariant =
                    item.variant.name.isNotEmpty &&
                    item.variant.name != 'Default';
                final label = showVariant
                    ? '${item.product.name} (${item.variant.name})'
                    : item.product.name;
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    children: [
                      pw.Expanded(child: pw.Text(label)),
                      pw.Text(
                        formatQuantity(
                          item.quantity,
                          item.product.quantityPrecision,
                        ),
                      ),
                      pw.SizedBox(width: 24),
                      pw.Text(cf.format(item.total)),
                    ],
                  ),
                );
              }),
              pw.Divider(),
              if (settings.showTax && sale.taxAmount > 0) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Subtotal'),
                    pw.Text(cf.format(sale.totalAmount - sale.taxAmount)),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Tax'),
                    pw.Text(cf.format(sale.taxAmount)),
                  ],
                ),
                pw.Divider(),
              ],
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'TOTAL',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    cf.format(sale.totalAmount),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              if (sale.payments.isNotEmpty) ...[
                pw.SizedBox(height: 12),
                pw.Divider(),
                pw.Text(
                  'Payment details',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                ...sale.payments.map(
                  (payment) => pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 4),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(payment.method.toUpperCase()),
                        pw.Text(cf.format(payment.amount)),
                      ],
                    ),
                  ),
                ),
              ],
              pw.SizedBox(height: 16),
              pw.Center(child: pw.Text('Thank you!')),
            ],
          );
        },
      ),
    );
    return doc;
  }

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
    final sym = settings.currencySymbol;
    final loc = settings.currencyLocale;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _goToPos(context, ref);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(returnToHistory ? 'Receipt copy' : 'Receipt'),
        ),
        body: Column(
          children: [
            Expanded(
              child: PdfPreview(
                build: (PdfPageFormat format) async {
                  final doc = await _buildPdf(sym, loc, settings);
                  return doc.save();
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
                        final doc = await _buildPdf(sym, loc, settings);
                        final bytes = await doc.save();
                        await Printing.sharePdf(
                          bytes: bytes,
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
    );
  }
}
