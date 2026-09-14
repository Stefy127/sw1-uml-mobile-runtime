import 'dart:async';
import 'package:http/http.dart';
import '../../schema/model/runtime_schema.dart';
import '../api/generic_api_service.dart';
import 'local_database.dart';

class RepositoryResult {
  final List<Map<String, dynamic>> records;
  final bool fromCache;
  const RepositoryResult(this.records, {required this.fromCache});
}

class GenericRepository {
  final GenericApiService api;
  GenericRepository({GenericApiService? api}) : api = api ?? GenericApiService();

  String _key(RuntimeEntity entity) => 'entity_cache:${entity.endpoint}';

  Future<RepositoryResult> getAllWithSource(RuntimeEntity entity) async {
    try {
      final records = await api.getAll(entity.endpoint).timeout(
        const Duration(seconds: 10),
      );
      await LocalDatabase.put(_key(entity), records);
      await LocalDatabase.put(
        'sync:${entity.endpoint}',
        DateTime.now().toIso8601String(),
      );
      return RepositoryResult(records, fromCache: false);
    } on ClientException catch (_) {
      return _cached(entity);
    } on TimeoutException catch (_) {
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
}
