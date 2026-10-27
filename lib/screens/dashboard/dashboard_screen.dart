import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/app_strings.dart';
import '../../models/dashboard_data.dart';
import '../../models/product.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/settings_provider.dart';
import '../../core/constants.dart';

const _cardColors = [
  Color(0xFF2563EB),
  Color(0xFF7C3AED),
  Color(0xFF059669),
  Color(0xFFF59E0B),
];

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardProvider);
    final s = ref.watch(stringsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: isDark
                  ? const Color(0xFF0F172A).withAlpha(210)
                  : Colors.white.withAlpha(210),
              child: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                title: Text(
                  s.navDashboard,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
                actions: [
                  IconButton(
                    icon: Icon(
                      Icons.refresh_rounded,
                      color: isDark ? Colors.white70 : const Color(0xFF64748B),
                    ),
                    onPressed: () => ref.invalidate(dashboardProvider),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading data\n$e')),
        data: (data) => _Body(data: data, s: s),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final DashboardData data;
  final AppStrings s;
  const _Body({required this.data, required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final cf = NumberFormat.currency(
      locale: settings.currencyLocale,
      symbol: settings.currencySymbol,
    );

    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          kPadding,
          8,
          kPadding,
          MediaQuery.of(context).padding.bottom + 16,
        ),
        children: [
          // ── Revenue cards ───────────────────────────────────────
          Row(
            children: [
              _StatCard(
                label: s.today,
                value: cf.format(data.revenueToday),
                sub: s.salesCountText(data.salesToday),
                color: _cardColors[0],
                icon: Icons.today_outlined,
              ),
              const SizedBox(width: 12),
              _StatCard(
                label: s.thisWeek,
                value: cf.format(data.revenueThisWeek),
                sub: s.salesCountText(data.salesThisWeek),
                color: _cardColors[1],
                icon: Icons.date_range_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatCard(
                label: s.thisMonth,
                value: cf.format(data.revenueThisMonth),
                sub: s.salesCountText(data.salesThisMonth),
                color: _cardColors[2],
                icon: Icons.calendar_month_outlined,
              ),
              const SizedBox(width: 12),
              _StatCard(
                label: s.avgSale,
                value: cf.format(data.avgSaleValue),
                sub: s.totalSalesText(data.salesAllTime),
                color: _cardColors[3],
                icon: Icons.trending_up_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatCard(
                label: 'Today Profit',
                value: cf.format(data.profitToday),
                sub: 'after cost of goods',
                color: const Color(0xFF059669),
                icon: Icons.trending_up_rounded,
              ),
              const SizedBox(width: 12),
              _StatCard(
                label: 'Margin',
                value: '${data.marginPercent.toStringAsFixed(1)}%',
                sub: 'of today\'s revenue',
                color: const Color(0xFF0EA5E9),
                icon: Icons.percent_rounded,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Inventory summary ───────────────────────────────────
          Row(
            children: [
              _MiniCard(
                label: s.productsLabel,
                value: '${data.totalProducts}',
                icon: Icons.inventory_2_outlined,
                color: const Color(0xFF0EA5E9),
              ),
              const SizedBox(width: 12),
              _MiniCard(
                label: s.variantsLabel,
                value: '${data.totalVariants}',
                icon: Icons.style_outlined,
                color: const Color(0xFFEC4899),
              ),
              const SizedBox(width: 12),
              _MiniCard(
                label: s.lowStockLabel,
                value: '${data.lowStockProducts.length}',
                icon: Icons.warning_amber_rounded,
                color: data.lowStockProducts.isEmpty
                    ? const Color(0xFF6B7280)
                    : const Color(0xFFEF4444),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── 7-day revenue chart ─────────────────────────────────
          _SectionCard(
            title: s.revenueChart,
            child: _RevenueChart(
              days: data.last7Days,
              noDataLabel: s.noData,
              currencySymbol: settings.currencySymbol,
            ),
          ),
          const SizedBox(height: 16),

          // ── Best sellers ────────────────────────────────────────
          if (data.topSellers.isNotEmpty) ...[
            _SectionCard(
              title: s.bestSellers,
              child: Column(
                children: data.topSellers.asMap().entries.map((e) {
                  return _BestSellerRow(
                    rank: e.key + 1,
                    item: e.value,
                    maxQty: data.topSellers.first.quantitySold,
                    s: s,
                    cf: cf,
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Low stock ───────────────────────────────────────────
          if (data.lowStockProducts.isNotEmpty)
            _SectionCard(
              title: s.lowStockTitle(data.lowStockProducts.length),
              titleColor: const Color(0xFFEF4444),
              child: Column(
                children: data.lowStockProducts
                    .map((p) => _LowStockRow(product: p, s: s))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Stat card ──────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color color;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withAlpha(204)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(77),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Glass shimmer overlay — subtle top-left highlight
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.centerRight,
                    colors: [Colors.white.withAlpha(30), Colors.transparent],
                    stops: const [0.0, 0.6],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Icon(icon, color: Colors.white54, size: 18),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mini card ──────────────────────────────────────────────────────────────

class _MiniCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MiniCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderCol = isDark ? const Color(0xFF334155) : kBorder;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderCol, width: 0.5),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section card ───────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Color? titleColor;

  const _SectionCard({
    required this.title,
    required this.child,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderCol = isDark ? const Color(0xFF334155) : kBorder;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderCol, width: 0.5),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(8),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: titleColor ?? (isDark ? Colors.white : kText),
              ),
            ),
          ),
          const SizedBox(height: 12),
          child,
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ── 7-day revenue bar chart ────────────────────────────────────────────────

class _RevenueChart extends StatelessWidget {
  final List<DailyRevenue> days;
  final String noDataLabel;
  final String currencySymbol;
  const _RevenueChart({
    required this.days,
    required this.noDataLabel,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (days.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(noDataLabel, style: const TextStyle(color: Colors.grey)),
      );
    }

    final maxAmt = days.map((d) => d.amount).reduce(max);
    final cf = NumberFormat.compactCurrency(
      symbol: currencySymbol,
      decimalDigits: 0,
    );
    final today = DateTime.now();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: SizedBox(
        height: 130,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: days.map((day) {
            final isToday =
                day.date.day == today.day &&
                day.date.month == today.month &&
                day.date.year == today.year;
            final ratio = maxAmt > 0
                ? (day.amount / maxAmt).clamp(0.0, 1.0)
                : 0.0;
            final barH = (80 * ratio).clamp(2.0, 80.0);
            final barColor = isToday
                ? kPrimary
                : (isDark ? const Color(0xFF60A5FA) : const Color(0xFF93C5FD));

            return Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  day.amount > 0 ? cf.format(day.amount) : '',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: isToday ? kPrimary : Colors.grey,
                  ),
                ),
                const SizedBox(height: 3),
                if (day.salesCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: barColor.withAlpha(isDark ? 55 : 30),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '×${day.salesCount}',
                      style: TextStyle(
                        fontSize: 8,
                        color: isToday
                            ? kPrimary
                            : (isDark ? Colors.white54 : Colors.grey),
                      ),
                    ),
                  ),
                const SizedBox(height: 2),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOut,
                  width: 28,
                  height: barH,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('E').format(day.date),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                    color: isToday ? kPrimary : Colors.grey,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Best seller row ────────────────────────────────────────────────────────

class _BestSellerRow extends StatelessWidget {
  final int rank;
  final BestSellerItem item;
  final double maxQty;
  final AppStrings s;
  final NumberFormat cf;

  const _BestSellerRow({
    required this.rank,
    required this.item,
    required this.maxQty,
    required this.s,
    required this.cf,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ratio = maxQty > 0 ? item.quantitySold / maxQty : 0.0;
    final showVariant =
        item.variantName.isNotEmpty && item.variantName != 'Default';

    final rankColor = rank == 1
        ? const Color(0xFFF59E0B)
        : rank == 2
        ? const Color(0xFF6B7280)
        : rank == 3
        ? const Color(0xFFCD7F32)
        : kPrimary.withAlpha(160);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: rankColor,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$rank',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  showVariant
                      ? '${item.productName} · ${item.variantName}'
                      : item.productName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    s.soldText(item.quantitySold),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: kPrimary,
                    ),
                  ),
                  Text(
                    cf.format(item.revenue),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 5,
              backgroundColor: isDark
                  ? const Color(0xFF334155)
                  : const Color(0xFFE5E7EB),
              valueColor: AlwaysStoppedAnimation<Color>(rankColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Low stock row ──────────────────────────────────────────────────────────

class _LowStockRow extends StatelessWidget {
  final Product product;
  final AppStrings s;
  const _LowStockRow({required this.product, required this.s});

  @override
  Widget build(BuildContext context) {
    final isOut = product.totalStock == 0;
    final color = isOut ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (product.category.isNotEmpty)
                  Text(
                    product.category,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              border: Border.all(color: color.withAlpha(80)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isOut
                  ? s.outOfStock
                  : s.unitLeftText(product.totalStock, product.unit),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
