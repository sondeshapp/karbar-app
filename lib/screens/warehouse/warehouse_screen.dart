import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/product.dart';
import '../../providers/warehouse_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/product_tile.dart';
import '../../widgets/empty_state.dart';

class WarehouseScreen extends ConsumerStatefulWidget {
  const WarehouseScreen({super.key});

  @override
  ConsumerState<WarehouseScreen> createState() => _WarehouseScreenState();
}

class _WarehouseScreenState extends ConsumerState<WarehouseScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(warehouseProvider.notifier).loadProducts();
    });
  }

  /// Scan a barcode from the warehouse screen.
  /// - If the barcode matches an existing product → open its edit form (restock).
  /// - If no match → open a blank add form with the barcode pre-filled.
  Future<void> _scanToAddOrRestock() async {
    final barcode = await context.push<String>('/warehouse/scanner');
    if (barcode == null || barcode.isEmpty || !mounted) return;

    final products = ref.read(warehouseProvider);
    for (final product in products) {
      for (final variant in product.variants) {
        if (variant.barcode.isNotEmpty && variant.barcode == barcode) {
          // Found — open edit form so shopkeeper can update stock
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${product.name} found — update stock to restock'),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
            context.push('/warehouse/edit', extra: product);
          }
          return;
        }
      }
    }

    // Not found — new product; pass barcode so the form pre-fills it
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New product — fill in the details'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.push('/warehouse/add', extra: barcode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(warehouseProvider);
    final s = ref.watch(stringsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.warehouse),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: 'Scan to add / restock',
            onPressed: _scanToAddOrRestock,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/warehouse/add'),
          ),
        ],
      ),
      floatingActionButton: products.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showStockInSheet(context, ref, products),
              icon: const Icon(Icons.add_box_rounded),
              label: const Text('Stock In'),
              backgroundColor: const Color(0xFF059669),
            ),
      body: products.isEmpty
          ? EmptyState(message: s.noProductsYet)
          : ListView.builder(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 80),
              itemCount: products.length,
              itemBuilder: (context, index) =>
                  ProductTile(product: products[index]),
            ),
    );
  }

  void _showStockInSheet(BuildContext context, WidgetRef ref, List<Product> products) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StockInSheet(
        products: ref.read(warehouseProvider),
        onConfirm: (variantId, qty, costPrice) =>
            ref.read(warehouseProvider.notifier).stockIn(
              variantId, qty, costPrice: costPrice,
            ),
      ),
    );
  }
}

// ── Stock-In bottom sheet ─────────────────────────────────────────────────────

class _StockInSheet extends StatefulWidget {
  final List<Product> products;
  final Future<void> Function(int variantId, int qty, double costPrice) onConfirm;

  const _StockInSheet({required this.products, required this.onConfirm});

  @override
  State<_StockInSheet> createState() => _StockInSheetState();
}

class _StockInSheetState extends State<_StockInSheet> {
  int _productIdx = 0;
  int _variantIdx = 0;
  final _qtyCtrl = TextEditingController(text: '1');
  final _costCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  Product get _product => widget.products[_productIdx];

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + pad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text('Stock In',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          // Product picker
          DropdownButtonFormField<int>(
            initialValue: _productIdx,
            decoration: const InputDecoration(
              labelText: 'Product',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: widget.products.asMap().entries.map((e) =>
              DropdownMenuItem(value: e.key, child: Text(e.value.name)),
            ).toList(),
            onChanged: (v) => setState(() { _productIdx = v!; _variantIdx = 0; }),
          ),
          if (_product.variants.length > 1) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _variantIdx,
              decoration: const InputDecoration(
                labelText: 'Variant',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _product.variants.asMap().entries.map((e) =>
                DropdownMenuItem(value: e.key, child: Text(e.value.name)),
              ).toList(),
              onChanged: (v) => setState(() => _variantIdx = v!),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantity *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _costCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Cost price (opt.)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _loading ? null : () async {
                final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
                if (qty <= 0) return;
                final variant = _product.variants[_variantIdx];
                if (variant.id == null) return;
                final cost = double.tryParse(_costCtrl.text.trim()) ?? 0;
                setState(() => _loading = true);
                await widget.onConfirm(variant.id!, qty, cost);
                if (!mounted) return;
                Navigator.pop(this.context);
              },
              child: _loading
                ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                : const Text('Confirm Stock In',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
