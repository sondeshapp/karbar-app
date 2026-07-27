class Customer {
  final int? id;
  final String name;
  final String phone;
  final DateTime createdAt;

  const Customer({
    this.id,
    required this.name,
    this.phone = '',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'phone': phone,
        'created_at': createdAt.toIso8601String(),
      };

  factory Customer.fromMap(Map<String, dynamic> map) => Customer(
        id: map['id'] as int?,
        name: map['name'] as String,
        phone: map['phone'] as String? ?? '',
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
