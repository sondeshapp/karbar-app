import 'dart:convert';

class RemoteSyncEvent {
  final int cursor;
  final String eventId;
  final String eventType;
  final int entityId;
  final DateTime createdAt;
  final Map<String, dynamic> payload;

  const RemoteSyncEvent({
    required this.cursor,
    required this.eventId,
    required this.eventType,
    required this.entityId,
    required this.createdAt,
    required this.payload,
  });

  factory RemoteSyncEvent.fromJson(Map<String, dynamic> json) {
    final cursor = json['cursor'];
    final entityId = json['entityId'];
    final eventId = json['eventId'];
    final eventType = json['eventType'];
    final createdAt = json['createdAt'];
    final payload = json['payload'];
    if (cursor is! int ||
        cursor < 1 ||
        entityId is! int ||
        entityId < 1 ||
        eventId is! String ||
        eventId.isEmpty ||
        eventType is! String ||
        eventType.isEmpty ||
        createdAt is! String ||
        DateTime.tryParse(createdAt) == null ||
        payload is! Map<String, dynamic>) {
      throw const FormatException('The server returned an invalid sync event.');
    }
    return RemoteSyncEvent(
      cursor: cursor,
      eventId: eventId,
      eventType: eventType,
      entityId: entityId,
      createdAt: DateTime.parse(createdAt),
      payload: payload,
    );
  }

  String toJsonString() => jsonEncode({
    'cursor': cursor,
    'eventId': eventId,
    'eventType': eventType,
    'entityId': entityId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'payload': payload,
  });
}

class RemoteSyncPage {
  final int cursor;
  final List<RemoteSyncEvent> events;

  const RemoteSyncPage({required this.cursor, required this.events});

  factory RemoteSyncPage.fromJson(Map<String, dynamic> json) {
    final cursor = json['cursor'];
    final events = json['events'];
    if (cursor is! int || cursor < 0 || events is! List) {
      throw const FormatException('The server returned an invalid event page.');
    }
    return RemoteSyncPage(
      cursor: cursor,
      events: events
          .map((event) {
            if (event is! Map<String, dynamic>) {
              throw const FormatException(
                'The server returned an invalid sync event.',
              );
            }
            return RemoteSyncEvent.fromJson(event);
          })
          .toList(growable: false),
    );
  }
}

class RemoteSyncApplyResult {
  final int applied;
  final int pending;
  final int errors;

  const RemoteSyncApplyResult({
    required this.applied,
    required this.pending,
    required this.errors,
  });
}
