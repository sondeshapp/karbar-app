import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../db/database_helper.dart';
import '../../models/baki_payment.dart';
import '../../models/sale.dart';
import '../../providers/baki_provider.dart';

class CustomerDetailScreen extends ConsumerWidget {
  final CustomerBakiSummary summary;

  const CustomerDetailScreen({super.key, required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fmt = NumberFormat.currency(symbol: '৳', decimalDigits: 0);
    final customer = summary.customer;

    final salesAsync = ref.watch(customerBakiSalesProvider(customer.id!));
    final paymentsAsync = ref.watch(customerPaymentsProvider(customer.id!));

    // Re-compute outstanding from fresh provider data
    final totalBakiFromSales =
        salesAsync.valueOrNull?.fold(0.0, (sum, s) => sum + s.bakiAmount) ??
        summary.totalBaki;
    final totalPaidFromPayments =
        paymentsAsync.valueOrNull?.fold(0.0, (sum, p) => sum + p.amount) ??
        summary.totalPaid;
    final outstanding = totalBakiFromSales - totalPaidFromPayments;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF1F5F9),
      body: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFD97706), Color(0xFFB45309)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                left: 20,
                right: 20,
                bottom: 28,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (Navigator.canPop(context))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(40),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                            customer.name.isNotEmpty
                                ? customer.name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customer.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (customer.phone.isNotEmpty)
                              Text(
                                customer.phone,
                                style: TextStyle(
                                  color: Colors.white.withAlpha(200),
                                  fontSize: 14,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _StatChip(
                        label: 'Outstanding',
                        value: fmt.format(outstanding),
                      ),
                      const SizedBox(width: 10),
                      _StatChip(
                        label: 'Total baki',
                        value: fmt.format(totalBakiFromSales),
                      ),
                      const SizedBox(width: 10),
                      _StatChip(
                        label: 'Total paid',
                        value: fmt.format(totalPaidFromPayments),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // ── Content ─────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Baki sales
                _SectionHeader(
                  label: 'Baki Sales',
                  icon: Icons.receipt_long_rounded,
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                salesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text(
                    'Error: $e',
                    style: const TextStyle(color: Colors.red),
                  ),
                  data: (sales) => sales.isEmpty
                      ? _EmptyCard(label: 'No baki sales yet', isDark: isDark)
                      : _Card(
                          isDark: isDark,
                          child: Column(
                            children: sales
                                .asMap()
                                .entries
                                .map(
                                  (e) => Column(
                                    children: [
                                      if (e.key > 0)
                                        Divider(
                                          height: 1,
                                          color: isDark
                                              ? Colors.white.withAlpha(10)
                                              : Colors.black.withAlpha(8),
                                        ),
                                      _SaleTile(
                                        sale: e.value,
                                        fmt: fmt,
                                        isDark: isDark,
                                      ),
                                    ],
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                ),
                const SizedBox(height: 20),
                // Payments
                _SectionHeader(
                  label: 'Payments received',
                  icon: Icons.payments_rounded,
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                paymentsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text(
                    'Error: $e',
                    style: const TextStyle(color: Colors.red),
                  ),
                  data: (payments) => payments.isEmpty
                      ? _EmptyCard(
                          label: 'No payments recorded yet',
                          isDark: isDark,
                        )
                      : _Card(
                          isDark: isDark,
                          child: Column(
                            children: payments
                                .asMap()
                                .entries
                                .map(
                                  (e) => Column(
                                    children: [
                                      if (e.key > 0)
                                        Divider(
                                          height: 1,
                                          color: isDark
                                              ? Colors.white.withAlpha(10)
                                              : Colors.black.withAlpha(8),
                                        ),
                                      _PaymentTile(
                                        payment: e.value,
                                        fmt: fmt,
                                        isDark: isDark,
                                      ),
                                    ],
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                ),
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ],
      ),
      floatingActionButton: outstanding > 0
          ? FloatingActionButton.extended(
              onPressed: () => _showRecordPaymentSheet(
                context,
                ref,
                customer.id!,
                outstanding,
                fmt,
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Record Payment'),
              backgroundColor: const Color(0xFF059669),
            )
          : FloatingActionButton.extended(
              onPressed: null,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Fully paid'),
              backgroundColor: const Color(0xFF059669),
            ),
    );
  }

  void _showRecordPaymentSheet(
    BuildContext context,
    WidgetRef ref,
    int customerId,
    double outstanding,
    NumberFormat fmt,
  ) {
    final amountCtrl = TextEditingController(
      text: outstanding.toStringAsFixed(0),
    );
    final noteCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
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
              Text(
                'Record Payment',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Outstanding: ${fmt.format(outstanding)}',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount received',
                  prefixText: '৳ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () async {
                    final amt = double.tryParse(amountCtrl.text.trim());
                    if (amt == null || amt <= 0) return;
                    await DatabaseHelper().insertBakiPayment(
                      BakiPayment(
                        customerId: customerId,
                        amount: amt,
                        note: noteCtrl.text.trim(),
                        paidAt: DateTime.now(),
                      ),
                    );
                    ref.read(bakiRefreshProvider.notifier).state++;
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text(
                    'Save Payment',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withAlpha(180),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isDark;
  const _SectionHeader({
    required this.label,
    required this.icon,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: isDark ? Colors.white70 : const Color(0xFF64748B),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white70 : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final bool isDark;
  final Widget child;
  const _Card({required this.isDark, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 25 : 8),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String label;
  final bool isDark;
  const _EmptyCard({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return _Card(
      isDark: isDark,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(label, style: const TextStyle(color: Color(0xFF94A3B8))),
        ),
      ),
    );
  }
}

class _SaleTile extends StatelessWidget {
  final Sale sale;
  final NumberFormat fmt;
  final bool isDark;
  const _SaleTile({
    required this.sale,
    required this.fmt,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('d MMM, h:mm a').format(sale.createdAt);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withAlpha(22),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.receipt_rounded,
              color: Color(0xFFD97706),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sale #${sale.id}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          Text(
            fmt.format(sale.bakiAmount),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Color(0xFFD97706),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final BakiPayment payment;
  final NumberFormat fmt;
  final bool isDark;
  const _PaymentTile({
    required this.payment,
    required this.fmt,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('d MMM, h:mm a').format(payment.paidAt);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF059669).withAlpha(22),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.payments_rounded,
              color: Color(0xFF059669),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.note.isNotEmpty ? payment.note : 'Payment received',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          Text(
            fmt.format(payment.amount),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Color(0xFF059669),
            ),
          ),
        ],
      ),
    );
  }
}
