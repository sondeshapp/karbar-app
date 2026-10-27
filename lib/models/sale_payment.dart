class SalePayment {
  final int? id;
  final String method;
  final double amount;
  final String note;

  const SalePayment({
    this.id,
    required this.method,
    required this.amount,
    this.note = '',
  });

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'method': method,
    'amount': amount,
    'note': note,
  };

  factory SalePayment.fromMap(Map<String, Object?> map) => SalePayment(
    id: map['id'] as int?,
    method: map['method'] as String,
    amount: (map['amount'] as num).toDouble(),
    note: map['note'] as String? ?? '',
  );
}
