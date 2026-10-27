class SyncOutboxEvent {
  final String idempotencyKey;
  final String eventType;
  final int entityId;
  final String payloadJson;
  final DateTime createdAt;
  final int attempts;
  final String lastError;

  const SyncOutboxEvent({
    required this.idempotencyKey,
    required this.eventType,
    required this.entityId,
    required this.payloadJson,
    required this.createdAt,
    required this.attempts,
    required this.lastError,
  });

  factory SyncOutboxEvent.fromMap(Map<String, Object?> row) => SyncOutboxEvent(
    idempotencyKey: row['idempotency_key'] as String,
    eventType: row['event_type'] as String,
    entityId: row['entity_id'] as int,
    payloadJson: row['payload_json'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
    attempts: row['attempts'] as int,
    lastError: row['last_error'] as String,
  );
}
