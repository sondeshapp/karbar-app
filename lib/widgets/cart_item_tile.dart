import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/cart_item.dart';
import '../providers/cart_provider.dart';
import '../providers/settings_provider.dart';
import '../core/constants.dart';

class CartItemTile extends ConsumerWidget {
  final CartItem item;

  const CartItemTile({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final cf = NumberFormat.currency(locale: settings.currencyLocale, symbol: settings.currencySymbol);
    final showVariant = item.variant.name.isNotEmpty && item.variant.name != 'Default';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kPadding, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onLongPress: () => _showDiscountDialog(context, ref, cf),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.product.name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (showVariant)
                    Text(item.variant.name,
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  Row(
                    children: [
                      Text(cf.format(item.total),
                          style: const TextStyle(fontSize: 13, color: Colors.grey)),
                      if (item.discountAmount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: kError.withAlpha(20),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '-${cf.format(item.discountAmount)}/item',
                            style: const TextStyle(fontSize: 10, color: kError, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove, size: 18),
                onPressed: () => ref.read(cartProvider.notifier).decrementQty(item.variant.id!),
              ),
              Text('${item.quantity}', style: const TextStyle(fontSize: 16)),
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                onPressed: () => ref.read(cartProvider.notifier).incrementQty(item.variant.id!),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: kError),
                onPressed: () => ref.read(cartProvider.notifier).removeItem(item.variant.id!),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDiscountDialog(BuildContext context, WidgetRef ref, NumberFormat cf) {
    final ctrl = TextEditingController(
      text: item.discountAmount > 0 ? item.discountAmount.toStringAsFixed(0) : '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Discount — ${item.product.name}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Flat discount per item',
            prefixText: '${cf.currencySymbol} ',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(cartProvider.notifier).setItemDiscount(item.variant.id!, 0);
              Navigator.pop(ctx);
            },
            child: const Text('Remove'),
          ),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim()) ?? 0;
              ref.read(cartProvider.notifier).setItemDiscount(item.variant.id!, v);
              Navigator.pop(ctx);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}
