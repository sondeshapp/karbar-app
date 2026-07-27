import 'cart_item.dart';

class Sale {
  final int? id;
  final List<CartItem> items;
  final double totalAmount;
  final DateTime createdAt;
  final String paymentType; // 'cash' | 'baki'
  final int? customerId;
  final String? customerName;

  const Sale({
    this.id,
    required this.items,
    required this.totalAmount,
    required this.createdAt,
    this.paymentType = 'cash',
    this.customerId,
    this.customerName,
  });

  bool get isBaki => paymentType == 'baki';
}
