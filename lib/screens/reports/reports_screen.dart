import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_strings.dart';
import '../../models/sales_report.dart';
import '../../core/quantity_format.dart';
import '../../providers/reports_provider.dart';
import '../../providers/settings_provider.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  late ReportRange _range;
  String _preset = 'month';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = ReportRange(from: DateTime(now.year, now.month, 1), through: now);
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void _setPreset(String preset) {
    final today = _today;
    setState(() {
      _preset = preset;
      if (preset == 'today') {
        _range = ReportRange(from: today, through: today);
      } else if (preset == 'week') {
        _range = ReportRange(
          from: today.subtract(const Duration(days: 6)),
          through: today,
        );
      } else {
        _range = ReportRange(
          from: DateTime(today.year, today.month, 1),
          through: today,
        );
      }
    });
  }

  Future<void> _chooseDates() async {
    final today = _today;
    final start = await showDatePicker(
      context: context,
      initialDate: _range.start.isAfter(today) ? today : _range.start,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: 'Select start date',
    );
    if (start == null || !mounted) return;
    final end = await showDatePicker(
      context: context,
      initialDate:
          _range.through.isBefore(start) || _range.through.isAfter(today)
          ? start
          : _range.through,
      firstDate: start,
      lastDate: today,
      helpText: 'Select end date',
    );
    if (end == null || !mounted) return;
    setState(() {
      _preset = 'custom';
      _range = ReportRange(from: start, through: end);
    });
  }

  String _csvCell(Object? value) {
    final text = value?.toString() ?? '';
    return '"${text.replaceAll('"', '""')}"';
  }

  Future<void> _exportCsv(SalesReportData data, AppStrings s) async {
    final rows = <List<Object?>>[
      [
        'Period',
        DateFormat.yMMMd().format(_range.start),
        DateFormat.yMMMd().format(_range.through),
      ],
      ['Metric', 'Value'],
      [s.grossSales, data.grossSales.toStringAsFixed(2)],
      [s.discountTotal, data.discounts.toStringAsFixed(2)],
      [s.netSales, data.netSales.toStringAsFixed(2)],
      [s.returnsMetric, data.returns.toStringAsFixed(2)],
      [s.purchaseCostsMetric, data.purchaseCosts.toStringAsFixed(2)],
      [s.taxCollected, data.taxCollected.toStringAsFixed(2)],
      ['Tax note', s.taxHistoryNote],
      [s.totalReceivable, data.totalReceivable.toStringAsFixed(2)],
      [s.transactions, data.saleCount],
      [s.averageSale, data.averageSale.toStringAsFixed(2)],
      [s.estimatedProfit, data.estimatedProfit.toStringAsFixed(2)],
      [s.bakiIssued, data.bakiIssued.toStringAsFixed(2)],
      [s.bakiCollected, data.bakiCollected.toStringAsFixed(2)],
      ['', ''],
      [s.paymentBreakdown, 'Amount'],
      ...data.paymentTotals.entries.map(
        (entry) => [entry.key, entry.value.toStringAsFixed(2)],
      ),
      ['', ''],
      [s.supplierPurchases, 'Amount'],
      ...data.supplierPurchaseTotals.entries.map(
        (entry) => [entry.key, entry.value.toStringAsFixed(2)],
      ),
      ['', ''],
      [s.topProductsReport, 'Quantity', s.netSales],
      ...data.topProducts.map(
        (item) => [item.name, item.quantity, item.netSales.toStringAsFixed(2)],
      ),
      ['', ''],
      [s.lowStockProducts, 'Stock'],
      ...data.lowStockProducts.map((item) => [item.name, item.totalStock]),
    ];
    final contents =
        '\uFEFF${rows.map((row) => row.map(_csvCell).join(',')).join('\r\n')}';
    final filename =
        'karbar_report_${DateFormat('yyyyMMdd').format(_range.start)}_${DateFormat('yyyyMMdd').format(_range.through)}.csv';
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await SharePlus.instance.share(
          ShareParams(
            title: s.reportsLabel,
            files: [
              XFile.fromData(
                Uint8List.fromList(utf8.encode(contents)),
                name: filename,
                mimeType: 'text/csv',
              ),
            ],
            fileNameOverrides: [filename],
          ),
        );
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(s.csvShareReady)));
        }
      } else {
        final location = await getSaveLocation(
          suggestedName: filename,
          acceptedTypeGroups: const [
            XTypeGroup(
              label: 'CSV',
              extensions: ['csv'],
              mimeTypes: ['text/csv'],
              uniformTypeIdentifiers: ['public.comma-separated-values-text'],
            ),
          ],
        );
        if (location == null) return;
        await XFile.fromData(
          Uint8List.fromList(utf8.encode(contents)),
          name: filename,
          mimeType: 'text/csv',
        ).saveTo(location.path);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(s.csvSaved)));
        }
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not export this report.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final report = ref.watch(salesReportProvider(_range));
    final settings = ref.watch(settingsProvider);
    final currency = NumberFormat.currency(
      locale: settings.currencyLocale,
      symbol: settings.currencySymbol,
    );
    final dateFormat = DateFormat.yMMMd();

    return Scaffold(
      appBar: AppBar(
        title: Text(s.reportsLabel),
        actions: [
          IconButton(
            tooltip: s.exportCsv,
            onPressed: report.valueOrNull == null
                ? null
                : () => _exportCsv(report.value!, s),
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(salesReportProvider(_range)),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                _rangeChip(s.todayRange, 'today'),
                const SizedBox(width: 8),
                _rangeChip(s.lastSevenDays, 'week'),
                const SizedBox(width: 8),
                _rangeChip(s.thisMonthRange, 'month'),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(
                    _preset == 'custom'
                        ? s.reportPeriod(
                            dateFormat.format(_range.start),
                            dateFormat.format(_range.through),
                          )
                        : s.customRange,
                  ),
                  selected: _preset == 'custom',
                  onSelected: (_) => _chooseDates(),
                ),
              ],
            ),
          ),
          Expanded(
            child: report.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Error: $error')),
              data: (data) => RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(salesReportProvider(_range));
                  await ref.read(salesReportProvider(_range).future);
                },
                child: _reportBody(context, data, s, currency),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rangeChip(String label, String preset) => ChoiceChip(
    label: Text(label),
    selected: _preset == preset,
    onSelected: (_) => _setPreset(preset),
  );

  Widget _reportBody(
    BuildContext context,
    SalesReportData data,
    AppStrings s,
    NumberFormat currency,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateFormat = DateFormat.yMMMd();
    final reportDate = s.reportPeriod(
      dateFormat.format(_range.start),
      dateFormat.format(_range.through),
    );
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Text(
            reportDate,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _metric(
              context,
              s.grossSales,
              currency.format(data.grossSales),
              Icons.payments_outlined,
              const Color(0xFF2563EB),
            ),
            _metric(
              context,
              s.discountTotal,
              currency.format(data.discounts),
              Icons.discount_outlined,
              const Color(0xFF7C3AED),
            ),
            _metric(
              context,
              s.netSales,
              currency.format(data.netSales),
              Icons.trending_up_rounded,
              const Color(0xFF059669),
            ),
            _metric(
              context,
              s.returnsMetric,
              currency.format(data.returns),
              Icons.assignment_return_outlined,
              const Color(0xFFDC2626),
            ),
            _metric(
              context,
              s.purchaseCostsMetric,
              currency.format(data.purchaseCosts),
              Icons.inventory_2_outlined,
              const Color(0xFFB45309),
            ),
            _metric(
              context,
              s.taxCollected,
              currency.format(data.taxCollected),
              Icons.receipt_long_outlined,
              const Color(0xFFF59E0B),
            ),
            _metric(
              context,
              s.totalReceivable,
              currency.format(data.totalReceivable),
              Icons.account_balance_wallet_outlined,
              const Color(0xFF0EA5E9),
            ),
            _metric(
              context,
              s.transactions,
              '${data.saleCount}',
              Icons.shopping_bag_outlined,
              const Color(0xFFEC4899),
            ),
            _metric(
              context,
              s.averageSale,
              currency.format(data.averageSale),
              Icons.calculate_outlined,
              const Color(0xFF64748B),
            ),
            _metric(
              context,
              s.estimatedProfit,
              currency.format(data.estimatedProfit),
              Icons.show_chart_rounded,
              const Color(0xFF10B981),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _infoNote(context, s.taxHistoryNote, isDark),
        if (data.linesWithoutCost > 0) ...[
          const SizedBox(height: 8),
          _infoNote(context, s.missingCostNote(data.linesWithoutCost), isDark),
        ],
        const SizedBox(height: 16),
        _sectionCard(
          context,
          s.paymentBreakdown,
          data.paymentTotals.isEmpty
              ? Text(s.noReportSales)
              : Column(
                  children: data.paymentTotals.entries
                      .map(
                        (entry) => _valueRow(
                          context,
                          entry.key == 'baki' ? 'Baki' : entry.key,
                          currency.format(entry.value),
                        ),
                      )
                      .toList(),
                ),
        ),
        if (data.supplierPurchaseTotals.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionCard(
            context,
            s.supplierPurchases,
            Column(
              children: data.supplierPurchaseTotals.entries
                  .map(
                    (entry) => _valueRow(
                      context,
                      entry.key,
                      currency.format(entry.value),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _sectionCard(
          context,
          s.bakiIssued,
          Column(
            children: [
              _valueRow(
                context,
                s.bakiIssued,
                currency.format(data.bakiIssued),
              ),
              _valueRow(
                context,
                s.bakiCollected,
                currency.format(data.bakiCollected),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          context,
          s.topProductsReport,
          data.topProducts.isEmpty
              ? Text(s.noReportSales)
              : Column(
                  children: data.topProducts
                      .take(5)
                      .map(
                        (item) => _valueRow(
                          context,
                          '${item.name} · ×${formatQuantity(item.quantity, 3)}',
                          currency.format(item.netSales),
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          context,
          s.lowStockProducts,
          data.lowStockProducts.isEmpty
              ? Text(s.noProductsYet)
              : Column(
                  children: data.lowStockProducts
                      .take(10)
                      .map(
                        (product) => _valueRow(
                          context,
                          product.name,
                          '${formatQuantity(product.totalStock, product.quantityPrecision)} ${product.unit}',
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }

  Widget _metric(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    final width = (MediaQuery.sizeOf(context).width - 42) / 2;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(BuildContext context, String title, Widget content) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          content,
        ],
      ),
    );
  }

  Widget _valueRow(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 12),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );

  Widget _infoNote(BuildContext context, String text, bool isDark) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF332B1E) : const Color(0xFFFFFBEB),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}
