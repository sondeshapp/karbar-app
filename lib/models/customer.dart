class Customer {
  final int? id;
  final String? syncId;
  final String name;
  final String phone;
  final DateTime createdAt;

  const Customer({
    this.id,
    this.syncId,
    required this.name,
    this.phone = '',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'sync_id': syncId,
    'name': name,
    'phone': phone,
    'created_at': createdAt.toIso8601String(),
  };

  factory Customer.fromMap(Map<String, dynamic> map) => Customer(
    id: map['id'] as int?,
    syncId: map['sync_id'] as String?,
    name: map['name'] as String,
    phone: map['phone'] as String? ?? '',
    createdAt: DateTime.parse(map['created_at'] as String),
  );
}
