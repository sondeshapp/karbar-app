class StaffActivity {
  final int id;
  final int? staffId;
  final String staffName;
  final String action;
  final String entityType;
  final int? entityId;
  final String summary;
  final DateTime createdAt;

  const StaffActivity({
    required this.id,
    required this.staffId,
    required this.staffName,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.summary,
    required this.createdAt,
  });

  factory StaffActivity.fromMap(Map<String, Object?> map) => StaffActivity(
    id: map['id'] as int,
    staffId: map['staff_id'] as int?,
    staffName: map['staff_name'] as String,
    action: map['action'] as String,
    entityType: map['entity_type'] as String,
    entityId: map['entity_id'] as int?,
    summary: map['summary'] as String,
    createdAt: DateTime.parse(map['created_at'] as String),
  );
}
