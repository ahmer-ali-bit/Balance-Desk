import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue;

/// One entry of the append-only replication journal.
///
/// Ops are immutable once written to Firestore. Each one carries the full row
/// payload plus last-writer-wins metadata ([updatedAt] + [originDeviceId]) so
/// any device can converge to the same state without a central coordinator.
class SyncOp {
  const SyncOp({
    required this.opId,
    required this.originDeviceId,
    required this.table,
    required this.rowId,
    required this.action,
    required this.updatedAt,
    required this.payload,
  });

  static const String actionUpsert = 'upsert';
  static const String actionDelete = 'delete';

  final String opId;
  final String originDeviceId;
  final String table;
  final String rowId;

  /// [actionUpsert] or [actionDelete].
  final String action;

  /// Milliseconds since epoch, from the device that produced the op.
  final int updatedAt;

  /// Full row snapshot; empty for deletes.
  final Map<String, Object?> payload;

  bool get isDelete => action == actionDelete;

  /// Builds a sortable, globally unique document id.
  ///
  /// Layout: `<12 hex millis>-<device id>-<6 digit counter>` — lexicographic
  /// order equals chronological order, which is what the Firestore query
  /// relies on when replaying the journal.
  static String newOpId({
    required String deviceId,
    required int counter,
    DateTime? at,
  }) {
    final int millis = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final String time = millis.toRadixString(16).padLeft(12, '0');
    final String seq = (counter % 1000000).toString().padLeft(6, '0');
    return '$time-$deviceId-$seq';
  }

  Map<String, Object?> toDocument() => <String, Object?>{
        'opId': opId,
        'originDeviceId': originDeviceId,
        'table': table,
        'rowId': rowId,
        'action': action,
        'updatedAt': updatedAt,
        'payload': payload,
        // Must equal request.time — the Firestore rules pin it that way.
        'createdAt': FieldValue.serverTimestamp(),
      };

  factory SyncOp.fromDocument(Map<String, Object?> data) {
    return SyncOp(
      opId: (data['opId'] ?? '') as String,
      originDeviceId: (data['originDeviceId'] ?? '') as String,
      table: (data['table'] ?? '') as String,
      rowId: (data['rowId'] ?? '') as String,
      action: (data['action'] ?? actionUpsert) as String,
      updatedAt: (data['updatedAt'] ?? 0) as int,
      payload: Map<String, Object?>.from(
        (data['payload'] ?? <String, Object?>{}) as Map<Object?, Object?>,
      ),
    );
  }
}
