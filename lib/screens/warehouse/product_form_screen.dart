import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/product.dart';
import '../../models/product_variant.dart';
import '../../providers/warehouse_provider.dart';
import '../../core/constants.dart';

const _defaultCategories = [
  'Beverages',
  'Food & Snacks',
  'Dairy',
  'Fresh Produce',
  'Household',
  'Personal Care',
  'Electronics',
  'Clothing',
  'Other',
];

const _units = [
  'pcs',
  'g',
  'kg',
  'ml',
  'l',
  'oz',
  'lb',
  'm',
  'cm',
  'box',
  'pack',
];

class _VariantRow {
  final TextEditingController nameCtrl;
  final TextEditingController barcodeCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController stockCtrl;
  int? id;
  String? syncId;

  _VariantRow({
    String name = '',
    String barcode = '',
    String price = '',
    String stock = '0',
    this.id,
    this.syncId,
  }) : nameCtrl = TextEditingController(text: name),
       barcodeCtrl = TextEditingController(text: barcode),
       priceCtrl = TextEditingController(text: price),
       stockCtrl = TextEditingController(text: stock);

  void dispose() {
    nameCtrl.dispose();
    barcodeCtrl.dispose();
    priceCtrl.dispose();
    stockCtrl.dispose();
  }
}

class ProductFormScreen extends ConsumerStatefulWidget {
  final Product? product;
  final String? initialBarcode;

  const ProductFormScreen({super.key, this.product, this.initialBarcode});

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _brandCtrl;
  late final TextEditingController _skuCtrl;
  late final TextEditingController _costPriceCtrl;
  late final TextEditingController _lowStockCtrl;

  String _category = '';
  String _unit = 'pcs';
  int _quantityPrecision = 0;
  String _imagePath = '';
  late List<_VariantRow> _variants;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _descCtrl = TextEditingController(text: p?.description ?? '');
    _brandCtrl = TextEditingController(text: p?.brand ?? '');
    _skuCtrl = TextEditingController(text: p?.sku ?? '');
    _costPriceCtrl = TextEditingController(
      text: p != null && p.costPrice > 0 ? p.costPrice.toString() : '',
    );
    _lowStockCtrl = TextEditingController(
      text: p?.lowStockAlert.toString() ?? '5',
    );
    _category = p?.category ?? '';
    _unit = p?.unit ?? 'pcs';
    _quantityPrecision = p?.quantityPrecision ?? 0;
    _imagePath = p?.imagePath ?? '';

    if (p != null && p.variants.isNotEmpty) {
      _variants = p.variants
          .map(
            (v) => _VariantRow(
              name: v.name,
              barcode: v.barcode,
              price: v.price.toString(),
              stock: v.stock.toString(),
              id: v.id,
              syncId: v.syncId,
            ),
          )
          .toList();
    } else {
      _variants = [_VariantRow()];
    }

    // Pre-fill barcode when arriving from a warehouse scan
    if (widget.initialBarcode != null && _variants.isNotEmpty) {
      _variants[0].barcodeCtrl.text = widget.initialBarcode!;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _brandCtrl.dispose();
    _skuCtrl.dispose();
    _costPriceCtrl.dispose();
    _lowStockCtrl.dispose();
    for (final v in _variants) {
      v.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (file == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final filename = 'product_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final saved = await File(file.path).copy('${dir.path}/$filename');
    setState(() => _imagePath = saved.path);
  }

  Future<void> _scanBarcodeForVariant(int index) async {
    final result = await context.push<String>('/warehouse/scanner');
    if (result != null) {
      setState(() => _variants[index].barcodeCtrl.text = result);
    }
  }

  void _addVariant() {
    setState(() => _variants.add(_VariantRow()));
  }

  void _removeVariant(int index) {
    setState(() {
      _variants[index].dispose();
      _variants.removeAt(index);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final variants = _variants.asMap().entries.map((e) {
      final row = e.value;
      return ProductVariant(
        id: row.id,
        syncId: row.syncId,
        name: _variants.length == 1 ? 'Default' : row.nameCtrl.text.trim(),
        barcode: row.barcodeCtrl.text.trim(),
        price: double.parse(row.priceCtrl.text.trim()),
        stock: double.parse(row.stockCtrl.text.trim()),
      );
    }).toList();

    final product = Product(
      id: widget.product?.id,
      syncId: widget.product?.syncId,
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      category: _category,
      brand: _brandCtrl.text.trim(),
      sku: _skuCtrl.text.trim(),
      unit: _unit,
      quantityPrecision: _quantityPrecision,
      imagePath: _imagePath,
      costPrice: double.tryParse(_costPriceCtrl.text.trim()) ?? 0,
      lowStockAlert: int.tryParse(_lowStockCtrl.text.trim()) ?? 5,
      variants: variants,
    );

    if (widget.product == null) {
      await ref.read(warehouseProvider.notifier).addProduct(product);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Product added')));
      }
    } else {
      await ref.read(warehouseProvider.notifier).updateProduct(product);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Product updated')));
      }
    }

    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final allProducts = ref.watch(warehouseProvider);

    // Merge categories already used in the warehouse with the built-in defaults.
    // Shopkeeper's own categories come first; defaults fill in what's missing.
    final usedCategories = allProducts
        .map((p) => p.category)
        .where((c) => c.isNotEmpty)
        .toSet();
    final suggestions = <String>{
      ...usedCategories,
      ..._defaultCategories,
    }.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.product == null ? 'Add product' : 'Edit product'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(kPadding),
          children: [
            _buildImagePicker(),
            const SizedBox(height: kPadding),
            _sectionLabel('Basic information'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Product name *'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _brandCtrl,
              decoration: const InputDecoration(labelText: 'Brand'),
            ),
            const SizedBox(height: 12),
            Autocomplete<String>(
              initialValue: TextEditingValue(text: _category),
              optionsBuilder: (textEditingValue) {
                final q = textEditingValue.text.toLowerCase();
                if (q.isEmpty) return suggestions;
                return suggestions.where((c) => c.toLowerCase().contains(q));
              },
              onSelected: (value) => setState(() => _category = value),
              fieldViewBuilder: (ctx, controller, focusNode, onSubmitted) {
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    hintText: 'Type or choose a category',
                    suffixIcon: Icon(Icons.arrow_drop_down, color: Colors.grey),
                  ),
                  onChanged: (v) => setState(() => _category = v.trim()),
                );
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _skuCtrl,
              decoration: const InputDecoration(
                labelText: 'SKU / Internal code',
              ),
            ),
            const SizedBox(height: kPadding),
            _sectionLabel('Pricing & stock defaults'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _units.contains(_unit) ? _unit : 'pcs',
                    decoration: const InputDecoration(labelText: 'Unit'),
                    items: _units
                        .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                        .toList(),
                    onChanged: (v) => setState(() => _unit = v ?? 'pcs'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _costPriceCtrl,
                    decoration: const InputDecoration(labelText: 'Cost price'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lowStockCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Low stock alert',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _quantityPrecision,
              decoration: const InputDecoration(
                labelText: 'Quantity decimals',
                helperText: 'Choose 3 for weight, volume, or length sales.',
              ),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Whole units')),
                DropdownMenuItem(
                  value: 3,
                  child: Text('Up to 3 decimal places'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _quantityPrecision = value ?? 0),
            ),
            const SizedBox(height: kPadding),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _sectionLabel('Sizes / Variants (${_variants.length})'),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add size'),
                  onPressed: _addVariant,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._variants.asMap().entries.map(
              (e) => _buildVariantRow(e.key, e.value),
            ),
            const SizedBox(height: kPadding * 2),
            ElevatedButton(onPressed: _save, child: const Text('Save product')),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePicker() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color: kSurface,
          border: Border.all(color: kBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: _imagePath.isNotEmpty && File(_imagePath).existsSync()
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(_imagePath), fit: BoxFit.cover),
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 40,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Tap to add product photo',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildVariantRow(int index, _VariantRow row) {
    final showName = _variants.length > 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(8),
        color: kSurface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                showName ? 'Variant ${index + 1}' : 'Pricing & stock',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              if (_variants.length > 1)
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: kError,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _removeVariant(index),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (showName) ...[
            TextFormField(
              controller: row.nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Size / Variant name',
              ),
              validator: (v) => showName && (v == null || v.trim().isEmpty)
                  ? 'Required'
                  : null,
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: row.barcodeCtrl,
                  decoration: const InputDecoration(labelText: 'Barcode'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: () => _scanBarcodeForVariant(index),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: row.priceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Selling price *',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Required';
                    }
                    final d = double.tryParse(v.trim());
                    if (d == null || d < 0) return 'Invalid';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: row.stockCtrl,
                  decoration: const InputDecoration(labelText: 'Stock *'),
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: _quantityPrecision > 0,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    final i = double.tryParse(v.trim());
                    if (i == null || !i.isFinite || i < 0) return 'Invalid';
                    if (_quantityPrecision == 0 && i % 1 != 0) {
                      return 'Use whole units or enable decimals above';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: kPrimary,
        letterSpacing: 0.3,
      ),
    );
  }
}
