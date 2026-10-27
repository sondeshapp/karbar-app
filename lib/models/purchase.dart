class Purchase {
  final int? id;
  final int? supplierId;
  final String supplierName;
  final double totalAmount;
  final DateTime createdAt;
  final String note;
  final List<PurchaseLine> items;

  const Purchase({
    this.id,
    this.supplierId,
    required this.supplierName,
    required this.totalAmount,
    required this.createdAt,
    this.note = '',
    this.items = const [],
  });
}

class PurchaseLine {
  final int variantId;
  final String productName;
  final String variantName;
  final double quantity;
  final double costPrice;

  const PurchaseLine({
    required this.variantId,
    required this.productName,
    required this.variantName,
    required this.quantity,
    required this.costPrice,
  });

  double get total => quantity * costPrice;
}
