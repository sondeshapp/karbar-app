import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/sale.dart';
import '../../providers/cart_provider.dart';
import '../../providers/sales_provider.dart';
import '../../providers/warehouse_provider.dart';
import '../../widgets/cart_item_tile.dart';
import '../../widgets/empty_state.dart';
import '../../core/constants.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartItems = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final cf = NumberFormat.currency(locale: 'en_US', symbol: '\$');

    Future<void> completeSale() async {
      final sale = Sale(
        items: List.from(cartItems),
        totalAmount: notifier.totalAmount,
        createdAt: DateTime.now(),
      );
      await ref.read(salesProvider.notifier).completeSale(sale);
      await ref.read(warehouseProvider.notifier).loadProducts();
      if (context.mounted) {
        context.go('/receipt', extra: sale);
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(
          cartItems.isEmpty
              ? 'Cart'
              : 'Cart (${notifier.itemCount} item${notifier.itemCount == 1 ? '' : 's'})',
        ),
        actions: [
          if (cartItems.isNotEmpty)
            TextButton(
              onPressed: () {
                ref.read(cartProvider.notifier).clearCart();
              },
              child: const Text(
                'Clear',
                style: TextStyle(color: kError),
              ),
            ),
        ],
      ),
      body: cartItems.isEmpty
          ? const EmptyState(message: 'Your cart is empty.\nGo back and add some products.')
          : ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 160),
              children: [
                Container(
                  color: Colors.white,
                  child: Column(
                    children: cartItems
                        .map((item) => CartItemTile(item: item))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 12),
                // Order summary card
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: kPadding),
                  padding: const EdgeInsets.all(kPadding),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Order summary',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      _SummaryRow(
                        label:
                            '${notifier.itemCount} item${notifier.itemCount == 1 ? '' : 's'}',
                        value: cf.format(notifier.totalAmount),
                      ),
                      const Divider(height: 20),
                      _SummaryRow(
                        label: 'Total',
                        value: cf.format(notifier.totalAmount),
                        isBold: true,
                        valueColor: kPrimary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
      bottomSheet: cartItems.isEmpty
          ? null
          : _CheckoutSheet(
              total: notifier.totalAmount,
              onComplete: completeSale,
            ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
      fontSize: isBold ? 16 : 14,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(
          value,
          style: style.copyWith(color: valueColor),
        ),
      ],
    );
  }
}

class _CheckoutSheet extends StatelessWidget {
  final double total;
  final VoidCallback onComplete;

  const _CheckoutSheet({required this.total, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    final cf = NumberFormat.currency(locale: 'en_US', symbol: '\$');
    return Container(
      padding: EdgeInsets.fromLTRB(
          kPadding, 12, kPadding, MediaQuery.of(context).padding.bottom + 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 20,
              offset: Offset(0, -4))
        ],
      ),
      child: ElevatedButton(
        onPressed: onComplete,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Complete sale',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              cf.format(total),
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
