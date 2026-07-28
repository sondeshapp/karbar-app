import 'cart_item.dart';

class Sale {
  final int? id;
  final List<CartItem> items;
  final double totalAmount;
  final DateTime createdAt;
  final String paymentType; // 'cash' | 'baki'
  final int? customerId;
  final String? customerName;
  final double discountAmount;
  final String discountType; // 'flat' | 'percent'

  const Sale({
    this.id,
    required this.items,
    required this.totalAmount,
    required this.createdAt,
    this.paymentType = 'cash',
    this.customerId,
    this.customerName,
    this.discountAmount = 0,
    this.discountType = 'flat',
  });

  bool get isBaki => paymentType == 'baki';
}
