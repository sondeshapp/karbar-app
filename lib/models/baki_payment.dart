class BakiPayment {
  final int? id;
  final int customerId;
  final double amount;
  final String note;
  final DateTime paidAt;

  const BakiPayment({
    this.id,
    required this.customerId,
    required this.amount,
    this.note = '',
    required this.paidAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'customer_id': customerId,
        'amount': amount,
        'note': note,
        'paid_at': paidAt.toIso8601String(),
      };

  factory BakiPayment.fromMap(Map<String, dynamic> map) => BakiPayment(
        id: map['id'] as int?,
        customerId: map['customer_id'] as int,
        amount: (map['amount'] as num).toDouble(),
        note: map['note'] as String? ?? '',
        paidAt: DateTime.parse(map['paid_at'] as String),
      );
}
