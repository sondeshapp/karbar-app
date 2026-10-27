class StaffUser {
  final int? id;
  final String? syncId;
  final String name;
  final String role;
  final String pinSalt;
  final String pinHash;

  /// 4 or 6 for PINs created by current versions; 0 marks a pre-migration PIN.
  final int pinLength;
  final bool active;
  final DateTime createdAt;

  const StaffUser({
    this.id,
    this.syncId,
    required this.name,
    required this.role,
    required this.pinSalt,
    required this.pinHash,
    this.pinLength = 0,
    required this.active,
    required this.createdAt,
  });

  bool get isOwner => role == 'owner';

  factory StaffUser.fromMap(Map<String, Object?> map) => StaffUser(
    id: map['id'] as int?,
    syncId: map['sync_id'] as String?,
    name: map['name'] as String,
    role: map['role'] as String,
    pinSalt: map['pin_salt'] as String,
    pinHash: map['pin_hash'] as String,
    pinLength: map['pin_length'] as int? ?? 0,
    active: (map['active'] as int? ?? 1) == 1,
    createdAt: DateTime.parse(map['created_at'] as String),
  );
}
