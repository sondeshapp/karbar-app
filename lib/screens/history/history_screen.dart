import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../../core/app_strings.dart';
import '../../providers/sales_provider.dart';
import '../../providers/settings_provider.dart';
import '../../db/database_helper.dart';
import '../../models/sale.dart';
import '../../providers/warehouse_provider.dart';
import '../../models/customer.dart';
import '../../core/quantity_format.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _search = TextEditingController();
  List<Customer> _customers = [];
  DateTimeRange? _dateRange;
  String _method = 'all';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHistory();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      await Future.wait([
        initializeDateFormatting('en_US'),
        initializeDateFormatting('bn_BD'),
      ]);
      await ref.read(salesProvider.notifier).loadSales();
      final customers = await DatabaseHelper().getAllCustomers();
      if (mounted) setState(() => _customers = customers);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseDateRange() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _dateRange,
    );
    if (selected != null) setState(() => _dateRange = selected);
  }

  Future<void> _showReturnDialog(BuildContext context, Sale sale) async {
    final s = ref.read(stringsProvider);
    final settings = ref.read(settingsProvider);
    final currency = NumberFormat.currency(
      locale: settings.currencyLocale,
      symbol: settings.currencySymbol,
    );
    final reasonController = TextEditingController();
    final selected = <int, double>{};
    var refundMethod = 'cash';
    final result =
        await showDialog<
          ({Map<int, double> quantities, String reason, String method})
        >(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(s.recordReturn),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in sale.items)
                        if (item.saleItemId != null &&
                            item.quantity > item.returnedQuantity)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.product.name} · ${s.quantityRemaining(formatQuantity(item.quantity - item.returnedQuantity, item.product.quantityPrecision))}',
                                  ),
                                ),
                                SizedBox(
                                  width: 100,
                                  child: TextFormField(
                                    initialValue: formatQuantity(
                                      selected[item.saleItemId!] ?? 0.0,
                                      item.product.quantityPrecision,
                                    ),
                                    keyboardType:
                                        TextInputType.numberWithOptions(
                                          decimal:
                                              item.product.quantityPrecision >
                                              0,
                                        ),
                                    decoration: InputDecoration(
                                      labelText: s.returnQuantity,
                                      isDense: true,
                                    ),
                                    onChanged: (value) => setDialogState(() {
                                      selected[item.saleItemId!] =
                                          double.tryParse(value) ?? 0;
                                    }),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      TextField(
                        controller: reasonController,
                        decoration: InputDecoration(
                          labelText: s.returnReason,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: refundMethod,
                        decoration: InputDecoration(
                          labelText: s.refundMethod,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final method in [
                            'cash',
                            'bkash',
                            'nagad',
                            'card',
                          ])
                            DropdownMenuItem(
                              value: method,
                              child: Text(s.paymentMethodLabel(method)),
                            ),
                          if (sale.customerId != null && sale.bakiAmount > 0)
                            DropdownMenuItem(
                              value: 'baki',
                              child: Text(s.reduceBaki),
                            ),
                        ],
                        onChanged: (value) => setDialogState(
                          () => refundMethod = value ?? 'cash',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(s.historyCancel),
                ),
                FilledButton(
                  onPressed: () {
                    final quantities = Map<int, double>.fromEntries(
                      selected.entries.where((entry) => entry.value > 0),
                    );
                    final reason = reasonController.text.trim();
                    if (quantities.isEmpty || reason.isEmpty) return;
                    Navigator.pop(dialogContext, (
                      quantities: quantities,
                      reason: reason,
                      method: refundMethod,
                    ));
                  },
                  child: Text(s.saveReturn),
                ),
              ],
            ),
          ),
        );
    reasonController.dispose();
    if (result == null || !context.mounted) return;
    try {
      final returned = await DatabaseHelper().createSaleReturn(
        saleId: sale.id!,
        quantitiesBySaleItemId: result.quantities,
        reason: result.reason,
        refundMethod: result.method,
      );
      await ref.read(salesProvider.notifier).loadSales();
      await ref.read(warehouseProvider.notifier).loadProducts();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.returnRecorded(currency.format(returned.amount))),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.returnFailed(error.toString()))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sales = ref.watch(salesProvider);
    final s = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final locale = s.isBn ? 'bn_BD' : 'en_US';
    final dateLocale = _loading ? 'en_US' : locale;
    final dateFormat = DateFormat('dd MMM yyyy · hh:mm a', dateLocale);
    final cf = NumberFormat.currency(
      locale: settings.currencyLocale,
      symbol: settings.currencySymbol,
    );
    final customerById = {
      for (final customer in _customers) customer.id: customer,
    };
    final query = _search.text.trim().toLowerCase();
    final visibleSales = sales.where((sale) {
      final customer = customerById[sale.customerId];
      final matchesQuery =
          query.isEmpty ||
          '${sale.id}'.contains(query) ||
          (sale.customerName ?? '').toLowerCase().contains(query) ||
          (customer?.phone ?? '').toLowerCase().contains(query);
      final matchesMethod =
          _method == 'all' ||
          (sale.payments.isNotEmpty
              ? sale.payments.any((payment) => payment.method == _method)
              : sale.paymentType == _method);
      final matchesDate =
          _dateRange == null ||
          (!sale.createdAt.isBefore(
                DateTime(
                  _dateRange!.start.year,
                  _dateRange!.start.month,
                  _dateRange!.start.day,
                ),
              ) &&
              sale.createdAt.isBefore(
                DateTime(
                  _dateRange!.end.year,
                  _dateRange!.end.month,
                  _dateRange!.end.day + 1,
                ),
              ));
      return matchesQuery && matchesMethod && matchesDate;
    }).toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBackground = isDark
        ? const Color(0xFF0F172A)
        : const Color(0xFFF1F5F9);
    final surface = isDark ? const Color(0xFF1E293B) : Colors.white;
    final outline = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final searchFill = isDark
        ? const Color(0xFF0F172A)
        : const Color(0xFFF8FAFC);
    final dateLabel = _dateRange == null
        ? s.historyDates
        : '${DateFormat('d MMM', dateLocale).format(_dateRange!.start)}–${DateFormat('d MMM', dateLocale).format(_dateRange!.end)}';
    void clearFilters() {
      setState(() {
        _search.clear();
        _method = 'all';
        _dateRange = null;
      });
    }

    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(
        title: Text(s.salesHistory),
        backgroundColor: pageBackground,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: outline),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 14 : 7),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: s.searchHistoryHint,
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF2563EB),
                    ),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: s.clearFilters,
                            onPressed: () => setState(_search.clear),
                            icon: const Icon(Icons.close_rounded),
                          ),
                    filled: true,
                    fillColor: searchFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: BorderSide(color: outline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: BorderSide(color: outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: const BorderSide(
                        color: Color(0xFF2563EB),
                        width: 1.5,
                      ),
                    ),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _method,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: s.historyPaymentMethod,
                          filled: true,
                          fillColor: searchFill,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(13),
                            borderSide: BorderSide(color: outline),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(13),
                            borderSide: BorderSide(color: outline),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          isDense: true,
                        ),
                        items: [
                          for (final method in [
                            'all',
                            'cash',
                            'bkash',
                            'nagad',
                            'card',
                            'baki',
                          ])
                            DropdownMenuItem(
                              value: method,
                              child: Text(
                                method == 'all'
                                    ? s.allPaymentMethods
                                    : s.paymentMethodLabel(method),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _method = value ?? 'all'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: const Color(
                        0xFF2563EB,
                      ).withAlpha(isDark ? 35 : 16),
                      borderRadius: BorderRadius.circular(13),
                      child: InkWell(
                        onTap: _chooseDateRange,
                        borderRadius: BorderRadius.circular(13),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: 56,
                            maxWidth: 142,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.calendar_month_rounded,
                                  size: 18,
                                  color: Color(0xFF2563EB),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    dateLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF2563EB),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                if (_dateRange != null)
                                  Tooltip(
                                    message: s.clearDateFilter,
                                    child: GestureDetector(
                                      onTap: () =>
                                          setState(() => _dateRange = null),
                                      child: Padding(
                                        padding: const EdgeInsets.only(left: 4),
                                        child: Icon(
                                          Icons.close_rounded,
                                          size: 16,
                                          color: isDark
                                              ? Colors.white70
                                              : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : sales.isEmpty
                ? _HistoryEmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: s.noSalesYet,
                    description: s.noSalesYetDescription,
                    actionLabel: s.startSale,
                    isDark: isDark,
                    onPressed: () => context.push('/pos'),
                  )
                : visibleSales.isEmpty
                ? _HistoryEmptyState(
                    icon: Icons.filter_alt_off_rounded,
                    title: s.noSalesMatchFilters,
                    description: s.adjustHistoryFilters,
                    actionLabel: s.clearFilters,
                    isDark: isDark,
                    onPressed: clearFilters,
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      MediaQuery.of(context).padding.bottom + 16,
                    ),
                    itemCount: visibleSales.length,
                    itemBuilder: (context, index) {
                      final sale = visibleSales[index];
                      final totalItems = sale.items.fold(
                        0.0,
                        (sum, i) => sum + i.quantity,
                      );
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: outline),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(isDark ? 12 : 6),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ExpansionTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          collapsedShape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          title: Text(
                            s.saleNumber((sale.id ?? index + 1).toString()),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${dateFormat.format(sale.createdAt)} · ${s.itemsText(totalItems)}',
                          ),
                          trailing: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                cf.format(sale.totalAmount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2563EB),
                                ),
                              ),
                              const SizedBox(height: 3),
                              _PaymentChip(type: sale.paymentType, strings: s),
                            ],
                          ),
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  right: 16,
                                  top: 4,
                                ),
                                child: TextButton.icon(
                                  onPressed: () => context.push(
                                    '/receipt?history=1',
                                    extra: sale,
                                  ),
                                  icon: const Icon(Icons.receipt_long_outlined),
                                  label: Text(s.reprintShareReceipt),
                                ),
                              ),
                            ),
                            ...sale.items.map((item) {
                              final showVariant =
                                  item.variant.name.isNotEmpty &&
                                  item.variant.name != 'Default';
                              return ListTile(
                                dense: true,
                                title: Text(item.product.name),
                                subtitle: showVariant
                                    ? Text(item.variant.name)
                                    : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '×${formatQuantity(item.quantity, item.product.quantityPrecision)}  ',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(cf.format(item.total)),
                                  ],
                                ),
                              );
                            }),
                            if (sale.items.any(
                              (item) => item.quantity > item.returnedQuantity,
                            ))
                              Align(
                                alignment: Alignment.centerRight,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    right: 16,
                                    bottom: 8,
                                  ),
                                  child: TextButton.icon(
                                    onPressed: () =>
                                        _showReturnDialog(context, sale),
                                    icon: const Icon(
                                      Icons.assignment_return_outlined,
                                    ),
                                    label: Text(s.returnItems),
                                  ),
                                ),
                              ),
                            if (sale.returnedAmount > 0)
                              ListTile(
                                dense: true,
                                title: Text(s.returned),
                                trailing: Text(
                                  '-${cf.format(sale.returnedAmount)}',
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PaymentChip extends StatelessWidget {
  final String type;
  final AppStrings strings;

  const _PaymentChip({required this.type, required this.strings});

  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      'baki' => const Color(0xFFF59E0B),
      'split' => const Color(0xFF7C3AED),
      'bkash' || 'nagad' || 'card' => const Color(0xFF2563EB),
      _ => const Color(0xFF059669),
    };
    final label = strings.paymentMethodLabel(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _HistoryEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final bool isDark;
  final VoidCallback onPressed;

  const _HistoryEmptyState({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.isDark,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withAlpha(isDark ? 30 : 16),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Icon(icon, size: 38, color: const Color(0xFF2563EB)),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(
                icon == Icons.receipt_long_rounded
                    ? Icons.point_of_sale_rounded
                    : Icons.filter_alt_off_rounded,
                size: 18,
              ),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
