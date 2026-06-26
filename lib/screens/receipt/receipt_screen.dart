import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../models/sale.dart';
import '../../providers/cart_provider.dart';
import '../../core/constants.dart';
import '../home_screen.dart';

class ReceiptScreen extends ConsumerWidget {
  final Sale sale;

  const ReceiptScreen({super.key, required this.sale});

  Future<pw.Document> _buildPdf() async {
    final doc = pw.Document();
    final dateFormat = DateFormat('dd MMM yyyy  HH:mm');
    final cf = NumberFormat.currency(locale: 'en_US', symbol: '\$');

    doc.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Center(
                child: pw.Text('RECEIPT',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 18)),
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
                    child: pw.Text('Item',
                        style:
                            pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Text('Qty',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(width: 24),
                  pw.Text('Total',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Divider(),
              ...sale.items.map((item) {
                final showVariant = item.variant.name.isNotEmpty &&
                    item.variant.name != 'Default';
                final label = showVariant
                    ? '${item.product.name} (${item.variant.name})'
                    : item.product.name;
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    children: [
                      pw.Expanded(child: pw.Text(label)),
                      pw.Text('${item.quantity}'),
                      pw.SizedBox(width: 24),
                      pw.Text(cf.format(item.total)),
                    ],
                  ),
                );
              }),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL',
                      style:
                          pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text(cf.format(sale.totalAmount),
                      style:
                          pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ],
              ),
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
    ref.read(cartProvider.notifier).clearCart();
    ref.read(selectedTabProvider.notifier).state = 2;
    context.go('/');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _goToPos(context, ref);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Receipt')),
        body: Column(
          children: [
            Expanded(
              child: PdfPreview(
                build: (PdfPageFormat format) async {
                  final doc = await _buildPdf();
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
                      child: const Text('New sale'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 48)),
                      icon: const Icon(Icons.share),
                      label: const Text('Share receipt'),
                      onPressed: () async {
                        final doc = await _buildPdf();
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
