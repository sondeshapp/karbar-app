import 'product.dart';
import 'product_variant.dart';

class CartItem {
  final Product product;
  final ProductVariant variant;
  final int quantity;
  final double discountAmount; // flat per-item discount

  CartItem({
    required this.product,
    required this.variant,
    required this.quantity,
    this.discountAmount = 0,
  });

  double get unitPrice => (variant.price - discountAmount).clamp(0, double.infinity);
  double get total => unitPrice * quantity;

  CartItem copyWith({int? quantity, double? discountAmount}) => CartItem(
    product: product,
    variant: variant,
    quantity: quantity ?? this.quantity,
    discountAmount: discountAmount ?? this.discountAmount,
  );
}
