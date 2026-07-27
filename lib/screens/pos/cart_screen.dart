import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/sale.dart';
import '../../models/customer.dart';
import '../../providers/cart_provider.dart';
import '../../providers/sales_provider.dart';
import '../../providers/warehouse_provider.dart';
import '../../providers/baki_provider.dart';
import '../../db/database_helper.dart';
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

    Future<void> completeSale(
        String paymentType, int? customerId, String? customerName) async {
      final sale = Sale(
        items: List.from(cartItems),
        totalAmount: notifier.totalAmount,
        createdAt: DateTime.now(),
        paymentType: paymentType,
        customerId: customerId,
        customerName: customerName,
      );
      await ref.read(salesProvider.notifier).completeSale(sale);
      await ref.read(warehouseProvider.notifier).loadProducts();
      if (paymentType == 'baki') {
        ref.read(bakiRefreshProvider.notifier).state++;
      }
      if (context.mounted) {
        context.go('/receipt', extra: sale);
      }
    }

    void showPaymentSheet() {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _PaymentSheet(
          total: notifier.totalAmount,
          onCash: () {
            Navigator.pop(ctx);
            completeSale('cash', null, null);
          },
          onBaki: (Customer customer) {
            Navigator.pop(ctx);
            completeSale('baki', customer.id, customer.name);
          },
        ),
      );
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
              onPressed: () => ref.read(cartProvider.notifier).clearCart(),
              child: const Text('Clear', style: TextStyle(color: kError)),
            ),
        ],
      ),
      body: cartItems.isEmpty
          ? const EmptyState(
              message: 'Your cart is empty.\nGo back and add some products.')
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
                      const Text('Order summary',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
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
              onComplete: showPaymentSheet,
            ),
    );
  }
}

// ── Payment method bottom sheet ───────────────────────────────────────────────

class _PaymentSheet extends ConsumerStatefulWidget {
  final double total;
  final VoidCallback onCash;
  final ValueChanged<Customer> onBaki;

  const _PaymentSheet({
    required this.total,
    required this.onCash,
    required this.onBaki,
  });

  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet> {
  bool _showingCustomerPicker = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cf = NumberFormat.currency(locale: 'en_US', symbol: '\$');
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomPad),
      child: _showingCustomerPicker
          ? _CustomerPicker(
              query: _query,
              searchCtrl: _searchCtrl,
              onQueryChanged: (v) => setState(() => _query = v),
              onCustomerSelected: widget.onBaki,
              onBack: () => setState(() {
                _showingCustomerPicker = false;
                _query = '';
                _searchCtrl.clear();
              }),
            )
          : _MethodChooser(
              total: widget.total,
              fmt: cf,
              onCash: widget.onCash,
              onBaki: () => setState(() => _showingCustomerPicker = true),
            ),
    );
  }
}

class _MethodChooser extends StatelessWidget {
  final double total;
  final NumberFormat fmt;
  final VoidCallback onCash;
  final VoidCallback onBaki;

  const _MethodChooser({
    required this.total,
    required this.fmt,
    required this.onCash,
    required this.onBaki,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const Text(
          'How is the customer paying?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          fmt.format(total),
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: kPrimary,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _PayButton(
                icon: Icons.payments_rounded,
                label: 'Nagad',
                sublabel: 'Pay now',
                color: const Color(0xFF059669),
                onTap: onCash,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PayButton(
                icon: Icons.pending_actions_rounded,
                label: 'বাকি',
                sublabel: 'Pay later',
                color: const Color(0xFFF59E0B),
                onTap: onBaki,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PayButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;
  final VoidCallback onTap;

  const _PayButton({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(60), width: 1.5),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: color)),
            const SizedBox(height: 2),
            Text(sublabel,
                style:
                    TextStyle(fontSize: 12, color: color.withAlpha(180))),
          ],
        ),
      ),
    );
  }
}

// ── Customer picker ───────────────────────────────────────────────────────────

class _CustomerPicker extends ConsumerWidget {
  final String query;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Customer> onCustomerSelected;
  final VoidCallback onBack;

  const _CustomerPicker({
    required this.query,
    required this.searchCtrl,
    required this.onQueryChanged,
    required this.onCustomerSelected,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersAsync = ref.watch(customerSearchProvider(query));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          children: [
            GestureDetector(
              onTap: onBack,
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 18, color: Color(0xFF64748B)),
            ),
            const SizedBox(width: 8),
            const Text('Select Customer',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: searchCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search by name or phone...',
              hintStyle:
                  TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
              prefixIcon: Icon(Icons.search_rounded,
                  size: 20, color: Color(0xFF9CA3AF)),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
            onChanged: onQueryChanged,
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: customersAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (_, __) =>
                const Center(child: Text('Error loading customers')),
            data: (customers) => ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: kPrimary.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.person_add_rounded,
                        color: kPrimary, size: 18),
                  ),
                  title: Text(
                    query.isNotEmpty
                        ? 'Add "$query" as new customer'
                        : 'Add new customer',
                    style: const TextStyle(
                        color: kPrimary, fontWeight: FontWeight.w600),
                  ),
                  onTap: () =>
                      _showAddCustomerDialog(context, ref, query),
                  contentPadding: EdgeInsets.zero,
                ),
                const Divider(height: 8),
                ...customers.map(
                  (c) => ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color:
                            const Color(0xFF64748B).withAlpha(18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.person_rounded,
                          color: Color(0xFF64748B), size: 18),
                    ),
                    title: Text(c.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600)),
                    subtitle:
                        c.phone.isNotEmpty ? Text(c.phone) : null,
                    onTap: () => onCustomerSelected(c),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (customers.isEmpty && query.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'No customers yet. Add one above.',
                        style: TextStyle(color: Color(0xFF9CA3AF)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showAddCustomerDialog(
      BuildContext context, WidgetRef ref, String initialName) {
    final nameCtrl = TextEditingController(text: initialName);
    final phoneCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Customer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name *',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(
                labelText: 'Phone (optional)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final customer = Customer(
                name: name,
                phone: phoneCtrl.text.trim(),
                createdAt: DateTime.now(),
              );
              final id =
                  await DatabaseHelper().insertCustomer(customer);
              final saved = Customer(
                id: id,
                name: customer.name,
                phone: customer.phone,
                createdAt: customer.createdAt,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              onCustomerSelected(saved);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

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
        Text(value, style: style.copyWith(color: valueColor)),
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
      padding: EdgeInsets.fromLTRB(kPadding, 12, kPadding,
          MediaQuery.of(context).padding.bottom + 12),
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
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Complete sale',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            Text(cf.format(total),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
