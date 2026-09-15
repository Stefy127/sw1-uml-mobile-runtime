import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:sw1_uml_mobile_runtime/core/api/generic_api_service.dart';
import 'package:sw1_uml_mobile_runtime/core/database/generic_repository.dart';
import 'package:sw1_uml_mobile_runtime/core/database/local_database.dart';
import 'package:sw1_uml_mobile_runtime/core/database/pending_operation.dart';
import 'package:sw1_uml_mobile_runtime/core/sync/sync_service.dart';
import 'package:sw1_uml_mobile_runtime/schema/model/runtime_schema.dart';

class _FakeApi extends GenericApiService {
  bool createCalled = false;

  @override
  Future<Map<String, dynamic>> create(
    String path,
    Map<String, dynamic> body,
  ) async {
    createCalled = true;
    return {'id': 7, 'name': body['name']};
  }
}

class _OfflineApi extends GenericApiService {
  var createCalls = 0;
  var deleteCalls = 0;

  @override
  Future<Map<String, dynamic>> create(
    String path,
    Map<String, dynamic> body,
  ) async {
    createCalls++;
    throw ClientException('offline');
  }

  @override
  Future<void> delete(String path, dynamic id) async {
    deleteCalls++;
    throw ClientException('offline');
  }

  @override
  Future<Map<String, dynamic>> update(
    String path,
    dynamic id,
    Map<String, dynamic> body,
  ) async {
    throw ClientException('offline');
  }
}

class _BatchApi extends GenericApiService {
  final List<String> createdNames = [];
  final List<dynamic> updatedIds = [];
  final List<Map<String, dynamic>> updatedBodies = [];
  final Set<String> failingNames;

  _BatchApi({this.failingNames = const {}});

  @override
  Future<Map<String, dynamic>> create(
    String path,
    Map<String, dynamic> body,
  ) async {
    final name = body['name'] as String;
    if (failingNames.contains(name)) throw ClientException('offline');
    createdNames.add(name);
    return {'id': createdNames.length, ...body};
  }

  @override
  Future<Map<String, dynamic>> update(
    String path,
    dynamic id,
    Map<String, dynamic> body,
  ) async {
    updatedIds.add(id);
    updatedBodies.add(body);
    return {'id': id, ...body};
  }
}

class _HttpErrorApi extends GenericApiService {
  @override
  Future<Map<String, dynamic>> create(
    String path,
    Map<String, dynamic> body,
  ) async {
    throw Exception('HTTP 500');
  }
}

class _ReconnectApi extends GenericApiService {
  bool online = true;
  final List<Map<String, dynamic>> remoteRecords = [
    {'id': 1, 'name': 'Ana Perez'},
  ];

  void _requireOnline() {
    if (!online) throw ClientException('offline');
  }

  @override
  Future<List<Map<String, dynamic>>> getAll(String path) async {
    _requireOnline();
    return remoteRecords.map((record) => {...record}).toList();
  }

  @override
  Future<Map<String, dynamic>> create(
    String path,
    Map<String, dynamic> body,
  ) async {
    _requireOnline();
    final record = {
      'id': remoteRecords.length + 1,
      ...body,
    };
    remoteRecords.add(record);
    return {...record};
  }

  @override
  Future<Map<String, dynamic>> update(
    String path,
    dynamic id,
    Map<String, dynamic> body,
  ) async {
    _requireOnline();
    final index = remoteRecords.indexWhere((record) => record['id'] == id);
    if (index < 0) throw Exception('missing record');
    remoteRecords[index] = {...remoteRecords[index], ...body};
    return {...remoteRecords[index]};
  }

  @override
  Future<void> delete(String path, dynamic id) async {
    _requireOnline();
    remoteRecords.removeWhere((record) => record['id'] == id);
  }
}

class _RemoteWhilePendingApi extends GenericApiService {
  @override
  Future<List<Map<String, dynamic>>> getAll(String path) async => [
        {'id': 1, 'name': 'Ana Perez'},
      ];

  @override
  Future<Map<String, dynamic>> create(
    String path,
    Map<String, dynamic> body,
  ) async {
    throw ClientException('still offline for sync');
  }
}

class _GuardApi extends GenericApiService {
  final List<dynamic> updateIds = [];
  final List<dynamic> deleteIds = [];

  @override
  Future<Map<String, dynamic>> update(
    String path,
    dynamic id,
    Map<String, dynamic> body,
  ) async {
    updateIds.add(id);
    if (id.toString().startsWith('local-')) {
      throw StateError('temporary ID reached update');
    }
    return {'id': id, ...body};
  }

  @override
  Future<void> delete(String path, dynamic id) async {
    deleteIds.add(id);
    if (id.toString().startsWith('local-')) {
      throw StateError('temporary ID reached delete');
    }
  }
}

RuntimeEntity _entity(String endpoint) => RuntimeEntity(
      name: 'TestEntity',
      endpoint: endpoint,
      idField: 'id',
      displayField: 'name',
      operations: RuntimeOperations(
        list: true,
        get: true,
        create: true,
        update: true,
        delete: true,
      ),
      fields: [],
    );

Future<void> _clear(String endpoint) async {
  await LocalDatabase.delete('pending_operations');
  await LocalDatabase.delete('entity_cache:$endpoint');
}

PendingOperation _createOperation(
  String id,
  String endpoint,
  String temporaryId,
  String name,
) => PendingOperation(
      id: id,
      entityEndpoint: endpoint,
      operationType: PendingOperationType.create,
      recordId: temporaryId,
      idField: 'id',
      payload: {'name': name},
      createdAt: DateTime.utc(2026, 1, 1).add(Duration(seconds: int.parse(id))),
    );

void main() {
  test('pending operation serializes and deserializes', () {
    final operation = PendingOperation(
      id: 'op-1',
      entityEndpoint: '/api/items',
      operationType: PendingOperationType.update,
      recordId: 4,
      payload: {'name': 'Updated'},
      createdAt: DateTime.utc(2026, 1, 1),
    );
    final restored = PendingOperation.fromJson(operation.toJson());
    expect(restored.id, operation.id);
    expect(restored.operationType, PendingOperationType.update);
    expect(restored.payload['name'], 'Updated');
  });

  test('local database stores generic values', () async {
    await LocalDatabase.put('test_entity_cache', [
      {'id': 1, 'name': 'Example'},
    ]);
    final value = await LocalDatabase.get('test_entity_cache') as List;
    expect((value.first as Map)['name'], 'Example');
  });

  test('sync flushes pending operation and reconciles cache', () async {
    const endpoint = '/api/sync-test';
    final api = _FakeApi();
    final sync = SyncService(api: api);

    await LocalDatabase.delete('pending_operations');
    await LocalDatabase.delete('entity_cache:$endpoint');
    await LocalDatabase.put('entity_cache:$endpoint', [
      {'id': 'local-1', 'name': 'Offline'},
    ]);
    await sync.enqueue(PendingOperation(
      id: 'op-sync-test',
      entityEndpoint: endpoint,
      operationType: PendingOperationType.create,
      recordId: 'local-1',
      idField: 'id',
      payload: {'name': 'Offline'},
      createdAt: DateTime.utc(2026, 1, 1),
    ));

    expect(await sync.flush(), 1);
    expect(api.createCalled, isTrue);
    expect(await sync.pendingOperations(), isEmpty);
    final cache = await LocalDatabase.get('entity_cache:$endpoint') as List;
    expect((cache.single as Map)['id'], 7);
    await LocalDatabase.delete('entity_cache:$endpoint');
  });

  test('offline update merges into pending create', () async {
    const endpoint = '/api/merge-test';
    await _clear(endpoint);
    final repository = GenericRepository(api: _OfflineApi());
    final entity = _entity(endpoint);

    final created = await repository.create(entity, {'name': 'Offline'});
    await repository.update(entity, created['id'], {'name': 'Offline editada'});

    final pending = await repository.sync.pendingOperations();
    expect(pending, hasLength(1));
    expect(pending.single.operationType, PendingOperationType.create);
    expect(pending.single.payload['name'], 'Offline editada');
    final cache = await LocalDatabase.get('entity_cache:$endpoint') as List;
    expect((cache.single as Map)['name'], 'Offline editada');
  });

  test('flush processes two pending creates', () async {
    const endpoint = '/api/batch-test';
    await _clear(endpoint);
    final api = _BatchApi();
    final sync = SyncService(api: api);
    await LocalDatabase.put('entity_cache:$endpoint', [
      {'id': 'temp-a', 'name': 'A'},
      {'id': 'temp-b', 'name': 'B'},
    ]);
    await sync.enqueue(_createOperation('1', endpoint, 'temp-a', 'A'));
    await sync.enqueue(_createOperation('2', endpoint, 'temp-b', 'B'));

    expect(await sync.flush(), 2);
    expect(api.createdNames, ['A', 'B']);
    expect(await sync.pendingOperations(), isEmpty);
    final cache = await LocalDatabase.get('entity_cache:$endpoint') as List;
    expect(cache.map((item) => (item as Map)['id']), [1, 2]);
  });

  test('create and delete before sync cancels remote work', () async {
    const endpoint = '/api/cancel-test';
    await _clear(endpoint);
    final api = _OfflineApi();
    final repository = GenericRepository(api: api);
    final entity = _entity(endpoint);

    final created = await repository.create(entity, {'name': 'Borrar'});
    await repository.delete(entity, created['id']);

    expect(await repository.sync.pendingOperations(), isEmpty);
    expect(api.createCalls, 1);
    expect(api.deleteCalls, 0);
    expect(await LocalDatabase.get('entity_cache:$endpoint'), isEmpty);
  });

  test('create reconciliation updates temporary IDs in later references', () async {
    const endpoint = '/api/reference-test';
    await _clear(endpoint);
    final api = _BatchApi();
    final sync = SyncService(api: api);
    await LocalDatabase.put('entity_cache:$endpoint', [
      {'id': 'temp-a', 'name': 'A'},
    ]);
    await sync.enqueue(_createOperation('1', endpoint, 'temp-a', 'A'));
    await sync.enqueue(PendingOperation(
      id: '2',
      entityEndpoint: endpoint,
      operationType: PendingOperationType.update,
      recordId: 'temp-a',
      idField: 'id',
      payload: {'parentId': 'temp-a', 'name': 'A editada'},
      createdAt: DateTime.utc(2026, 1, 1).add(const Duration(seconds: 2)),
    ));

    expect(await sync.flush(), 2);
    expect(api.updatedIds, [1]);
    expect(api.updatedBodies.single['parentId'], 1);
  });

  test('network failure on second operation preserves second and later', () async {
    const endpoint = '/api/partial-test';
    await _clear(endpoint);
    final api = _BatchApi(failingNames: {'B'});
    final sync = SyncService(api: api);
    await LocalDatabase.put('entity_cache:$endpoint', [
      {'id': 'temp-a', 'name': 'A'},
      {'id': 'temp-b', 'name': 'B'},
    ]);
    await sync.enqueue(_createOperation('1', endpoint, 'temp-a', 'A'));
    await sync.enqueue(_createOperation('2', endpoint, 'temp-b', 'B'));

    expect(await sync.flush(), 1);
    expect(await sync.pendingOperations(), hasLength(1));
    expect((await sync.pendingOperations()).single.recordId, 'temp-b');
  });

  test('HTTP error does not silently remove pending operation', () async {
    const endpoint = '/api/http-error-test';
    await _clear(endpoint);
    final sync = SyncService(api: _HttpErrorApi());
    await sync.enqueue(_createOperation('1', endpoint, 'temp-a', 'A'));

    expect(await sync.flush(), 0);
    expect(await sync.pendingOperations(), hasLength(1));
  });

  test('reconnection flow flushes before remote refresh', () async {
    const endpoint = '/api/reconnect-test';
    await _clear(endpoint);
    final api = _ReconnectApi();
    final repository = GenericRepository(api: api);
    final entity = _entity(endpoint);

    final initial = await repository.getAllWithSource(entity);
    expect(initial.records.map((record) => record['name']), ['Ana Perez']);

    api.online = false;
    final first = await repository.create(entity, {'name': 'Offline'});
    await repository.update(entity, first['id'], {'name': 'Offline editada'});
    await repository.create(entity, {'name': 'offline 2'});
    final toDelete = await repository.create(
      entity,
      {'name': 'Persona Para borrar'},
    );
    await repository.delete(entity, toDelete['id']);

    final offline = await repository.getAllWithSource(entity);
    expect(
      offline.records.map((record) => record['name']),
      ['Ana Perez', 'Offline editada', 'offline 2'],
    );

    api.online = true;
    final afterReconnect = await repository.getAllWithSource(entity);
    expect(
      afterReconnect.records.map((record) => record['name']),
      ['Ana Perez', 'Offline editada', 'offline 2'],
    );
    expect(api.remoteRecords.map((record) => record['name']),
        ['Ana Perez', 'Offline editada', 'offline 2']);
    expect(await repository.sync.pendingOperations(), isEmpty);
  });

  test('remote refresh overlays pending records when flush cannot complete', () async {
    const endpoint = '/api/overlay-test';
    await _clear(endpoint);
    final repository = GenericRepository(api: _RemoteWhilePendingApi());
    final entity = _entity(endpoint);
    await repository.sync.enqueue(
      _createOperation('1', endpoint, 'temp-a', 'Offline editada'),
    );

    final result = await repository.getAllWithSource(entity);

    expect(
      result.records.map((record) => record['name']),
      ['Ana Perez', 'Offline editada'],
    );
    expect(await repository.sync.pendingOperations(), hasLength(1));
  });

  test('legacy create and update normalize to one updated create', () async {
    const endpoint = '/api/legacy-update-test';
    await _clear(endpoint);
    final sync = SyncService(api: _GuardApi());
    await sync.enqueue(PendingOperation(
      id: 'create-legacy',
      entityEndpoint: endpoint,
      operationType: PendingOperationType.create,
      recordId: 'local-1',
      idField: 'id',
      payload: {'id': 'local-1', 'name': 'Offline'},
      createdAt: DateTime.utc(2026, 1, 1),
    ));
    await sync.enqueue(PendingOperation(
      id: 'update-legacy',
      entityEndpoint: endpoint,
      operationType: PendingOperationType.update,
      recordId: 'local-1',
      idField: 'id',
      payload: {'name': 'Offline editada'},
      createdAt: DateTime.utc(2026, 1, 1).add(const Duration(seconds: 1)),
    ));

    final normalized = await sync.normalizePendingOperations();
    expect(normalized, hasLength(1));
    expect(normalized.single.operationType, PendingOperationType.create);
    expect(normalized.single.payload, {'name': 'Offline editada'});
  });

  test('legacy create and delete normalize to no remote operation', () async {
    const endpoint = '/api/legacy-delete-test';
    await _clear(endpoint);
    final api = _GuardApi();
    final sync = SyncService(api: api);
    await sync.enqueue(_createOperation('1', endpoint, 'local-1', 'Borrar'));
    await sync.enqueue(PendingOperation(
      id: 'delete-legacy',
      entityEndpoint: endpoint,
      operationType: PendingOperationType.delete,
      recordId: 'local-1',
      idField: 'id',
      payload: {},
      createdAt: DateTime.utc(2026, 1, 1).add(const Duration(seconds: 1)),
    ));

    expect(await sync.flush(), 0);
    expect(await sync.pendingOperations(), isEmpty);
    expect(api.updateIds, isEmpty);
    expect(api.deleteIds, isEmpty);
  });

  test('orphan temporary update and delete never reach backend', () async {
    const endpoint = '/api/orphan-test';
    await _clear(endpoint);
    final api = _GuardApi();
    final sync = SyncService(api: api);
    await sync.enqueue(PendingOperation(
      id: 'update-orphan',
      entityEndpoint: endpoint,
      operationType: PendingOperationType.update,
      recordId: 'local-1',
      idField: 'id',
      payload: {'name': 'Orphan'},
      createdAt: DateTime.utc(2026, 1, 1),
    ));
    await sync.enqueue(PendingOperation(
      id: 'delete-orphan',
      entityEndpoint: endpoint,
      operationType: PendingOperationType.delete,
      recordId: 'local-2',
      idField: 'id',
      payload: {},
      createdAt: DateTime.utc(2026, 1, 1).add(const Duration(seconds: 1)),
    ));

    expect(await sync.flush(), 0);
    expect(await sync.pendingOperations(), isEmpty);
    expect(api.updateIds, isEmpty);
    expect(api.deleteIds, isEmpty);
  });

  test('repository guards public update and delete for temporary IDs', () async {
    const endpoint = '/api/repository-guard-test';
    await _clear(endpoint);
    final api = _GuardApi();
    final repository = GenericRepository(api: api);
    final entity = _entity(endpoint);

    await repository.update(entity, 'local-1', {'name': 'Local'});
    await repository.delete(entity, 'local-1');

    expect(api.updateIds, isEmpty);
    expect(api.deleteIds, isEmpty);
  });
}
