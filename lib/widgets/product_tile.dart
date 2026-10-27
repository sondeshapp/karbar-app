import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../providers/warehouse_provider.dart';
import '../core/constants.dart';
import '../core/quantity_format.dart';

class ProductTile extends ConsumerWidget {
  final Product product;

  const ProductTile({super.key, required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cf = NumberFormat.currency(locale: 'en_US', symbol: '\$');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: kPadding,
        vertical: 4,
      ),
      leading: _ProductThumb(imagePath: product.imagePath),
      title: Row(
        children: [
          Expanded(
            child: Text(
              product.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          if (product.isLowStock)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: Color(0xFFF59E0B),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (product.brand.isNotEmpty || product.category.isNotEmpty)
            Text(
              [
                if (product.brand.isNotEmpty) product.brand,
                if (product.category.isNotEmpty) product.category,
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          Row(
            children: [
              Text(
                '${formatQuantity(product.totalStock, product.quantityPrecision)} ${product.unit} in stock',
                style: const TextStyle(fontSize: 13),
              ),
              if (product.hasVariants) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: kSurface,
                    border: Border.all(color: kBorder),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${product.variants.length} sizes',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            product.hasVariants
                ? _priceRange(product, cf)
                : cf.format(product.price),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
      onTap: () => context.push('/warehouse/edit', extra: product),
      onLongPress: () => _confirmDelete(context, ref),
    );
  }

  String _priceRange(Product p, NumberFormat cf) {
    final prices = p.variants.map((v) => v.price).toList()..sort();
    if (prices.first == prices.last) return cf.format(prices.first);
    return '${cf.format(prices.first)}–${cf.format(prices.last)}';
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete product'),
        content: Text('Delete "${product.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: kError),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && product.id != null) {
      await ref.read(warehouseProvider.notifier).deleteProduct(product.id!);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Product deleted')));
      }
    }
  }
}

class _ProductThumb extends StatelessWidget {
  final String imagePath;
  const _ProductThumb({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    final hasImage = imagePath.isNotEmpty && File(imagePath).existsSync();
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: kSurface,
        border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: hasImage
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(File(imagePath), fit: BoxFit.cover),
            )
          : const Icon(
              Icons.inventory_2_outlined,
              size: 24,
              color: Colors.grey,
            ),
    );
  }
}
