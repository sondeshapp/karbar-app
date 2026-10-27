import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../models/product_variant.dart';
import '../providers/cart_provider.dart';
import '../core/constants.dart';
import '../core/quantity_format.dart';

// Consistent pastel gradients for products without an image
const _placeholderGradients = [
  [Color(0xFF6366F1), Color(0xFF4F46E5)],
  [Color(0xFF10B981), Color(0xFF059669)],
  [Color(0xFFF59E0B), Color(0xFFD97706)],
  [Color(0xFFEF4444), Color(0xFFDC2626)],
  [Color(0xFFEC4899), Color(0xFFDB2777)],
  [Color(0xFF0EA5E9), Color(0xFF0284C7)],
  [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
];

class ProductGridCard extends ConsumerWidget {
  final Product product;
  final void Function(Product, ProductVariant) onVariantPick;

  const ProductGridCard({
    super.key,
    required this.product,
    required this.onVariantPick,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cf = NumberFormat.currency(locale: 'en_US', symbol: '\$');
    final cartItems = ref.watch(cartProvider);

    final singleVariant = !product.hasVariants && product.variants.isNotEmpty
        ? product.variants.first
        : null;

    final singleQty = singleVariant != null
        ? (cartItems
                  .where((i) => i.variant.id == singleVariant.id)
                  .firstOrNull
                  ?.quantity ??
              0.0)
        : 0.0;

    final multiQty = product.hasVariants
        ? cartItems
              .where((i) => i.product.id == product.id)
              .fold(0.0, (s, i) => s + i.quantity)
        : 0.0;

    void handleAdd() {
      if (product.variants.isEmpty) return;
      if (!product.hasVariants) {
        ref
            .read(cartProvider.notifier)
            .addItem(product, product.variants.first);
      } else {
        onVariantPick(product, product.variants.first);
      }
    }

    final gradIdx = product.name.isEmpty
        ? 0
        : product.name.codeUnitAt(0) % _placeholderGradients.length;
    final gradColors = _placeholderGradients[gradIdx];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image area
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(14),
                  ),
                  child: SizedBox.expand(child: _productImage(gradColors)),
                ),
                // Add / qty control
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: singleVariant != null && singleQty > 0
                      ? _QtyPill(
                          qty: singleQty,
                          onDec: () => ref
                              .read(cartProvider.notifier)
                              .decrementQty(singleVariant.id!),
                          onInc: () => ref
                              .read(cartProvider.notifier)
                              .incrementQty(singleVariant.id!),
                        )
                      : _AddCircle(qty: multiQty, onTap: handleAdd),
                ),
                // Multi-variant badge
                if (product.hasVariants && multiQty > 0)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: kPrimary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$multiQty in cart',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Info area
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Price row
                  Row(
                    children: [
                      Text(
                        product.hasVariants
                            ? _priceRange(product, cf)
                            : cf.format(product.price),
                        style: const TextStyle(
                          color: kPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      if (product.hasVariants) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: kSurface,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${product.variants.length} sizes',
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: kText,
                      height: 1.3,
                    ),
                  ),
                  if (product.brand.isNotEmpty)
                    Text(
                      product.brand,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _productImage(List<Color> gradColors) {
    if (product.imagePath.isNotEmpty && File(product.imagePath).existsSync()) {
      return Image.file(File(product.imagePath), fit: BoxFit.cover);
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          product.name.isNotEmpty ? product.name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 44,
            fontWeight: FontWeight.bold,
            color: Colors.white.withAlpha(200),
          ),
        ),
      ),
    );
  }

  String _priceRange(Product p, NumberFormat cf) {
    final prices = p.variants.map((v) => v.price).toList()..sort();
    if (prices.first == prices.last) return cf.format(prices.first);
    return '${cf.format(prices.first)}+';
  }
}

// ── Add circle button ──────────────────────────────────────────────────────

class _AddCircle extends StatelessWidget {
  final double qty;
  final VoidCallback onTap;

  const _AddCircle({required this.qty, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: qty > 0 ? kPrimary : Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(40),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          Icons.add_rounded,
          size: 20,
          color: qty > 0 ? Colors.white : kPrimary,
        ),
      ),
    );
  }
}

// ── Quantity pill ──────────────────────────────────────────────────────────

class _QtyPill extends StatelessWidget {
  final double qty;
  final VoidCallback onDec;
  final VoidCallback onInc;

  const _QtyPill({required this.qty, required this.onDec, required this.onInc});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: kPrimary,
        borderRadius: BorderRadius.circular(17),
        boxShadow: [
          BoxShadow(
            color: kPrimary.withAlpha(100),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PillBtn(icon: Icons.remove_rounded, onTap: onDec),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              formatQuantity(qty, 3),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          _PillBtn(icon: Icons.add_rounded, onTap: onInc),
        ],
      ),
    );
  }
}

class _PillBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _PillBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 34,
        alignment: Alignment.center,
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }
}
