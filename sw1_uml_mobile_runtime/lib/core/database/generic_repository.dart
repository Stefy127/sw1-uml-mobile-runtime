import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart';
import '../../schema/model/runtime_schema.dart';
import '../api/generic_api_service.dart';
import '../sync/sync_service.dart';
import '../sync/sync_coordinator.dart';
import 'pending_operation.dart';
import 'local_database.dart';

class RepositoryResult {
  final List<Map<String, dynamic>> records;
  final bool fromCache;
  const RepositoryResult(this.records, {required this.fromCache});
}

class GenericRepository {
  final GenericApiService api;
  late final SyncService sync = SyncService(api: api);
  late final SyncCoordinator coordinator;

  GenericRepository({GenericApiService? api, SyncCoordinator? coordinator})
      : api = api ?? GenericApiService() {
    this.coordinator = coordinator ??
        (api == null ? SyncCoordinator.shared : SyncCoordinator(service: sync));
    this.coordinator.configure(sync);
  }

  String _key(RuntimeEntity entity) => 'entity_cache:${entity.endpoint}';

  Future<RepositoryResult> getAllWithSource(RuntimeEntity entity) async {
    final pendingBefore = await coordinator.refreshPendingCount();
    debugPrint('SYNC pending before refresh=$pendingBefore');
    try {
      await coordinator.flush();
      final remoteRecords = await api.getAll(entity.endpoint).timeout(
        const Duration(seconds: 10),
      );
      final pendingAfter = await coordinator.refreshPendingCount();
      final records = pendingAfter == 0
          ? remoteRecords
          : await sync.applyPendingOverlay(entity.endpoint, remoteRecords);
      if (pendingAfter > 0) {
        debugPrint('REFRESH remote while pending=$pendingAfter');
      } else {
        debugPrint('REFRESH remote after sync');
      }
      coordinator.markOnline();
      await LocalDatabase.put(_key(entity), records);
      await LocalDatabase.put(
        'sync:${entity.endpoint}',
        DateTime.now().toIso8601String(),
      );
      return RepositoryResult(records, fromCache: false);
    } on ClientException catch (_) {
      coordinator.markOffline();
      await coordinator.refreshPendingCount();
      return _cached(entity);
    }
    on TimeoutException catch (_) {
      coordinator.markOffline();
      await coordinator.refreshPendingCount();
      return _cached(entity);
    }
  }

  Future<RepositoryResult> _cached(RuntimeEntity entity) async {
    final value = await LocalDatabase.get(_key(entity));
    if (value is List) {
      return RepositoryResult(
        value.map((item) => Map<String, dynamic>.from(item as Map)).toList(),
        fromCache: true,
      );
    }
    throw Exception('Sin conexión y sin datos guardados para ${entity.name}.');
  }

  Future<List<Map<String, dynamic>>> getAll(RuntimeEntity entity) async =>
      (await getAllWithSource(entity)).records;

  Future<Map<String, dynamic>> create(
    RuntimeEntity entity,
    Map<String, dynamic> body,
  ) async {
    try {
      final record = await api.create(entity.endpoint, body);
      await _appendToCache(entity, record);
      return record;
    } on ClientException catch (_) {
      return _queueCreate(entity, body);
    } on TimeoutException catch (_) {
      return _queueCreate(entity, body);
    }
  }

  Future<Map<String, dynamic>> update(
    RuntimeEntity entity,
    dynamic id,
    Map<String, dynamic> body,
  ) async {
    if (_isTemporaryId(id)) {
      final merged = await sync.mergeIntoPendingCreate(entity.endpoint, id, body);
      if (!merged) {
        await _removeLocalPendingOperation(entity, id);
      }
      await _mergeInCache(entity, id, body);
      return body;
    }
    try {
      final record = await api.update(entity.endpoint, id, body);
      await _mergeInCache(entity, id, record.isEmpty ? body : record);
      return record;
    } on ClientException catch (_) {
      final merged = await sync.mergeIntoPendingCreate(entity.endpoint, id, body);
      if (!merged) await _queue(PendingOperationType.update, entity, id, body);
      await _mergeInCache(entity, id, body);
      return body;
    } on TimeoutException catch (_) {
      final merged = await sync.mergeIntoPendingCreate(entity.endpoint, id, body);
      if (!merged) await _queue(PendingOperationType.update, entity, id, body);
      await _mergeInCache(entity, id, body);
      return body;
    }
  }

  Future<void> delete(RuntimeEntity entity, dynamic id) async {
    if (_isTemporaryId(id) && await sync.cancelPendingCreate(entity.endpoint, id)) {
      await _removeFromCache(entity, id);
      await coordinator.refreshPendingCount();
      return;
    }
    if (_isTemporaryId(id)) {
      await _removeFromCache(entity, id);
      return;
    }
    try {
      await api.delete(entity.endpoint, id);
    } on ClientException catch (_) {
      await _queue(PendingOperationType.delete, entity, id, {});
    } on TimeoutException catch (_) {
      await _queue(PendingOperationType.delete, entity, id, {});
    }
    await _removeFromCache(entity, id);
  }

  Future<Map<String, dynamic>> _queueCreate(
    RuntimeEntity entity,
    Map<String, dynamic> body,
  ) async {
    final localId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final record = {...body, entity.idField: localId};
    await _queue(PendingOperationType.create, entity, localId, body);
    await coordinator.refreshPendingCount();
    await _appendToCache(entity, record);
    return record;
  }

  Future<void> _queue(
    PendingOperationType type,
    RuntimeEntity entity,
    dynamic id,
    Map<String, dynamic> payload,
  ) async {
    await sync.enqueue(PendingOperation(
      id: 'op-${DateTime.now().microsecondsSinceEpoch}',
      entityEndpoint: entity.endpoint,
      operationType: type,
      recordId: id,
      idField: entity.idField,
      payload: payload,
      createdAt: DateTime.now().toUtc(),
    ));
    await coordinator.refreshPendingCount();
  }

  Future<List<Map<String, dynamic>>> _cachedRecords(RuntimeEntity entity) async {
    final value = await LocalDatabase.get(_key(entity));
    if (value is! List) return [];
    return value.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<void> _appendToCache(RuntimeEntity entity, Map<String, dynamic> record) async {
    final records = await _cachedRecords(entity);
    records.add(record);
    await LocalDatabase.put(_key(entity), records);
  }

  Future<void> _mergeInCache(
    RuntimeEntity entity,
    dynamic id,
    Map<String, dynamic> changes,
  ) async {
    final records = await _cachedRecords(entity);
    final index = records.indexWhere((record) => record[entity.idField] == id);
    if (index >= 0) records[index] = {...records[index], ...changes};
    await LocalDatabase.put(_key(entity), records);
  }

  Future<void> _removeFromCache(RuntimeEntity entity, dynamic id) async {
    final records = await _cachedRecords(entity);
    records.removeWhere((record) => record[entity.idField] == id);
    await LocalDatabase.put(_key(entity), records);
  }

  Future<void> _removeLocalPendingOperation(
    RuntimeEntity entity,
    dynamic id,
  ) async {
    final operations = await sync.pendingOperations();
    final remaining = operations.where((operation) {
      return !(operation.entityEndpoint == entity.endpoint &&
          operation.recordId == id);
    }).toList();
    await LocalDatabase.put(
      'pending_operations',
      remaining.map((operation) => operation.toJson()).toList(),
    );
    await coordinator.refreshPendingCount();
  }

  bool _isTemporaryId(dynamic id) => id.toString().startsWith('local-');
}
