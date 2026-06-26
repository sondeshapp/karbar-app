import 'product.dart';
import 'product_variant.dart';

class CartItem {
  final Product product;
  final ProductVariant variant;
  final int quantity;

  CartItem({
    required this.product,
    required this.variant,
    required this.quantity,
  });

  double get total => variant.price * quantity;

  CartItem copyWith({int? quantity}) =>
      CartItem(product: product, variant: variant, quantity: quantity ?? this.quantity);
}
