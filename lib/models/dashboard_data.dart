import 'product.dart';

class BestSellerItem {
  final String productName;
  final String variantName;
  final double quantitySold;
  final double revenue;

  const BestSellerItem({
    required this.productName,
    required this.variantName,
    required this.quantitySold,
    required this.revenue,
  });
}

class DailyRevenue {
  final DateTime date;
  final double amount;
  final int salesCount;

  const DailyRevenue({
    required this.date,
    required this.amount,
    required this.salesCount,
  });
}

class DashboardData {
  final double revenueToday;
  final int salesToday;
  final double revenueThisWeek;
  final int salesThisWeek;
  final double revenueThisMonth;
  final int salesThisMonth;
  final double revenueAllTime;
  final int salesAllTime;
  final double avgSaleValue;
  final double profitToday;
  final double marginPercent;
  final int totalProducts;
  final int totalVariants;
  final List<BestSellerItem> topSellers;
  final List<Product> lowStockProducts;
  final List<DailyRevenue> last7Days;

  const DashboardData({
    required this.revenueToday,
    required this.salesToday,
    required this.revenueThisWeek,
    required this.salesThisWeek,
    required this.revenueThisMonth,
    required this.salesThisMonth,
    required this.revenueAllTime,
    required this.salesAllTime,
    required this.avgSaleValue,
    required this.profitToday,
    required this.marginPercent,
    required this.totalProducts,
    required this.totalVariants,
    required this.topSellers,
    required this.lowStockProducts,
    required this.last7Days,
  });
}
