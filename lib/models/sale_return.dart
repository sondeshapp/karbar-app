class SaleReturn {
  final int? id;
  final int saleId;
  final double amount;
  final String reason;
  final String refundMethod;
  final DateTime createdAt;
  final List<SaleReturnLine> items;

  const SaleReturn({
    this.id,
    required this.saleId,
    required this.amount,
    required this.reason,
    required this.refundMethod,
    required this.createdAt,
    this.items = const [],
  });
}

class SaleReturnLine {
  final int saleItemId;
  final String productName;
  final String variantName;
  final double quantity;
  final double amount;

  const SaleReturnLine({
    required this.saleItemId,
    required this.productName,
    required this.variantName,
    required this.quantity,
    required this.amount,
  });
}
