class Supplier {
  final int? id;
  final String? syncId;
  final String name;
  final String phone;
  final String address;
  final String notes;

  const Supplier({
    this.id,
    this.syncId,
    required this.name,
    this.phone = '',
    this.address = '',
    this.notes = '',
  });

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'sync_id': syncId,
    'name': name,
    'phone': phone,
    'address': address,
    'notes': notes,
  };

  factory Supplier.fromMap(Map<String, Object?> map) => Supplier(
    id: map['id'] as int?,
    syncId: map['sync_id'] as String?,
    name: map['name'] as String,
    phone: map['phone'] as String? ?? '',
    address: map['address'] as String? ?? '',
    notes: map['notes'] as String? ?? '',
  );
}
