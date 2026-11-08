import 'dart:convert';

import 'package:pdf/pdf.dart';

class ReceiptDesign {
  final String paperSize;
  final String layout;
  final String? logoBase64;
  final String footer;

  const ReceiptDesign({
    this.paperSize = 'a4',
    this.layout = 'classic',
    this.logoBase64,
    this.footer = 'Thank you!',
  });

  bool get compact => layout == 'compact';
  bool get hasLogo => logoBase64 != null && logoBase64!.isNotEmpty;

  PdfPageFormat get pageFormat => switch (paperSize) {
    '58mm' => PdfPageFormat(58 * PdfPageFormat.mm, 200 * PdfPageFormat.mm),
    '80mm' => PdfPageFormat(80 * PdfPageFormat.mm, 250 * PdfPageFormat.mm),
    _ => PdfPageFormat.a4,
  };

  ReceiptDesign copyWith({
    String? paperSize,
    String? layout,
    String? logoBase64,
    bool clearLogo = false,
    String? footer,
  }) => ReceiptDesign(
    paperSize: paperSize ?? this.paperSize,
    layout: layout ?? this.layout,
    logoBase64: clearLogo ? null : logoBase64 ?? this.logoBase64,
    footer: footer ?? this.footer,
  );

  Map<String, Object?> toJson() => {
    'paperSize': paperSize,
    'layout': layout,
    'logoBase64': logoBase64,
    'footer': footer,
  };

  factory ReceiptDesign.fromJson(Map<String, dynamic> json) {
    final paperSize = json['paperSize'];
    final layout = json['layout'];
    final logoBase64 = json['logoBase64'];
    final footer = json['footer'];
    return ReceiptDesign(
      paperSize:
          paperSize is String && {'58mm', '80mm', 'a4'}.contains(paperSize)
          ? paperSize
          : 'a4',
      layout: layout == 'compact' ? 'compact' : 'classic',
      logoBase64: logoBase64 is String && logoBase64.isNotEmpty
          ? logoBase64
          : null,
      footer: footer is String ? footer : 'Thank you!',
    );
  }

  String toStorageJson() => jsonEncode(toJson());

  factory ReceiptDesign.fromStorageJson(String json) =>
      ReceiptDesign.fromJson(jsonDecode(json) as Map<String, dynamic>);
}
