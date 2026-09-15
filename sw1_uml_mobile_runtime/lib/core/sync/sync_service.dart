import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart';

import '../api/generic_api_service.dart';
import '../database/local_database.dart';
import '../database/pending_operation.dart';

class SyncService {
  static const _queueKey = 'pending_operations';

  final GenericApiService api;

  SyncService({GenericApiService? api}) : api = api ?? GenericApiService();

  Future<void> enqueue(PendingOperation operation) async {
    final operations = await pendingOperations();
    operations.add(operation);
    await _save(operations);
  }

  Future<bool> mergeIntoPendingCreate(
    String endpoint,
    dynamic temporaryId,
    Map<String, dynamic> changes,
  ) async {
    final operations = await pendingOperations();
    final index = operations.indexWhere(
      (operation) =>
          operation.operationType == PendingOperationType.create &&
          operation.entityEndpoint == endpoint &&
          operation.recordId == temporaryId,
    );
    if (index < 0) return false;

    final operation = operations[index];
    operations[index] = PendingOperation(
      id: operation.id,
      entityEndpoint: operation.entityEndpoint,
      operationType: operation.operationType,
      recordId: operation.recordId,
      idField: operation.idField,
      payload: {...operation.payload, ...changes},
      createdAt: operation.createdAt,
      status: operation.status,
    );
    await _save(operations);
    return true;
  }

  Future<bool> cancelPendingCreate(String endpoint, dynamic temporaryId) async {
    final operations = await pendingOperations();
    final remaining = operations.where((operation) {
      return !(operation.entityEndpoint == endpoint &&
          operation.recordId == temporaryId &&
          _isTemporaryId(temporaryId));
    }).toList();
    if (remaining.length == operations.length) return false;
    await _save(remaining);
    return true;
  }

  Future<List<PendingOperation>> pendingOperations() async {
    final value = await LocalDatabase.get(_queueKey);
    if (value is! List) return [];
    return value
        .map((item) => PendingOperation.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<List<PendingOperation>> normalizePendingOperations() async {
    final source = await pendingOperations()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final normalized = <PendingOperation>[];
    final consumed = <int>{};

    for (var index = 0; index < source.length; index++) {
      if (consumed.contains(index)) continue;
      final operation = source[index];
      if (operation.operationType == PendingOperationType.create &&
          _isTemporaryId(operation.recordId)) {
        final related = <PendingOperation>[];
        for (var relatedIndex = index + 1;
            relatedIndex < source.length;
            relatedIndex++) {
          final candidate = source[relatedIndex];
          if (candidate.entityEndpoint == operation.entityEndpoint &&
              candidate.recordId == operation.recordId &&
              (candidate.operationType == PendingOperationType.update ||
                  candidate.operationType == PendingOperationType.delete)) {
            related.add(candidate);
            consumed.add(relatedIndex);
          }
        }
        if (related.any((item) => item.operationType == PendingOperationType.delete)) {
          consumed.add(index);
          continue;
        }
        var payload = _withoutTemporaryId(operation);
        for (final update in related.where(
          (item) => item.operationType == PendingOperationType.update,
        )) {
          payload = {...payload, ...update.payload};
        }
        final idField = operation.idField;
        if (idField != null && _isTemporaryId(payload[idField])) {
          payload.remove(idField);
        }
        normalized.add(_copyOperation(operation, payload: payload));
        consumed.add(index);
        continue;
      }

      if (_isTemporaryId(operation.recordId)) {
        consumed.add(index);
        continue;
      }
      normalized.add(operation);
      consumed.add(index);
    }
    await _save(normalized);
    return normalized;
  }

  Future<List<Map<String, dynamic>>> applyPendingOverlay(
    String endpoint,
    List<Map<String, dynamic>> records,
  ) async {
    final operations = (await pendingOperations())
        .where((operation) => operation.entityEndpoint == endpoint)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final result = records.map((record) => {...record}).toList();

    for (final operation in operations) {
      switch (operation.operationType) {
        case PendingOperationType.create:
          result.add({...operation.payload, operation.idField!: operation.recordId});
        case PendingOperationType.update:
          final index = result.indexWhere(
            (record) => record[operation.idField] == operation.recordId,
          );
          if (index >= 0) result[index] = {...result[index], ...operation.payload};
        case PendingOperationType.delete:
          result.removeWhere(
            (record) => record[operation.idField] == operation.recordId,
          );
      }
    }
    return result;
  }

  Future<int> flush() async {
    final operations = await normalizePendingOperations();
    debugPrint('SYNC start count=${operations.length}');
    var completed = 0;

    while (operations.isNotEmpty) {
      final operation = operations.first;
      _logOperation(operation);
      try {
        Map<String, dynamic>? response;
        switch (operation.operationType) {
          case PendingOperationType.create:
            response = await api.create(operation.entityEndpoint, operation.payload);
          case PendingOperationType.update:
            if (_isTemporaryId(operation.recordId)) {
              operations.removeAt(0);
              await _save(operations);
              continue;
            }
            response = await api.update(
              operation.entityEndpoint,
              operation.recordId,
              operation.payload,
            );
          case PendingOperationType.delete:
            if (_isTemporaryId(operation.recordId)) {
              operations.removeAt(0);
              await _save(operations);
              continue;
            }
            await api.delete(operation.entityEndpoint, operation.recordId);
        }
        if (operation.operationType == PendingOperationType.create) {
          final remoteId = response?[operation.idField];
          if (remoteId == null) {
            throw StateError('CREATE sin ID remoto para ${operation.id}');
          }
          debugPrint(
            'SYNC CREATE success temp=${operation.recordId} remote=$remoteId',
          );
          await _reconcileCreate(operation, response!, remoteId, operations);
        } else {
          await _applyToCache(operation, response);
        }
        operations.removeAt(0);
        await _save(operations);
        completed++;
      } on ClientException catch (_) {
        debugPrint('SYNC ${operation.operationType.name} failed op=${operation.id} network');
        break;
      } on TimeoutException catch (_) {
        debugPrint('SYNC ${operation.operationType.name} failed op=${operation.id} timeout');
        break;
      } catch (_) {
        debugPrint('SYNC ${operation.operationType.name} failed op=${operation.id} error');
        break;
      }
    }

    debugPrint('SYNC complete remaining=${operations.length}');
    return completed;
  }

  void _logOperation(PendingOperation operation) {
    final suffix = operation.operationType == PendingOperationType.create
        ? ' temp=${operation.recordId}'
        : ' id=${operation.recordId}';
    debugPrint('SYNC ${operation.operationType.name.toUpperCase()} op=${operation.id}$suffix');
  }

  Future<void> _reconcileCreate(
    PendingOperation operation,
    Map<String, dynamic> response,
    dynamic remoteId,
    List<PendingOperation> operations,
  ) async {
    final idField = operation.idField ?? 'id';
    final key = 'entity_cache:${operation.entityEndpoint}';
    final value = await LocalDatabase.get(key);
    if (value is List) {
      final records = value
          .map((item) => Map<String, dynamic>.from(
                _replaceValue(
                  Map<String, dynamic>.from(item as Map),
                  operation.recordId,
                  remoteId,
                ) as Map,
              ))
          .toList();
      final index = records.indexWhere(
        (record) => record[idField] == remoteId,
      );
      if (index >= 0) {
        records[index] = {...records[index], ...response};
      } else {
        records.add({...operation.payload, ...response, idField: remoteId});
      }
      await LocalDatabase.put(key, records);
    }

    for (var index = 1; index < operations.length; index++) {
      final pending = operations[index];
      operations[index] = PendingOperation(
        id: pending.id,
        entityEndpoint: pending.entityEndpoint,
        operationType: pending.operationType,
        recordId: _replaceValue(pending.recordId, operation.recordId, remoteId),
        idField: pending.idField,
        payload: Map<String, dynamic>.from(
          _replaceValue(pending.payload, operation.recordId, remoteId) as Map,
        ),
        createdAt: pending.createdAt,
        status: pending.status,
      );
    }
  }

  bool _isTemporaryId(dynamic id) => id.toString().startsWith('local-');

  PendingOperation _copyOperation(
    PendingOperation operation, {
    Map<String, dynamic>? payload,
    dynamic recordId,
  }) => PendingOperation(
        id: operation.id,
        entityEndpoint: operation.entityEndpoint,
        operationType: operation.operationType,
        recordId: recordId ?? operation.recordId,
        idField: operation.idField,
        payload: payload ?? operation.payload,
        createdAt: operation.createdAt,
        status: operation.status,
      );

  Map<String, dynamic> _withoutTemporaryId(PendingOperation operation) {
    final payload = {...operation.payload};
    final idField = operation.idField;
    if (idField != null && _isTemporaryId(payload[idField])) {
      payload.remove(idField);
    }
    return payload;
  }

  dynamic _replaceValue(dynamic value, dynamic temporaryId, dynamic remoteId) {
    if (value == temporaryId) return remoteId;
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key, _replaceValue(item, temporaryId, remoteId)),
      );
    }
    if (value is List) {
      return value.map((item) => _replaceValue(item, temporaryId, remoteId)).toList();
    }
    return value;
  }

  Future<void> _applyToCache(
    PendingOperation operation,
    Map<String, dynamic>? response,
  ) async {
    final key = 'entity_cache:${operation.entityEndpoint}';
    final value = await LocalDatabase.get(key);
    if (value is! List) return;
    final records = value.map((item) => Map<String, dynamic>.from(item as Map)).toList();

    switch (operation.operationType) {
      case PendingOperationType.create:
        final index = records.indexWhere(
          (record) => record[operation.idField] == operation.recordId,
        );
        if (index >= 0) {
          records[index] = {...records[index], ...?response};
        } else if (response != null && response.isNotEmpty) {
          records.add(response);
        }
      case PendingOperationType.update:
        final index = records.indexWhere(
          (record) => record[operation.idField] == operation.recordId,
        );
        if (index >= 0) records[index] = {...records[index], ...?response};
      case PendingOperationType.delete:
        records.removeWhere(
          (record) => record[operation.idField] == operation.recordId,
        );
    }
    await LocalDatabase.put(key, records);
  }

  Future<void> _save(List<PendingOperation> operations) async {
    if (operations.isEmpty) {
      await LocalDatabase.delete(_queueKey);
      return;
    }
    await LocalDatabase.put(
      _queueKey,
      operations.map((operation) => operation.toJson()).toList(),
    );
  }
}