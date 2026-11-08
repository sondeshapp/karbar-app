import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../models/receipt_design.dart';
import '../../models/sale.dart';
import '../../providers/receipt_design_provider.dart';
import '../../providers/sales_provider.dart';
import '../../providers/settings_provider.dart';
import '../receipt/receipt_screen.dart';

class ReceiptDesignScreen extends ConsumerStatefulWidget {
  const ReceiptDesignScreen({super.key});

  @override
  ConsumerState<ReceiptDesignScreen> createState() =>
      _ReceiptDesignScreenState();
}

class _ReceiptDesignScreenState extends ConsumerState<ReceiptDesignScreen> {
  final _footerController = TextEditingController();
  final _imagePicker = ImagePicker();
  Timer? _footerDebounce;
  ReceiptDesign _design = const ReceiptDesign();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _footerDebounce?.cancel();
    _footerController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final design = await ref.read(receiptDesignProvider.future);
      _footerController.text = design.footer;
      await ref.read(salesProvider.notifier).loadSales();
      if (!mounted) return;
      setState(() {
        _design = design;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _update(ReceiptDesign design) => setState(() => _design = design);

  Future<void> _pickLogo() async {
    final strings = ref.read(stringsProvider);
    try {
      final selected = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );
      if (selected == null) return;
      final source = img.decodeImage(await selected.readAsBytes());
      if (source == null) throw const FormatException('Invalid image');
      final resized = source.width > 512 || source.height > 512
          ? img.copyResize(
              source,
              width: source.width >= source.height ? 512 : null,
              height: source.height > source.width ? 512 : null,
            )
          : source;
      final bytes = img.encodePng(resized);
      if (!mounted) return;
      _update(_design.copyWith(logoBase64: base64Encode(bytes)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.receiptLogoInvalid)));
      }
    }
  }

  Future<void> _save() async {
    final strings = ref.read(stringsProvider);
    _footerDebounce?.cancel();
    final design = _design.copyWith(footer: _footerController.text.trim());
    setState(() {
      _design = design;
      _saving = true;
    });
    try {
      await ref.read(receiptDesignStoreProvider).save(design);
      ref.invalidate(receiptDesignProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.receiptSaved)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.receiptSaveFailed)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final sales = ref.watch(salesProvider);
    final sale = _latestSale(sales);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(strings.customizeReceipt)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _sectionCard(
                  context,
                  title: strings.receiptPaperSize,
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: '58mm',
                        label: Text(strings.receiptPaper58),
                      ),
                      ButtonSegment(
                        value: '80mm',
                        label: Text(strings.receiptPaper80),
                      ),
                      ButtonSegment(
                        value: 'a4',
                        label: Text(strings.receiptPaperA4),
                      ),
                    ],
                    selected: {_design.paperSize},
                    onSelectionChanged: (value) =>
                        _update(_design.copyWith(paperSize: value.first)),
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  context,
                  title: strings.receiptLayout,
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: 'classic',
                        label: Text(strings.receiptClassic),
                      ),
                      ButtonSegment(
                        value: 'compact',
                        label: Text(strings.receiptCompact),
                      ),
                    ],
                    selected: {_design.layout},
                    onSelectionChanged: (value) =>
                        _update(_design.copyWith(layout: value.first)),
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  context,
                  title: strings.receiptLogo,
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _design.hasLogo
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  base64Decode(_design.logoBase64!),
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.contain,
                                ),
                              )
                            : Icon(
                                Icons.storefront_outlined,
                                color: colors.onSurfaceVariant,
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickLogo,
                          icon: const Icon(Icons.image_outlined),
                          label: Text(strings.chooseReceiptLogo),
                        ),
                      ),
                      if (_design.hasLogo) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: strings.removeReceiptLogo,
                          onPressed: () =>
                              _update(_design.copyWith(clearLogo: true)),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  context,
                  title: strings.receiptFooter,
                  child: TextField(
                    controller: _footerController,
                    maxLength: 100,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: strings.receiptFooter,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      _footerDebounce?.cancel();
                      _footerDebounce = Timer(
                        const Duration(milliseconds: 350),
                        () {
                          if (mounted) {
                            _update(_design.copyWith(footer: value));
                          }
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  context,
                  title: strings.receiptPreview,
                  child: sale == null
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Text(
                            strings.receiptPreviewAfterSale,
                            textAlign: TextAlign.center,
                          ),
                        )
                      : SizedBox(
                          height: 390,
                          child: PdfPreview(
                            key: ValueKey(
                              '${_design.paperSize}_${_design.layout}_${_design.footer}_${_design.logoBase64?.length}',
                            ),
                            build: (PdfPageFormat format) async {
                              final document = await buildReceiptPdf(
                                sale: sale,
                                currencySymbol: settings.currencySymbol,
                                currencyLocale: settings.currencyLocale,
                                settings: settings,
                                design: _design,
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
                ),
                const SizedBox(height: 80),
              ],
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: _loading || _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: Text(strings.receiptSave),
        ),
      ),
    );
  }

  Sale? _latestSale(List<Sale> sales) {
    if (sales.isEmpty) return null;
    return sales.reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b);
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required Widget child,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}
