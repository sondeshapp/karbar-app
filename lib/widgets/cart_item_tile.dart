import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/cart_item.dart';
import '../providers/cart_provider.dart';
import '../core/constants.dart';

class CartItemTile extends ConsumerWidget {
  final CartItem item;

  const CartItemTile({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cf = NumberFormat.currency(locale: 'en_US', symbol: '\$');
    final showVariant = item.variant.name.isNotEmpty &&
        item.variant.name != 'Default';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kPadding, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (showVariant)
                  Text(
                    item.variant.name,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                Text(
                  cf.format(item.total),
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove, size: 18),
                onPressed: () => ref
                    .read(cartProvider.notifier)
                    .decrementQty(item.variant.id!),
              ),
              Text('${item.quantity}',
                  style: const TextStyle(fontSize: 16)),
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                onPressed: () => ref
                    .read(cartProvider.notifier)
                    .incrementQty(item.variant.id!),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: kError),
                onPressed: () => ref
                    .read(cartProvider.notifier)
                    .removeItem(item.variant.id!),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
