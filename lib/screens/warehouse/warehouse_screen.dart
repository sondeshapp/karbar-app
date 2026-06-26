import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
      body: products.isEmpty
          ? EmptyState(message: s.noProductsYet)
          : ListView.builder(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 8),
              itemCount: products.length,
              itemBuilder: (context, index) =>
                  ProductTile(product: products[index]),
            ),
    );
  }
}
