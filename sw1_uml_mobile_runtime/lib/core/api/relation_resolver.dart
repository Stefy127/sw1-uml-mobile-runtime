import '../../schema/model/runtime_schema.dart';
import '../../core/database/generic_repository.dart';
import 'entity_resolver.dart';
import 'generic_api_service.dart';

enum RelationOperation { set, add, remove, replace, clear }
enum RelationResolutionStatus { resolved, notFound, ambiguous, invalid }

class RelationOperationNormalizer {
  static RelationOperation normalize(String input) {
    final value = input.toLowerCase();
    if (value.contains('deja solamente') ||
        value.contains('solamente') ||
        value.contains('solo') ||
        value.contains('reemplaza')) {
      return RelationOperation.replace;
    }
    if (value.contains('quita') ||
        value.contains('elimina') ||
        value.contains('remueve')) {
      return RelationOperation.remove;
    }
    if (value.contains('agrega') ||
        value.contains('añade') ||
        value.contains('add') ||
        value.contains('suma')) {
      return RelationOperation.add;
    }
    if (value.contains('asigna') ||
        value.contains('establece') ||
        value.contains('set') ||
        value.contains('pon')) {
      return RelationOperation.set;
    }
    return RelationOperation.set;
  }
}

class RelationResolutionResult {
  final RelationResolutionStatus status;
  final String message;
  final String fieldName;
  final String? owningFieldName;
  final dynamic valueId;
  final List<dynamic>? targetIds;
  final RelationOperation operation;
  final Map<String, dynamic> payload;

  const RelationResolutionResult({
    required this.status,
    this.message = '',
    this.fieldName = '',
    this.owningFieldName,
    this.valueId,
    this.targetIds,
    this.operation = RelationOperation.set,
    this.payload = const {},
  });
}

class RelationResolver {
  final GenericApiService api;
  final RuntimeSchema schema;
  static final Map<String, Future<List<Map<String, dynamic>>>> _cache = {};
  final GenericRepository repository;
  final EntityResolver entityResolver;

  RelationResolver(this.api, this.schema)
      : repository = GenericRepository(api: api),
        entityResolver = EntityResolver(repository: GenericRepository(api: api));

  RelationResolver.withRepository(this.repository, this.schema)
      : api = repository.api,
        entityResolver = EntityResolver(repository: repository);

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
    } catch (_) {
      return value.toString();
    }
  }

  Future<RelationResolutionResult> resolveField({
    required RuntimeEntity sourceEntity,
    required RuntimeField field,
    required Map<String, dynamic> sourceRecord,
    required String selector,
    required RelationOperation operation,
  }) async {
    if (field.relation != true) {
      return RelationResolutionResult(
        status: RelationResolutionStatus.invalid,
        message: 'El campo no es una relación.',
        fieldName: field.name,
        operation: operation,
      );
    }

    final targetEntity = _targetEntityFor(field);
    final target = await entityResolver.resolve(targetEntity, _selectorFromText(selector));
    if (target.status != EntityResolutionStatus.resolved) {
      return RelationResolutionResult(
        status: RelationResolutionStatus.notFound,
        message: target.message,
        fieldName: field.name,
        operation: operation,
      );
    }

    final resolvedId = _idOf(target.record!);
    if (resolvedId == null) {
      return RelationResolutionResult(
        status: RelationResolutionStatus.invalid,
        message: 'La entidad resuelta no tiene ID.',
        fieldName: field.name,
        operation: operation,
      );
    }

    final inverseField = _inverseOwningFieldFor(sourceEntity, field);
    if (field.readOnly && field.owningSide == false && inverseField != null) {
      return RelationResolutionResult(
        status: RelationResolutionStatus.resolved,
        message: 'Relación resuelta usando el lado propietario.',
        fieldName: field.name,
        owningFieldName: inverseField.name,
        valueId: resolvedId,
        targetIds: [resolvedId],
        operation: operation,
        payload: {inverseField.name: resolvedId},
      );
    }

    final payloadValue = field.collection ? <dynamic>[resolvedId] : resolvedId;
    return RelationResolutionResult(
      status: RelationResolutionStatus.resolved,
      message: 'Relación resuelta.',
      fieldName: field.name,
      valueId: resolvedId,
      targetIds: [resolvedId],
      operation: operation,
      payload: {field.name: payloadValue},
    );
  }

  Future<RelationResolutionResult> resolveAssociationBridge({
    required RuntimeEntity sourceEntity,
    required RuntimeEntity targetEntity,
    required Map<String, dynamic> sourceSelector,
    required Map<String, dynamic> targetSelector,
    required RuntimeEntity bridgeEntity,
    required Map<String, dynamic> payload,
  }) async {
    final source = await entityResolver.resolve(sourceEntity, sourceSelector);
    final target = await entityResolver.resolve(targetEntity, targetSelector);
    if (source.status != EntityResolutionStatus.resolved ||
        target.status != EntityResolutionStatus.resolved) {
      return RelationResolutionResult(
        status: RelationResolutionStatus.notFound,
        message: 'No se pudo resolver la asociación.',
      );
    }

    final sourceId = _idOf(source.record!);
    final targetId = _idOf(target.record!);
    if (sourceId == null || targetId == null) {
      return RelationResolutionResult(
        status: RelationResolutionStatus.invalid,
        message: 'La asociación no tiene IDs válidos.',
      );
    }

    final sourceFieldName = _entityIdFieldName(sourceEntity);
    final targetFieldName = _entityIdFieldName(targetEntity);

    final bridgePayload = <String, dynamic>{
      ...payload,
      sourceFieldName: sourceId,
      targetFieldName: targetId,
    };

    return RelationResolutionResult(
      status: RelationResolutionStatus.resolved,
      message: 'Bridge resuelto.',
      fieldName: bridgeEntity.name,
      valueId: sourceId,
      targetIds: [sourceId, targetId],
      operation: RelationOperation.set,
      payload: bridgePayload,
    );
  }

  Map<String, dynamic> _selectorFromText(String selector) {
    final cleaned = selector.trim();
    if (cleaned.isEmpty) return const {};
    return {'nombre': cleaned};
  }

  RuntimeEntity _targetEntityFor(RuntimeField field) {
    if (field.targetEntity != null && field.targetEntity!.isNotEmpty) {
      final entity = schema.entityByName(field.targetEntity!);
      if (entity != null) return entity;
    }
    return schema.entities.first;
  }

  RuntimeField? _inverseOwningFieldFor(RuntimeEntity sourceEntity, RuntimeField field) {
    if (!field.readOnly || field.owningSide == true) {
      return null;
    }
    for (final entity in schema.entities) {
      for (final candidate in entity.fields) {
        if (candidate.relation == true &&
            candidate.targetEntity == sourceEntity.name &&
            candidate.owningSide == true) {
          return candidate;
        }
      }
    }
    return null;
  }

  String _entityIdFieldName(RuntimeEntity entity) {
    final base = entity.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ').trim();
    if (base.isEmpty) return entity.idField;
    final lowered = base.toLowerCase();
    return '${lowered.replaceAll(RegExp(r'\s+'), '')}Id';
  }

  dynamic _idOf(Map<String, dynamic> record) {
    for (final key in ['id', '_id', 'uuid', 'Id', 'ID']) {
      final value = record[key];
      if (value != null) return value;
    }
    return null;
  }
}
