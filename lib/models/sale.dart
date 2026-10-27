import 'cart_item.dart';
import 'sale_payment.dart';

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
  final double taxAmount;
  final List<SalePayment> payments;
  final double returnedBakiAmount;
  final double returnedAmount;
  final int? staffId;

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
    this.taxAmount = 0,
    this.payments = const [],
    this.returnedBakiAmount = 0,
    this.returnedAmount = 0,
    this.staffId,
  });

  bool get isBaki => paymentType == 'baki';

  double get bakiAmount =>
      ((payments.isNotEmpty
                  ? payments
                        .where((payment) => payment.method == 'baki')
                        .fold(0.0, (total, payment) => total + payment.amount)
                  : (isBaki ? totalAmount : 0.0)) -
              returnedBakiAmount)
          .clamp(0.0, double.infinity);
}
