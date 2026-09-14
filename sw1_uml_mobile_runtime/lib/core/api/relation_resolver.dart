import '../../schema/model/runtime_schema.dart';
import 'generic_api_service.dart';
import '../database/generic_repository.dart';

class RelationResolver {
  final GenericApiService api;
  final RuntimeSchema schema;
  static final Map<String, Future<List<Map<String, dynamic>>>> _cache = {};
  late final GenericRepository repository = GenericRepository(api: api);
  RelationResolver(this.api, this.schema);

  RuntimeEntity? entity(String? name) => name == null ? null : schema.entityByName(name);

  Future<String> display(RuntimeField field, dynamic value) async {
    if (value == null) return '—';
    final target = entity(field.targetEntity);
    if (target == null) return value.toString();
    try {
      final records = await _cache.putIfAbsent(
        target.endpoint,
        () => repository.getAll(target),
      );
      final match = records.where((r) => r[target.idField].toString() == value.toString()).firstOrNull;
      return match?[target.displayField]?.toString() ?? value.toString();
    } catch (_) { return value.toString(); }
  }
}
