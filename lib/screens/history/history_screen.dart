import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/sales_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/empty_state.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(salesProvider.notifier).loadSales();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sales = ref.watch(salesProvider);
    final s = ref.watch(stringsProvider);
    final dateFormat = DateFormat('dd MMM yyyy  HH:mm');
    final cf = NumberFormat.currency(locale: 'en_US', symbol: '\$');

    return Scaffold(
      appBar: AppBar(title: Text(s.salesHistory)),
      body: sales.isEmpty
          ? EmptyState(message: s.noSalesYet)
          : ListView.builder(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 8),
              itemCount: sales.length,
              itemBuilder: (context, index) {
                final sale = sales[index];
                final totalItems =
                    sale.items.fold(0, (sum, i) => sum + i.quantity);
                return ExpansionTile(
                  title: Text(dateFormat.format(sale.createdAt)),
                  subtitle: Text(s.itemsText(totalItems)),
                  trailing: Text(
                    cf.format(sale.totalAmount),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2563EB)),
                  ),
                  children: sale.items.map((item) {
                    final showVariant = item.variant.name.isNotEmpty &&
                        item.variant.name != 'Default';
                    return ListTile(
                      dense: true,
                      title: Text(item.product.name),
                      subtitle:
                          showVariant ? Text(item.variant.name) : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('×${item.quantity}  ',
                              style:
                                  const TextStyle(color: Colors.grey)),
                          Text(cf.format(item.total)),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
    );
  }
}
