import 'product.dart';
import 'product_variant.dart';

class CartItem {
  final Product product;
  final ProductVariant variant;
  final double quantity;
  final double discountAmount; // flat per-item discount
  final int? saleItemId;
  final double returnedQuantity;

  CartItem({
    required this.product,
    required this.variant,
    required this.quantity,
    this.discountAmount = 0,
    this.saleItemId,
    this.returnedQuantity = 0,
  });

  double get unitPrice =>
      (variant.price - discountAmount).clamp(0, double.infinity);
  double get total => unitPrice * quantity;

  CartItem copyWith({double? quantity, double? discountAmount}) => CartItem(
    product: product,
    variant: variant,
    quantity: quantity ?? this.quantity,
    discountAmount: discountAmount ?? this.discountAmount,
    saleItemId: saleItemId,
    returnedQuantity: returnedQuantity,
  );
}
