import 'dart:convert';

class CloudCatalogMutation {
  final String remoteShopId;
  final String mutationId;
  final String entityType;
  final String entityId;
  final int baseRevision;
  final Map<String, Object?> payload;
  final bool deleted;

  const CloudCatalogMutation({
    required this.remoteShopId,
    required this.mutationId,
    required this.entityType,
    required this.entityId,
    required this.baseRevision,
    required this.payload,
    required this.deleted,
  });

  factory CloudCatalogMutation.fromMap(Map<String, dynamic> map) =>
      CloudCatalogMutation(
        remoteShopId: map['remote_shop_id'] as String,
        mutationId: map['mutation_id'] as String,
        entityType: map['entity_type'] as String,
        entityId: map['entity_id'] as String,
        baseRevision: map['base_revision'] as int,
        payload: (jsonDecode(map['payload_json'] as String) as Map)
            .cast<String, Object?>(),
        deleted: map['deleted'] == 1,
      );
}

class CloudCatalogApplyResult {
  final int applied;
  final int conflicts;

  const CloudCatalogApplyResult({
    required this.applied,
    required this.conflicts,
  });
}

class CloudCatalogConflict {
  final int cursor;
  final String entityType;
  final String entityId;
  final int baseRevision;
  final int revision;
  final Map<String, dynamic> payload;
  final Map<String, dynamic>? localPayload;
  final bool deleted;
  final String reason;

  const CloudCatalogConflict({
    required this.cursor,
    required this.entityType,
    required this.entityId,
    required this.baseRevision,
    required this.revision,
    required this.payload,
    this.localPayload,
    required this.deleted,
    required this.reason,
  });

  factory CloudCatalogConflict.fromMap(Map<String, dynamic> row) =>
      CloudCatalogConflict(
        cursor: row['cursor'] as int,
        entityType: row['entity_type'] as String,
        entityId: row['entity_id'] as String,
        baseRevision: row['base_revision'] as int,
        revision: row['revision'] as int,
        payload: (jsonDecode(row['payload_json'] as String) as Map)
            .cast<String, dynamic>(),
        localPayload: row['local_payload_json'] is String
            ? (jsonDecode(row['local_payload_json'] as String) as Map)
                  .cast<String, dynamic>()
            : null,
        deleted: row['deleted'] == 1,
        reason: row['conflict_reason'] as String,
      );
}

class CatalogMutationResult {
  final bool duplicate;
  final int cursor;
  final int revision;

  const CatalogMutationResult({
    required this.duplicate,
    required this.cursor,
    required this.revision,
  });

  factory CatalogMutationResult.fromJson(Map<String, dynamic> json) {
    final accepted = json['accepted'];
    final duplicate = json['duplicate'];
    final cursor = json['cursor'];
    final revision = json['revision'];
    if (accepted != true ||
        duplicate is! bool ||
        cursor is! int ||
        revision is! int ||
        cursor < 1 ||
        revision < 1) {
      throw const FormatException(
        'The server returned an invalid catalog result.',
      );
    }
    return CatalogMutationResult(
      duplicate: duplicate,
      cursor: cursor,
      revision: revision,
    );
  }
}

class CloudCatalogChange {
  final int cursor;
  final String entityType;
  final String entityId;
  final String mutationId;
  final int baseRevision;
  final int revision;
  final Map<String, dynamic> payload;
  final bool deleted;
  final DateTime changedAt;

  const CloudCatalogChange({
    required this.cursor,
    required this.entityType,
    required this.entityId,
    required this.mutationId,
    required this.baseRevision,
    required this.revision,
    required this.payload,
    required this.deleted,
    required this.changedAt,
  });

  factory CloudCatalogChange.fromJson(Map<String, dynamic> json) {
    final cursor = json['cursor'];
    final entityType = json['entityType'];
    final entityId = json['entityId'];
    final mutationId = json['mutationId'];
    final baseRevision = json['baseRevision'];
    final revision = json['revision'];
    final payload = json['payload'];
    final deleted = json['deleted'];
    final changedAt = json['changedAt'];
    if (cursor is! int ||
        cursor < 1 ||
        !{
          'product',
          'customer',
          'settings',
          'supplier',
          'staff',
        }.contains(entityType) ||
        entityId is! String ||
        entityId.isEmpty ||
        mutationId is! String ||
        mutationId.isEmpty ||
        baseRevision is! int ||
        baseRevision < 0 ||
        revision is! int ||
        revision != baseRevision + 1 ||
        payload is! Map<String, dynamic> ||
        deleted is! bool ||
        changedAt is! String ||
        DateTime.tryParse(changedAt) == null) {
      throw const FormatException(
        'The server returned an invalid catalog change.',
      );
    }
    return CloudCatalogChange(
      cursor: cursor,
      entityType: entityType as String,
      entityId: entityId,
      mutationId: mutationId,
      baseRevision: baseRevision,
      revision: revision,
      payload: payload,
      deleted: deleted,
      changedAt: DateTime.parse(changedAt),
    );
  }
}

class CloudCatalogPage {
  final int cursor;
  final List<CloudCatalogChange> changes;

  const CloudCatalogPage({required this.cursor, required this.changes});

  factory CloudCatalogPage.fromJson(Map<String, dynamic> json) {
    final cursor = json['cursor'];
    final changes = json['changes'];
    if (cursor is! int || cursor < 0 || changes is! List) {
      throw const FormatException(
        'The server returned an invalid catalog page.',
      );
    }
    final parsed = changes
        .map((change) {
          if (change is! Map<String, dynamic>) {
            throw const FormatException(
              'The server returned an invalid catalog change.',
            );
          }
          return CloudCatalogChange.fromJson(change);
        })
        .toList(growable: false);
    if (parsed.any((change) => change.cursor > cursor)) {
      throw const FormatException(
        'The catalog cursor precedes a returned change.',
      );
    }
    return CloudCatalogPage(cursor: cursor, changes: parsed);
  }
}

class CatalogRevisionConflict {
  final int currentRevision;
  final Map<String, dynamic>? currentPayload;
  final bool deleted;

  const CatalogRevisionConflict({
    required this.currentRevision,
    required this.currentPayload,
    required this.deleted,
  });

  factory CatalogRevisionConflict.fromJson(Map<String, dynamic> json) {
    final revision = json['currentRevision'];
    final payload = json['currentPayload'];
    final deleted = json['deleted'];
    if (revision is! int ||
        revision < 0 ||
        (payload != null && payload is! Map<String, dynamic>) ||
        deleted is! bool) {
      throw const FormatException(
        'The server returned invalid conflict details.',
      );
    }
    return CatalogRevisionConflict(
      currentRevision: revision,
      currentPayload: payload as Map<String, dynamic>?,
      deleted: deleted,
    );
  }
}

Map<String, dynamic> decodeCatalogJson(String contents) {
  final decoded = jsonDecode(contents);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException(
      'The server returned an invalid catalog response.',
    );
  }
  return decoded;
}
