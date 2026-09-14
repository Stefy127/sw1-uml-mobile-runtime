import 'package:flutter_test/flutter_test.dart';
import 'package:sw1_uml_mobile_runtime/core/database/local_database.dart';
import 'package:sw1_uml_mobile_runtime/core/database/pending_operation.dart';

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
}
