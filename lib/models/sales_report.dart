import 'product.dart';

class ReportRange {
  final DateTime from;
  final DateTime through;

  const ReportRange({required this.from, required this.through});

  DateTime get start => DateTime(from.year, from.month, from.day);
  DateTime get endExclusive =>
      DateTime(through.year, through.month, through.day + 1);

  @override
  bool operator ==(Object other) =>
      other is ReportRange &&
      start == other.start &&
      through.year == other.through.year &&
      through.month == other.through.month &&
      through.day == other.through.day;

  @override
  int get hashCode =>
      Object.hash(start, through.year, through.month, through.day);
}

class ReportProductSummary {
  final String name;
  final double quantity;
  final double netSales;

  const ReportProductSummary({
    required this.name,
    required this.quantity,
    required this.netSales,
  });
}

class SalesReportData {
  final double grossSales;
  final double discounts;
  final double netSales;
  final double taxCollected;
  final double totalReceivable;
  final double returns;
  final double purchaseCosts;
  final Map<String, double> supplierPurchaseTotals;
  final int saleCount;
  final double averageSale;
  final double estimatedProfit;
  final int linesWithoutCost;
  final double bakiIssued;
  final double bakiCollected;
  final Map<String, double> paymentTotals;
  final List<ReportProductSummary> topProducts;
  final List<Product> lowStockProducts;

  const SalesReportData({
    required this.grossSales,
    required this.discounts,
    required this.netSales,
    required this.taxCollected,
    required this.totalReceivable,
    required this.returns,
    required this.purchaseCosts,
    required this.supplierPurchaseTotals,
    required this.saleCount,
    required this.averageSale,
    required this.estimatedProfit,
    required this.linesWithoutCost,
    required this.bakiIssued,
    required this.bakiCollected,
    required this.paymentTotals,
    required this.topProducts,
    required this.lowStockProducts,
  });
}
