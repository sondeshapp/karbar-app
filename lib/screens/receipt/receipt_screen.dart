import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/app_strings.dart';
import '../../core/constants.dart';
import '../../core/quantity_format.dart';
import '../../db/database_helper.dart';
import '../../models/receipt_design.dart';
import '../../models/sale.dart';
import '../../providers/cart_provider.dart';
import '../../providers/receipt_design_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/staff_provider.dart';

class _ReceiptFontBundle {
  final pw.Font latinRegular;
  final pw.Font latinBold;
  final pw.Font bengaliRegular;
  final pw.Font bengaliBold;

  const _ReceiptFontBundle({
    required this.latinRegular,
    required this.latinBold,
    required this.bengaliRegular,
    required this.bengaliBold,
  });
}

Future<_ReceiptFontBundle>? _cachedReceiptFonts;

Future<_ReceiptFontBundle> _loadReceiptFonts() {
  return _cachedReceiptFonts ??= () async {
    final regularData = await rootBundle.load(
      'assets/fonts/NotoSansBengali-Regular.ttf',
    );
    final boldData = await rootBundle.load(
      'assets/fonts/NotoSansBengali-Bold.ttf',
    );

    try {
      final fontLoader = FontLoader('NotoSansBengali')
        ..addFont(Future.value(regularData))
        ..addFont(Future.value(boldData));
      await fontLoader.load();
    } catch (_) {
      // Ignore if FontLoader is unavailable in headless environments.
    }

    return _ReceiptFontBundle(
      latinRegular: pw.Font.helvetica(),
      latinBold: pw.Font.helveticaBold(),
      bengaliRegular: pw.Font.ttf(regularData),
      bengaliBold: pw.Font.ttf(boldData),
    );
  }();
}

final RegExp _bengaliScriptRunRegex = RegExp(r'[\u0980-\u09FF]+');

/// Returns true when [text] contains Bengali letters, vowel signs (kar), or
/// conjuncts (hasanta) that require OpenType HarfBuzz shaping.
/// Standalone Bengali digits (০-৯, U+09E6..U+09EF) and the Taka sign (৳, U+09F3)
/// do not require complex shaping and can be rendered directly as PDF vectors.
bool _needsComplexBengaliShaping(String text) {
  for (final rune in text.runes) {
    if (rune >= 0x0980 && rune <= 0x09FF) {
      final isDigit = rune >= 0x09E6 && rune <= 0x09EF;
      final isTakaSign = rune == 0x09F3;
      if (!isDigit && !isTakaSign) {
        return true;
      }
    }
  }
  return false;
}

/// Builds a dual-font vector [pw.RichText] widget where Latin/ASCII runs use
/// Helvetica and Bengali runs (such as `৫.০০৳`) use NotoSansBengali, preserving
/// bold weight for both scripts.
pw.Widget _buildVectorReceiptText(
  String text, {
  required _ReceiptFontBundle fonts,
  required double fontSize,
  bool bold = false,
  pw.TextAlign textAlign = pw.TextAlign.left,
}) {
  final latinFont = bold ? fonts.latinBold : fonts.latinRegular;
  final bengaliFont = bold ? fonts.bengaliBold : fonts.bengaliRegular;
  final weight = bold ? pw.FontWeight.bold : pw.FontWeight.normal;

  final spans = <pw.InlineSpan>[];
  var lastIndex = 0;

  for (final match in _bengaliScriptRunRegex.allMatches(text)) {
    if (match.start > lastIndex) {
      spans.add(
        pw.TextSpan(
          text: text.substring(lastIndex, match.start),
          style: pw.TextStyle(
            font: latinFont,
            fontNormal: fonts.latinRegular,
            fontBold: fonts.latinBold,
            fontFallback: [bengaliFont],
            fontSize: fontSize,
            fontWeight: weight,
          ),
        ),
      );
    }
    spans.add(
      pw.TextSpan(
        text: match.group(0),
        style: pw.TextStyle(
          font: bengaliFont,
          fontNormal: fonts.bengaliRegular,
          fontBold: fonts.bengaliBold,
          fontFallback: [latinFont],
          fontSize: fontSize,
          fontWeight: weight,
        ),
      ),
    );
    lastIndex = match.end;
  }

  if (lastIndex < text.length || spans.isEmpty) {
    spans.add(
      pw.TextSpan(
        text: text.substring(lastIndex),
        style: pw.TextStyle(
          font: latinFont,
          fontNormal: fonts.latinRegular,
          fontBold: fonts.latinBold,
          fontFallback: [bengaliFont],
          fontSize: fontSize,
          fontWeight: weight,
        ),
      ),
    );
  }

  return pw.RichText(
    textAlign: textAlign,
    text: pw.TextSpan(children: spans),
  );
}

/// Renders text for the PDF receipt, using crisp vector spans for English/Latin
/// and Bengali currency/numbers, and Flutter's HarfBuzz [TextPainter] when
/// [text] contains Bengali words/conjuncts/vowel signs.
Future<pw.Widget> _buildReceiptText(
  String text, {
  required _ReceiptFontBundle fonts,
  required double fontSize,
  required double maxWidth,
  bool bold = false,
  pw.TextAlign textAlign = pw.TextAlign.left,
}) async {
  if (!_needsComplexBengaliShaping(text)) {
    return _buildVectorReceiptText(
      text,
      fonts: fonts,
      fontSize: fontSize,
      bold: bold,
      textAlign: textAlign,
    );
  }

  try {
    const scale = 3.5;
    final flutterAlign = switch (textAlign) {
      pw.TextAlign.center => TextAlign.center,
      pw.TextAlign.right => TextAlign.right,
      _ => TextAlign.left,
    };

    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'NotoSansBengali',
          fontFamilyFallback: const ['Roboto', 'sans-serif'],
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          color: Colors.black,
          height: 1.22,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: flutterAlign,
    )..layout(maxWidth: maxWidth);

    final logicalWidth = painter.width.ceilToDouble();
    final logicalHeight = painter.height.ceilToDouble();
    if (logicalWidth > 0 && logicalHeight > 0) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(scale, scale);
      painter.paint(canvas, Offset.zero);
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        (logicalWidth * scale).ceil(),
        (logicalHeight * scale).ceil(),
      );
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData != null) {
        final imageWidget = pw.Image(
          pw.MemoryImage(byteData.buffer.asUint8List()),
          width: logicalWidth,
          height: logicalHeight,
        );
        return switch (textAlign) {
          pw.TextAlign.center => pw.Center(child: imageWidget),
          pw.TextAlign.right => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: imageWidget,
          ),
          _ => pw.Align(alignment: pw.Alignment.centerLeft, child: imageWidget),
        };
      }
    }
  } catch (_) {
    // Fall back to dual-font vector text if rasterization is unavailable.
  }

  return _buildVectorReceiptText(
    text,
    fonts: fonts,
    fontSize: fontSize,
    bold: bold,
    textAlign: textAlign,
  );
}

Future<String> _resolveReceiptPersonName(Sale sale, String? generatedBy) async {
  final saleStaff = sale.staffName?.trim() ?? '';
  if (saleStaff.isNotEmpty) return saleStaff;

  final currentPerson = generatedBy?.trim() ?? '';
  if (currentPerson.isNotEmpty) return currentPerson;

  try {
    final users = await DatabaseHelper().getStaffUsers();
    if (sale.staffId != null) {
      for (final user in users) {
        if (user.id == sale.staffId && user.name.trim().isNotEmpty) {
          return user.name.trim();
        }
      }
    }
    for (final user in users) {
      if (user.active && user.name.trim().isNotEmpty) {
        return user.name.trim();
      }
    }
  } catch (_) {
    // Ignore DB lookup errors if database is not initialized in a test.
  }

  return '';
}

Future<pw.Document> buildReceiptPdf({
  required Sale sale,
  required String currencySymbol,
  required String currencyLocale,
  required SettingsState settings,
  required ReceiptDesign design,
  String? generatedBy,
}) async {
  final document = pw.Document();
  final isBn = settings.language == 'বাংলা';
  final strings = AppStrings(isBn: isBn);
  final dateFormat = DateFormat('dd MMM yyyy  HH:mm');
  final currency = NumberFormat.currency(
    locale: currencyLocale,
    symbol: currencySymbol,
  );
  final small = design.compact ? 8.5 : 10.5;
  final normal = design.compact ? 9.5 : 11.5;
  final sectionGap = design.compact ? 5.0 : 10.0;
  final margin = design.compact ? 14.0 : 24.0;
  final contentWidth = (design.pageFormat.width - (margin * 2)).clamp(
    80.0,
    double.infinity,
  );

  final Uint8List? logoBytes = design.hasLogo
      ? base64Decode(design.logoBase64!)
      : null;
  final pw.MemoryImage? logo = logoBytes == null
      ? null
      : pw.MemoryImage(logoBytes);

  final fonts = await _loadReceiptFonts();
  final pdfTheme = pw.ThemeData.withFont(
    base: fonts.latinRegular,
    bold: fonts.latinBold,
    italic: fonts.latinRegular,
    boldItalic: fonts.latinBold,
    fontFallback: [fonts.bengaliRegular, fonts.bengaliBold],
  );

  final shopNameWidget = settings.shopName.isNotEmpty
      ? await _buildReceiptText(
          settings.shopName,
          fonts: fonts,
          fontSize: design.compact ? 12 : 16,
          maxWidth: contentWidth,
          bold: true,
          textAlign: pw.TextAlign.center,
        )
      : null;

  final shopAddressWidget = settings.shopAddress.isNotEmpty
      ? await _buildReceiptText(
          settings.shopAddress,
          fonts: fonts,
          fontSize: small,
          maxWidth: contentWidth,
          textAlign: pw.TextAlign.center,
        )
      : null;

  final shopPhoneWidget = settings.shopPhone.isNotEmpty
      ? await _buildReceiptText(
          settings.shopPhone,
          fonts: fonts,
          fontSize: small,
          maxWidth: contentWidth,
          textAlign: pw.TextAlign.center,
        )
      : null;

  final receiptTitleWidget = await _buildReceiptText(
    isBn ? 'রসিদ' : 'RECEIPT',
    fonts: fonts,
    fontSize: design.compact ? 13 : 18,
    maxWidth: contentWidth,
    bold: true,
    textAlign: pw.TextAlign.center,
  );

  final dateLabel = isBn
      ? 'তারিখ: ${dateFormat.format(sale.createdAt)}'
      : 'Date: ${dateFormat.format(sale.createdAt)}';
  final dateWidget = await _buildReceiptText(
    dateLabel,
    fonts: fonts,
    fontSize: small,
    maxWidth: contentWidth,
    textAlign: pw.TextAlign.center,
  );

  final personName = await _resolveReceiptPersonName(sale, generatedBy);
  final generatedByWidget = personName.isNotEmpty
      ? await _buildReceiptText(
          isBn ? 'প্রস্তুতকারী: $personName' : 'Generated by: $personName',
          fonts: fonts,
          fontSize: small,
          maxWidth: contentWidth,
          textAlign: pw.TextAlign.center,
        )
      : null;

  final itemHeaderWidget = await _buildReceiptText(
    isBn ? 'পণ্য' : 'Item',
    fonts: fonts,
    fontSize: normal,
    maxWidth: contentWidth * 0.55,
    bold: true,
  );
  final qtyHeaderWidget = await _buildReceiptText(
    isBn ? 'পরিমাণ' : 'Qty',
    fonts: fonts,
    fontSize: normal,
    maxWidth: contentWidth * 0.25,
    bold: true,
    textAlign: pw.TextAlign.right,
  );
  final totalHeaderWidget = await _buildReceiptText(
    isBn ? 'মোট' : 'Total',
    fonts: fonts,
    fontSize: normal,
    maxWidth: contentWidth * 0.35,
    bold: true,
    textAlign: pw.TextAlign.right,
  );

  final itemRows = <pw.Widget>[];
  for (final item in sale.items) {
    final showVariant =
        item.variant.name.isNotEmpty && item.variant.name != 'Default';
    final label = showVariant
        ? '${item.product.name} (${item.variant.name})'
        : item.product.name;
    final labelWidget = await _buildReceiptText(
      label,
      fonts: fonts,
      fontSize: normal,
      maxWidth: contentWidth * 0.56,
    );
    final qtyWidget = await _buildReceiptText(
      formatQuantity(item.quantity, item.product.quantityPrecision),
      fonts: fonts,
      fontSize: normal,
      maxWidth: contentWidth * 0.2,
      textAlign: pw.TextAlign.right,
    );
    final lineTotalWidget = await _buildReceiptText(
      currency.format(item.total),
      fonts: fonts,
      fontSize: normal,
      maxWidth: contentWidth * 0.32,
      textAlign: pw.TextAlign.right,
    );

    itemRows.add(
      pw.Padding(
        padding: pw.EdgeInsets.symmetric(vertical: design.compact ? 1 : 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: labelWidget),
            pw.SizedBox(width: design.compact ? 10 : 18),
            qtyWidget,
            pw.SizedBox(width: design.compact ? 10 : 24),
            lineTotalWidget,
          ],
        ),
      ),
    );
  }

  final taxWidgets = <pw.Widget>[];
  if (settings.showTax && sale.taxAmount > 0) {
    taxWidgets.add(
      await _receiptAmountRow(
        isBn ? 'উপমোট' : 'Subtotal',
        currency.format(sale.totalAmount - sale.taxAmount),
        small,
        fonts: fonts,
        contentWidth: contentWidth,
      ),
    );
    taxWidgets.add(pw.SizedBox(height: 3));
    taxWidgets.add(
      await _receiptAmountRow(
        isBn ? 'কর' : 'Tax',
        currency.format(sale.taxAmount),
        small,
        fonts: fonts,
        contentWidth: contentWidth,
      ),
    );
    taxWidgets.add(pw.Divider());
  }

  final grandTotalRow = await _receiptAmountRow(
    isBn ? 'সর্বমোট' : 'TOTAL',
    currency.format(sale.totalAmount),
    design.compact ? 11 : 14,
    fonts: fonts,
    contentWidth: contentWidth,
    bold: true,
  );

  final paymentWidgets = <pw.Widget>[];
  if (sale.payments.isNotEmpty) {
    paymentWidgets.add(pw.SizedBox(height: sectionGap));
    paymentWidgets.add(pw.Divider());
    paymentWidgets.add(
      await _buildReceiptText(
        isBn ? 'পেমেন্টের বিবরণ' : 'Payment details',
        fonts: fonts,
        fontSize: normal,
        maxWidth: contentWidth,
        bold: true,
      ),
    );
    for (final payment in sale.payments) {
      final methodLabel = isBn
          ? strings.paymentMethodLabel(payment.method)
          : payment.method.toUpperCase();
      paymentWidgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 3),
          child: await _receiptAmountRow(
            methodLabel,
            currency.format(payment.amount),
            small,
            fonts: fonts,
            contentWidth: contentWidth,
          ),
        ),
      );
    }
  }

  final footerText = design.footer.trim();
  final footerWidget = footerText.isNotEmpty
      ? await _buildReceiptText(
          footerText,
          fonts: fonts,
          fontSize: normal,
          maxWidth: contentWidth,
          textAlign: pw.TextAlign.center,
        )
      : null;

  document.addPage(
    pw.MultiPage(
      theme: pdfTheme,
      pageFormat: design.pageFormat,
      margin: pw.EdgeInsets.all(margin),
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
        if (shopNameWidget != null) pw.Center(child: shopNameWidget),
        if (shopAddressWidget != null) pw.Center(child: shopAddressWidget),
        if (shopPhoneWidget != null) pw.Center(child: shopPhoneWidget),
        if (settings.shopName.isNotEmpty ||
            settings.shopAddress.isNotEmpty ||
            settings.shopPhone.isNotEmpty)
          pw.SizedBox(height: sectionGap),
        pw.Center(child: receiptTitleWidget),
        pw.SizedBox(height: 4),
        pw.Center(child: dateWidget),
        if (generatedByWidget != null) ...[
          pw.SizedBox(height: 2),
          pw.Center(child: generatedByWidget),
        ],
        pw.SizedBox(height: sectionGap),
        pw.Divider(),
        pw.Row(
          children: [
            pw.Expanded(child: itemHeaderWidget),
            pw.SizedBox(width: design.compact ? 10 : 18),
            qtyHeaderWidget,
            pw.SizedBox(width: design.compact ? 10 : 24),
            totalHeaderWidget,
          ],
        ),
        pw.Divider(),
        ...itemRows,
        pw.Divider(),
        ...taxWidgets,
        grandTotalRow,
        ...paymentWidgets,
        if (footerWidget != null) ...[
          pw.SizedBox(height: design.compact ? 10 : 18),
          pw.Center(child: footerWidget),
        ],
      ],
    ),
  );
  return document;
}

Future<pw.Widget> _receiptAmountRow(
  String label,
  String amount,
  double fontSize, {
  required _ReceiptFontBundle fonts,
  required double contentWidth,
  bool bold = false,
}) async {
  final labelWidget = await _buildReceiptText(
    label,
    fonts: fonts,
    fontSize: fontSize,
    maxWidth: contentWidth * 0.58,
    bold: bold,
  );
  final amountWidget = await _buildReceiptText(
    amount,
    fonts: fonts,
    fontSize: fontSize,
    maxWidth: contentWidth * 0.42,
    bold: bold,
    textAlign: pw.TextAlign.right,
  );
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [labelWidget, amountWidget],
  );
}

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
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/history');
      }
      return;
    }
    ref.read(cartProvider.notifier).clearCart();
    context.go('/');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final activeStaff = ref.watch(activeStaffProvider);
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
                      generatedBy: activeStaff?.name,
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
                            generatedBy: activeStaff?.name,
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
