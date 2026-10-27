import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../db/database_helper.dart';
import '../../models/product.dart';
import '../../models/purchase.dart';
import '../../models/product_variant.dart';
import '../../models/supplier.dart';
import '../../providers/settings_provider.dart';
import '../../providers/warehouse_provider.dart';
import '../../core/quantity_format.dart';

class SupplierPurchaseScreen extends ConsumerStatefulWidget {
  const SupplierPurchaseScreen({super.key});

  @override
  ConsumerState<SupplierPurchaseScreen> createState() =>
      _SupplierPurchaseScreenState();
}

class _SupplierPurchaseScreenState
    extends ConsumerState<SupplierPurchaseScreen> {
  final _db = DatabaseHelper();
  List<Supplier> _suppliers = [];
  List<Purchase> _purchases = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([_db.getSuppliers(), _db.getPurchases()]);
    if (!mounted) return;
    setState(() {
      _suppliers = results[0] as List<Supplier>;
      _purchases = results[1] as List<Purchase>;
      _loading = false;
    });
  }

  Future<void> _addSupplier() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    final notes = TextEditingController();
    final supplier = await showDialog<Supplier>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add supplier'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name *'),
              ),
              TextField(
                controller: phone,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              TextField(
                controller: address,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              TextField(
                controller: notes,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty) return;
              Navigator.pop(
                dialogContext,
                Supplier(
                  name: name.text.trim(),
                  phone: phone.text.trim(),
                  address: address.text.trim(),
                  notes: notes.text.trim(),
                ),
              );
            },
            child: const Text('Save supplier'),
          ),
        ],
      ),
    );
    name.dispose();
    phone.dispose();
    address.dispose();
    notes.dispose();
    if (supplier == null) return;
    await _db.saveSupplier(supplier);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${supplier.name} added')));
    }
  }

  Future<void> _newPurchase() async {
    if (_suppliers.isEmpty) {
      await _addSupplier();
      if (!mounted || _suppliers.isEmpty) return;
    }
    final products = ref.read(warehouseProvider);
    if (products.isEmpty) return;
    final draft =
        await showDialog<
          ({Supplier supplier, List<PurchaseLine> lines, String note})
        >(
          context: context,
          builder: (dialogContext) =>
              _PurchaseDialog(suppliers: _suppliers, products: products),
        );
    if (draft == null) return;
    try {
      await _db.recordPurchase(
        supplier: draft.supplier,
        items: draft.lines,
        note: draft.note,
      );
      await ref.read(warehouseProvider.notifier).loadProducts();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase recorded and stock updated')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not record purchase: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final currency = NumberFormat.currency(
      locale: settings.currencyLocale,
      symbol: settings.currencySymbol,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suppliers & purchases'),
        actions: [
          IconButton(
            tooltip: 'Add supplier',
            onPressed: _addSupplier,
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _suppliers.isEmpty ? _addSupplier : _newPurchase,
        icon: const Icon(Icons.add_shopping_cart_rounded),
        label: Text(_suppliers.isEmpty ? 'Add supplier' : 'New purchase'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                children: [
                  Text(
                    'SUPPLIERS',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  if (_suppliers.isEmpty)
                    const Card(child: ListTile(title: Text('No suppliers yet')))
                  else
                    ..._suppliers.map(
                      (supplier) => Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.local_shipping_outlined),
                          ),
                          title: Text(supplier.name),
                          subtitle: Text(
                            [
                              if (supplier.phone.isNotEmpty) supplier.phone,
                              if (supplier.address.isNotEmpty) supplier.address,
                            ].join(' · '),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Text(
                    'PURCHASE HISTORY',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  if (_purchases.isEmpty)
                    const Card(
                      child: ListTile(title: Text('No purchases recorded')),
                    )
                  else
                    ..._purchases.map(
                      (purchase) => Card(
                        child: ExpansionTile(
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: Text(purchase.supplierName),
                          subtitle: Text(
                            DateFormat(
                              'dd MMM yyyy · HH:mm',
                            ).format(purchase.createdAt),
                          ),
                          trailing: Text(
                            currency.format(purchase.totalAmount),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          children: [
                            for (final line in purchase.items)
                              ListTile(
                                dense: true,
                                title: Text(
                                  '${line.productName}${line.variantName.isEmpty ? '' : ' · ${line.variantName}'}',
                                ),
                                subtitle: Text(
                                  '${formatQuantity(line.quantity, 3)} × ${currency.format(line.costPrice)}',
                                ),
                                trailing: Text(currency.format(line.total)),
                              ),
                            if (purchase.note.isNotEmpty)
                              ListTile(title: Text(purchase.note)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _PurchaseDialog extends StatefulWidget {
  final List<Supplier> suppliers;
  final List<Product> products;

  const _PurchaseDialog({required this.suppliers, required this.products});

  @override
  State<_PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<_PurchaseDialog> {
  late Supplier _supplier = widget.suppliers.first;
  final _note = TextEditingController();
  final _rows = <_PurchaseDraftRow>[_PurchaseDraftRow()];
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New purchase'),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _supplier.id,
              decoration: const InputDecoration(labelText: 'Supplier'),
              items: [
                for (final supplier in widget.suppliers)
                  DropdownMenuItem(
                    value: supplier.id,
                    child: Text(supplier.name),
                  ),
              ],
              onChanged: (id) => setState(
                () =>
                    _supplier = widget.suppliers.firstWhere((s) => s.id == id),
              ),
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < _rows.length; index++)
              _buildLine(index),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _rows.add(_PurchaseDraftRow())),
                icon: const Icon(Icons.add),
                label: const Text('Add another item'),
              ),
            ),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Record purchase')),
    ],
  );

  Widget _buildLine(int index) {
    final draft = _rows[index];
    final product = widget
        .products[draft.productIndex.clamp(0, widget.products.length - 1)];
    if (product.variants.isEmpty) return const SizedBox.shrink();
    draft.variantIndex = draft.variantIndex.clamp(
      0,
      product.variants.length - 1,
    );
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: draft.productIndex,
                    decoration: const InputDecoration(labelText: 'Product'),
                    items: [
                      for (var i = 0; i < widget.products.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            widget.products[i].name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      draft.productIndex = value ?? 0;
                      draft.variantIndex = 0;
                    }),
                  ),
                ),
                if (_rows.length > 1)
                  IconButton(
                    tooltip: 'Remove item',
                    onPressed: () => setState(() {
                      _rows.removeAt(index).dispose();
                    }),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            if (product.variants.length > 1)
              DropdownButtonFormField<int>(
                initialValue: draft.variantIndex,
                decoration: const InputDecoration(labelText: 'Variant'),
                items: [
                  for (var i = 0; i < product.variants.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(product.variants[i].name),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => draft.variantIndex = value ?? 0),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: draft.quantity,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: product.quantityPrecision > 0,
                    ),
                    decoration: const InputDecoration(labelText: 'Quantity'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: draft.cost,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Unit cost'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final lines = <PurchaseLine>[];
    for (final row in _rows) {
      final product = widget.products[row.productIndex];
      if (product.variants.isEmpty) {
        setState(() => _error = 'Every product must have a variant.');
        return;
      }
      final ProductVariant variant = product.variants[row.variantIndex];
      final quantity = double.tryParse(row.quantity.text.trim()) ?? 0;
      final cost = double.tryParse(row.cost.text.trim());
      if (variant.id == null ||
          quantity <= 0 ||
          !quantity.isFinite ||
          (product.quantityPrecision == 0 && quantity % 1 != 0) ||
          cost == null ||
          !cost.isFinite ||
          cost < 0) {
        setState(
          () => _error = 'Enter a valid quantity and unit cost for each item.',
        );
        return;
      }
      lines.add(
        PurchaseLine(
          variantId: variant.id!,
          productName: product.name,
          variantName: variant.name,
          quantity: quantity,
          costPrice: cost,
        ),
      );
    }
    Navigator.pop(context, (
      supplier: _supplier,
      lines: lines,
      note: _note.text.trim(),
    ));
  }
}

class _PurchaseDraftRow {
  int productIndex = 0;
  int variantIndex = 0;
  final quantity = TextEditingController(text: '1');
  final cost = TextEditingController();

  void dispose() {
    quantity.dispose();
    cost.dispose();
  }
}
