import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/sale.dart';
import '../../models/customer.dart';
import '../../models/sale_payment.dart';
import '../../providers/cart_provider.dart';
import '../../providers/sales_provider.dart';
import '../../providers/warehouse_provider.dart';
import '../../providers/baki_provider.dart';
import '../../db/database_helper.dart';
import '../../widgets/cart_item_tile.dart';
import '../../widgets/empty_state.dart';
import '../../core/constants.dart';
import '../../providers/settings_provider.dart';
import '../../core/quantity_format.dart';
import '../../providers/staff_provider.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  bool _processing = false;

  Future<void> _completeSale(
    List<SalePayment> payments,
    Customer? customer,
  ) async {
    final notifier = ref.read(cartProvider.notifier);
    final cartItems = ref.read(cartProvider);
    final hasBaki = payments.any((payment) => payment.method == 'baki');
    final paymentType = hasBaki
        ? 'baki'
        : payments.length == 1
        ? payments.single.method
        : 'split';
    final sale = Sale(
      items: List.from(cartItems),
      totalAmount: notifier.totalAmount,
      createdAt: DateTime.now(),
      paymentType: paymentType,
      customerId: customer?.id,
      customerName: customer?.name,
      discountAmount: notifier.orderDiscount,
      discountType: notifier.orderDiscountType,
      taxAmount: notifier.taxAmount,
      payments: payments,
      staffId: ref.read(activeStaffProvider)?.id,
    );
    try {
      await ref.read(salesProvider.notifier).completeSale(sale);
      await ref.read(warehouseProvider.notifier).loadProducts();
      if (paymentType == 'baki') {
        ref.read(bakiRefreshProvider.notifier).state++;
      }
      ref.read(cartProvider.notifier).clearCart();
      if (mounted) context.go('/receipt', extra: sale);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sale failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _showPaymentSheet(double total) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PaymentSheet(
        total: total,
        onComplete: (payments, customer) {
          Navigator.pop(ctx);
          setState(() => _processing = true);
          _completeSale(payments, customer);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final cf = NumberFormat.currency(
      locale: settings.currencyLocale,
      symbol: settings.currencySymbol,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(
          cartItems.isEmpty
              ? 'Cart'
              : 'Cart (${formatQuantity(notifier.itemCount, 3)} items)',
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
              message: 'Your cart is empty.\nGo back and add some products.',
            )
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
                      const Text(
                        'Order summary',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SummaryRow(
                        label: '${formatQuantity(notifier.itemCount, 3)} items',
                        value: cf.format(notifier.subtotal),
                      ),
                      const SizedBox(height: 10),
                      _OrderDiscountInput(cf: cf),
                      if (notifier.orderDiscountFlat > 0)
                        _SummaryRow(
                          label: 'Discount',
                          value: '-${cf.format(notifier.orderDiscountFlat)}',
                          valueColor: kError,
                        ),
                      if (settings.showTax && settings.taxRate > 0)
                        _SummaryRow(
                          label:
                              'VAT (${(settings.taxRate * 100).toStringAsFixed(0)}%)',
                          value: cf.format(notifier.taxAmount),
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
              processing: _processing,
              onComplete: () => _showPaymentSheet(notifier.totalAmount),
            ),
    );
  }
}

// ── Payment method bottom sheet ───────────────────────────────────────────────

class _PaymentSheet extends ConsumerStatefulWidget {
  final double total;
  final void Function(List<SalePayment> payments, Customer? customer)
  onComplete;

  const _PaymentSheet({required this.total, required this.onComplete});

  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet> {
  bool _showingCustomerPicker = false;
  final _searchCtrl = TextEditingController();
  late final TextEditingController _cashCtrl;
  final _bkashCtrl = TextEditingController(text: '0');
  final _nagadCtrl = TextEditingController(text: '0');
  final _cardCtrl = TextEditingController(text: '0');
  String _query = '';

  @override
  void initState() {
    super.initState();
    _cashCtrl = TextEditingController(text: widget.total.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _cashCtrl.dispose();
    _bkashCtrl.dispose();
    _nagadCtrl.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  List<SalePayment>? _paymentsFor() {
    final values = <({String method, TextEditingController controller})>[
      (method: 'cash', controller: _cashCtrl),
      (method: 'bkash', controller: _bkashCtrl),
      (method: 'nagad', controller: _nagadCtrl),
      (method: 'card', controller: _cardCtrl),
    ];
    final payments = <SalePayment>[];
    var paid = 0.0;
    for (final value in values) {
      final amount = double.tryParse(value.controller.text.trim());
      if (amount == null || !amount.isFinite || amount < 0) return null;
      if (amount > 0) {
        payments.add(SalePayment(method: value.method, amount: amount));
        paid += amount;
      }
    }
    if (paid > widget.total + 0.01) return null;
    final baki = (widget.total - paid).clamp(0.0, double.infinity);
    if (baki > 0.01) {
      payments.add(SalePayment(method: 'baki', amount: baki));
    } else if (payments.isNotEmpty && (widget.total - paid).abs() <= 0.01) {
      final last = payments.removeLast();
      payments.add(
        SalePayment(
          method: last.method,
          amount: last.amount + widget.total - paid,
        ),
      );
    }
    if (payments.isEmpty) return null;
    return payments;
  }

  void _continue(Customer? customer) {
    final payments = _paymentsFor();
    if (payments == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(stringsProvider).enterValidPayment)),
      );
      return;
    }
    if (payments.any((payment) => payment.method == 'baki') &&
        customer == null) {
      setState(() => _showingCustomerPicker = true);
      return;
    }
    widget.onComplete(payments, customer);
  }

  double get _paidAmount => [_cashCtrl, _bkashCtrl, _nagadCtrl, _cardCtrl].fold(
    0.0,
    (sum, controller) => sum + (double.tryParse(controller.text.trim()) ?? 0),
  );

  Widget _amountField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required void Function(String) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (_) => onChanged(''),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final s = ref.watch(stringsProvider);
    final cf = NumberFormat.currency(
      locale: settings.currencyLocale,
      symbol: settings.currencySymbol,
    );
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
              onCustomerSelected: (customer) => _continue(customer),
              onBack: () => setState(() {
                _showingCustomerPicker = false;
                _query = '';
                _searchCtrl.clear();
              }),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    s.payment,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total ${cf.format(widget.total)}',
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: kPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _amountField(
                    label: s.cash,
                    icon: Icons.payments_rounded,
                    controller: _cashCtrl,
                    onChanged: (_) => setState(() {}),
                  ),
                  _amountField(
                    label: s.bkash,
                    icon: Icons.phone_android_rounded,
                    controller: _bkashCtrl,
                    onChanged: (_) => setState(() {}),
                  ),
                  _amountField(
                    label: s.nagad,
                    icon: Icons.account_balance_wallet_outlined,
                    controller: _nagadCtrl,
                    onChanged: (_) => setState(() {}),
                  ),
                  _amountField(
                    label: s.card,
                    icon: Icons.credit_card_rounded,
                    controller: _cardCtrl,
                    onChanged: (_) => setState(() {}),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [Text(s.received), Text(cf.format(_paidAmount))],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(s.remainingBaki),
                      Text(
                        cf.format(
                          (widget.total - _paidAmount).clamp(
                            0.0,
                            double.infinity,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: () => _continue(null),
                      child: Text(s.continuePayment),
                    ),
                  ),
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
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Select Customer',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
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
              hintStyle: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 20,
                color: Color(0xFF9CA3AF),
              ),
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
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) =>
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
                    child: const Icon(
                      Icons.person_add_rounded,
                      color: kPrimary,
                      size: 18,
                    ),
                  ),
                  title: Text(
                    query.isNotEmpty
                        ? 'Add "$query" as new customer'
                        : 'Add new customer',
                    style: const TextStyle(
                      color: kPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () => _showAddCustomerDialog(context, ref, query),
                  contentPadding: EdgeInsets.zero,
                ),
                const Divider(height: 8),
                ...customers.map(
                  (c) => ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF64748B).withAlpha(18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: Color(0xFF64748B),
                        size: 18,
                      ),
                    ),
                    title: Text(
                      c.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: c.phone.isNotEmpty ? Text(c.phone) : null,
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
    BuildContext context,
    WidgetRef ref,
    String initialName,
  ) {
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
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final customer = Customer(
                name: name,
                phone: phoneCtrl.text.trim(),
                createdAt: DateTime.now(),
              );
              final id = await DatabaseHelper().insertCustomer(customer);
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

// ── Order-level discount input ────────────────────────────────────────────────

class _OrderDiscountInput extends ConsumerStatefulWidget {
  final NumberFormat cf;
  const _OrderDiscountInput({required this.cf});

  @override
  ConsumerState<_OrderDiscountInput> createState() =>
      _OrderDiscountInputState();
}

class _OrderDiscountInputState extends ConsumerState<_OrderDiscountInput> {
  final _ctrl = TextEditingController();
  bool _isPercent = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 36,
            child: TextField(
              controller: _ctrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Discount',
                hintStyle: const TextStyle(fontSize: 13),
                prefixText: _isPercent ? '' : '${widget.cf.currencySymbol} ',
                suffixText: _isPercent ? '%' : null,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              onChanged: (v) {
                final amount = double.tryParse(v) ?? 0;
                ref
                    .read(cartProvider.notifier)
                    .setOrderDiscount(amount, _isPercent ? 'percent' : 'flat');
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            setState(() => _isPercent = !_isPercent);
            final amount = double.tryParse(_ctrl.text) ?? 0;
            ref
                .read(cartProvider.notifier)
                .setOrderDiscount(amount, _isPercent ? 'percent' : 'flat');
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _isPercent ? kPrimary : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: _isPercent ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CheckoutSheet extends ConsumerWidget {
  final double total;
  final bool processing;
  final VoidCallback onComplete;

  const _CheckoutSheet({
    required this.total,
    required this.onComplete,
    this.processing = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final cf = NumberFormat.currency(
      locale: settings.currencyLocale,
      symbol: settings.currencySymbol,
    );
    return Container(
      padding: EdgeInsets.fromLTRB(
        kPadding,
        12,
        kPadding,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: processing ? null : onComplete,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: processing
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Complete sale',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    cf.format(total),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
