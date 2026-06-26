import 'cart_item.dart';

class Sale {
  final int? id;
  final List<CartItem> items;
  final double totalAmount;
  final DateTime createdAt;

  Sale({
    this.id,
    required this.items,
    required this.totalAmount,
    required this.createdAt,
  });
}
