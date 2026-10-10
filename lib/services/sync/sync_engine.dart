import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../database/sync_tables.dart';
import '../../models/sync_op.dart';
import 'link_service.dart';
import 'sync_store.dart';

enum SyncStatus {
  /// Firebase is not configured at build time — the app is local-only.
  disabled,

  /// Configured, but this device is not linked to any workspace yet.
  idle,

  /// Linked and idle; nothing pending.
  synced,

  /// Pushing local ops or applying remote ones.
  syncing,

  /// Linked, but the last attempt failed (typically offline).
  offline,
}

/// Replication engine for Linked Devices.
///
/// Strategy: **delta journal + per-row last-writer-wins**.
///
/// * Local mutations are captured by SQLite triggers into `sync_outbox`
///   (see `sync_tables.dart`), so no business-logic code path is involved.
/// * Outbox rows are collapsed per row and pushed as immutable ops.
/// * Remote ops are replayed in id order and applied only when they are newer
///   than what this device already holds — ties are broken deterministically
///   by origin device id, so every device converges to the same state.
/// * Applying a remote op suspends trigger capture, which stops the change
///   from echoing straight back out.
class SyncEngine extends ChangeNotifier {
  SyncEngine({
    required Future<Database> Function() database,
    LinkService? linkService,
    SyncStore store = const SyncStore(),
  })  : _database = database,
        _linkService = linkService ?? LinkService(),
        _store = store;

  final Future<Database> Function() _database;
  final LinkService _linkService;
  final SyncStore _store;

  static const int _batchLimit = 200;

  String? _workspaceId;
  SyncStatus _status = SyncStatus.disabled;
  String? _statusMessage;
  int _pendingCount = 0;
  int _appliedCount = 0;
  int _opCounter = 0;
  bool _running = false;
  bool _disposed = false;
  bool _catchingUp = false;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _opsSubscription;
  Timer? _heartbeatTimer;
  Timer? _retryTimer;

  SyncStatus get status => _status;
  String? get statusMessage => _statusMessage;
  String? get workspaceId => _workspaceId;
  int get pendingCount => _pendingCount;
  int get appliedCount => _appliedCount;
  bool get isLinked => _workspaceId != null;

  LinkService get linkService => _linkService;

  /// Called after remote ops changed local data. Every provider already
  /// listens to `AppDatabase.onDataChanged`, so wiring this to
  /// `AppDatabase.instance.notifyDataChanged` refreshes the whole UI.
  void Function()? onDataChanged;

  // ------------------------------------------------------------- lifecycle

  /// Starts replicating [workspaceId]. Safe to call again to switch workspace.
  Future<void> start(String workspaceId) async {
    await stop();

    _workspaceId = workspaceId;
    _running = true;
    _setStatus(SyncStatus.syncing);

    final Database db = await _database();
    await _store.setStateValue(db, kSyncWorkspaceStateKey, workspaceId);

    // Heartbeat keeps the roster's "last seen" useful for the owner.
    _heartbeatTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(_linkService.heartbeat(workspaceId)),
    );
    unawaited(_linkService.heartbeat(workspaceId));

    _subscribeToRemoteOps(workspaceId);

    await catchUp();
    await pushPending();
  }

  /// Stops replication and forgets the linked workspace.
  Future<void> stop() async {
    _running = false;
    await _opsSubscription?.cancel();
    _opsSubscription = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;

    if (_workspaceId != null) {
      try {
        final Database db = await _database();
        await _store.clearState(db, kSyncWorkspaceStateKey);
      } catch (_) {
        // Database may already be closed during shutdown.
      }
    }

    _workspaceId = null;
    _setStatus(SyncStatus.idle);
  }

  /// Marks the engine as unavailable because Firebase was not configured at
  /// build time. The rest of the app is unaffected.
  void markDisabled() {
    _running = false;
    _setStatus(
      SyncStatus.disabled,
      message: 'Linked Devices needs a Firebase build configuration.',
    );
  }

  /// Restores a previous session on app start, if there was one.
  Future<void> restore() async {
    try {
      final Database db = await _database();
      final String? workspaceId = await _store.state(db, kSyncWorkspaceStateKey);
      if (workspaceId != null && workspaceId.isNotEmpty) {
        await start(workspaceId);
      } else {
        _setStatus(SyncStatus.idle);
      }
    } catch (_) {
      _setStatus(SyncStatus.idle);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _running = false;
    unawaited(_opsSubscription?.cancel());
    _heartbeatTimer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------ push

  /// Queues the entire local ledger for upload, then pushes it.
  ///
  /// Needed once when an existing ledger is linked for the first time: the
  /// capture triggers have only seen changes made *after* they were created.
  Future<void> publishFullSnapshot() async {
    if (!_running) {
      return;
    }
    final Database db = await _database();
    await _store.queueFullSnapshot(db);
    await pushPending();
  }

  /// Pushes every pending local mutation as an immutable op.
  Future<void> pushPending() async {
    final String? workspaceId = _workspaceId;
    if (!_running || workspaceId == null) {
      return;
    }

    try {
      final Database db = await _database();
      final List<PendingOp> pending = await _store.pendingOps(db);
      _pendingCount = pending.length;
      _safeNotify();

      if (pending.isEmpty) {
        _setStatus(SyncStatus.synced);
        return;
      }

      _setStatus(SyncStatus.syncing);

      // A committed WriteBatch cannot be reused, so a fresh one is created
      // after every flush.
      WriteBatch batch = _linkService.firestore.batch();
      int queued = 0;
      final List<int> flushedIds = <int>[];

      Future<void> flush() async {
        if (queued == 0) {
          return;
        }
        await batch.commit();
        await _store.markPushed(db, List<int>.from(flushedIds));
        flushedIds.clear();
        queued = 0;
        batch = _linkService.firestore.batch();
      }

      for (final PendingOp op in pending) {
        if (queued >= _batchLimit) {
          await flush();
        }

        final String opId = SyncOp.newOpId(
          deviceId: _linkService.identity.deviceId,
          counter: _opCounter++,
        );

        final SyncOp syncOp = SyncOp(
          opId: opId,
          originDeviceId: _linkService.identity.deviceId,
          table: op.table,
          rowId: op.rowId,
          action: op.action,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          payload: op.payload,
        );

        batch.set(
          _linkService.opsRef(workspaceId).doc(opId),
          syncOp.toDocument(),
        );
        flushedIds.addAll(op.outboxIds);
        queued++;
      }

      await flush();
      await _store.prunePushed(db);

      _pendingCount = 0;
      _setStatus(SyncStatus.synced);
    } catch (error) {
      _setStatus(SyncStatus.offline, message: _describeError(error));
      _scheduleRetry();
    }
  }

  // ----------------------------------------------------------------- apply

  /// Replays the journal from the stored cursor, page by page.
  ///
  /// A live `limitToLast` snapshot alone would silently skip history on a
  /// workspace that already has more than one page of ops.
  Future<void> catchUp() async {
    final String? workspaceId = _workspaceId;
    if (!_running || workspaceId == null || _catchingUp) {
      return;
    }
    _catchingUp = true;

    try {
      final Database db = await _database();
      String cursor = await _store.state(db, kSyncCursorStateKey) ?? '';

      while (_running) {
        Query<Map<String, dynamic>> query = _linkService
            .opsRef(workspaceId)
            .orderBy('opId')
            .limit(_batchLimit);

        if (cursor.isNotEmpty) {
          query = query.startAfter(<Object?>[cursor]);
        }

        final QuerySnapshot<Map<String, dynamic>> snapshot = await query.get();
        if (snapshot.docs.isEmpty) {
          break;
        }

        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in snapshot.docs) {
          final SyncOp op = SyncOp.fromDocument(doc.data());
          await _consume(op);
          cursor = doc.id;
        }

        await _store.setStateValue(db, kSyncCursorStateKey, cursor);

        if (snapshot.docs.length < _batchLimit) {
          break;
        }
      }

      _setStatus(_pendingCount == 0 ? SyncStatus.synced : SyncStatus.syncing);
    } catch (error) {
      _setStatus(SyncStatus.offline, message: _describeError(error));
      _scheduleRetry();
    } finally {
      _catchingUp = false;
    }
  }

  void _subscribeToRemoteOps(String workspaceId) {
    _opsSubscription = _linkService
        .opsRef(workspaceId)
        .orderBy('opId')
        .limitToLast(_batchLimit)
        .snapshots()
        .listen(
      (QuerySnapshot<Map<String, dynamic>> snapshot) {
        unawaited(_applyLiveSnapshot(snapshot));
      },
      onError: (Object error) {
        _setStatus(SyncStatus.offline, message: _describeError(error));
        _scheduleRetry();
      },
    );
  }

  Future<void> _applyLiveSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (!_running) {
      return;
    }

    final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
        List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(snapshot.docs)
          ..sort(
            (
              QueryDocumentSnapshot<Map<String, dynamic>> a,
              QueryDocumentSnapshot<Map<String, dynamic>> b,
            ) =>
                a.id.compareTo(b.id),
          );

    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in docs) {
      await _consume(SyncOp.fromDocument(doc.data()));
    }

    // A full page means more ops may exist than the window can show — fall
    // back to a proper paged replay so nothing is skipped.
    if (docs.length >= _batchLimit) {
      await catchUp();
    }

    _setStatus(_pendingCount == 0 ? SyncStatus.synced : SyncStatus.syncing);
  }

  Future<void> _consume(SyncOp op) async {
    // Our own writes already landed locally — just book-keep them so the
    // cursor can move past them.
    if (op.originDeviceId == _linkService.identity.deviceId) {
      final Database db = await _database();
      if (!await _store.isApplied(db, op.opId)) {
        await _store.markApplied(db, op.opId);
      }
      return;
    }

    if (await applyOp(op)) {
      _appliedCount++;
      onDataChanged?.call();
    }
  }

  /// Applies one remote op with the LWW guard. Returns true when the op is
  /// now considered applied (including "skipped because stale").
  @visibleForTesting
  Future<bool> applyOp(SyncOp op) async {
    final Database db = await _database();

    if (await _store.isApplied(db, op.opId)) {
      return true;
    }

    if (!kSyncedTables.contains(op.table)) {
      // Unknown table (older/newer client) — mark applied so it never blocks
      // the cursor again.
      await _store.markApplied(db, op.opId);
      return true;
    }

    final ({int updatedAt, String origin})? current =
        await _store.rowState(db, op.table, op.rowId);

    if (current != null && !_wins(op, current.updatedAt, current.origin)) {
      await _store.markApplied(db, op.opId);
      return true;
    }

    await db.execute(kSyncCaptureSuspendSql);
    try {
      final String pk = kSyncPrimaryKeys[op.table]!;
      final Object? pkValue = _coercePk(op.rowId, op.table);

      if (op.isDelete) {
        await db.delete(
          op.table,
          where: '$pk = ?',
          whereArgs: <Object?>[pkValue],
        );
      } else {
        final Map<String, Object?> values =
            Map<String, Object?>.from(op.payload)..[pk] = pkValue;
        await db.insert(
          op.table,
          values,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await _store.putRowState(
        db,
        table: op.table,
        rowId: op.rowId,
        updatedAt: op.updatedAt,
        origin: op.originDeviceId,
      );
      await _store.markApplied(db, op.opId);
      return true;
    } catch (error) {
      // Most likely a foreign-key ordering problem: an entry arrived before
      // its customer. Retry a bounded number of times, then park the op so it
      // cannot wedge the journal forever.
      final bool retry = await _store.registerFailedApply(db, op.opId);
      if (retry) {
        _scheduleRetry();
      } else {
        debugPrint(
          'SyncEngine: parked op ${op.opId} after repeated failures: $error',
        );
      }
      return false;
    } finally {
      await db.execute(kSyncCaptureResumeSql);
    }
  }

  /// Last-writer-wins, with a deterministic tiebreak so two devices never
  /// disagree about which of two equal timestamps won.
  bool _wins(SyncOp op, int localUpdatedAt, String localOrigin) {
    if (op.updatedAt != localUpdatedAt) {
      return op.updatedAt > localUpdatedAt;
    }
    return op.originDeviceId.compareTo(localOrigin) > 0;
  }

  Object? _coercePk(String rowId, String table) {
    if (kSyncPrimaryKeys[table] == 'settingKey') {
      return rowId;
    }
    return int.tryParse(rowId) ?? rowId;
  }

  void _scheduleRetry() {
    if (!_running || _retryTimer?.isActive == true) {
      return;
    }
    _retryTimer = Timer(const Duration(seconds: 20), () {
      unawaited(catchUp().then((_) => pushPending()));
    });
  }

  void _setStatus(SyncStatus status, {String? message}) {
    _status = status;
    _statusMessage = message;
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  String _describeError(Object error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'unavailable':
          return 'Offline — changes will sync when the connection returns.';
        case 'permission-denied':
          return 'Access denied. Deploy the latest firestore.rules.';
        default:
          return error.message ?? 'Sync failed.';
      }
    }
    return 'Sync failed: $error';
  }
}
