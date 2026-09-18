import '../../core/api/entity_resolver.dart';
import '../../core/api/relation_resolver.dart';
import '../../core/database/generic_repository.dart';
import '../../core/formatters/label_formatter.dart';
import '../../schema/model/runtime_schema.dart';
import 'command_intent.dart';
import 'command_execution_plan.dart';
import 'text_normalizer.dart';

class CommandExecutionResult {
  final bool success;
  final bool requiresConfirmation;
  final String message;
  final RuntimeEntity? entity;
  final Map<String, dynamic> body;
  const CommandExecutionResult({required this.success, required this.message, this.requiresConfirmation = false, this.entity, this.body = const {}});
}

class CommandExecutor {
  final GenericRepository repository;
  final RuntimeSchema schema;
  CommandExecutor({required this.schema, GenericRepository? repository}) : repository = repository ?? GenericRepository();

  Future<CommandExecutionPlan> buildPlan(CommandIntent intent) async {
    final entity = intent.entity;
    if (entity == null) {
      return CommandExecutionPlan(intent: intent, action: intent.action, status: CommandPlanStatus.invalid, blockingError: 'No reconocí la entidad.');
    }
    if (intent.action == CommandAction.unknown || intent.confidence < 0.5 || intent.ambiguities.isNotEmpty) {
      return CommandExecutionPlan(intent: intent, action: intent.action, entity: entity, status: CommandPlanStatus.invalid, blockingError: 'No pude interpretar con seguridad el comando.');
    }
    if (intent.sourceEntity != null && intent.targetEntity != null) return _buildRelationPlan(intent);

    Map<String, dynamic>? targetRecord;
    if (intent.action == CommandAction.update || intent.action == CommandAction.delete || intent.action == CommandAction.get) {
      if (intent.recordId == null) {
        return CommandExecutionPlan(intent: intent, action: intent.action, entity: entity, status: CommandPlanStatus.notFound, blockingError: 'Indica el registro real que deseas modificar.');
      }
      try {
        targetRecord = await repository.getById(entity, intent.recordId);
      } catch (_) {
        return CommandExecutionPlan(intent: intent, action: intent.action, entity: entity, status: CommandPlanStatus.notFound, blockingError: 'No existe el registro ${entity.name} #${intent.recordId}.');
      }
    }
    return CommandExecutionPlan(intent: intent, action: intent.action, entity: entity, targetRecord: targetRecord, scalarChanges: intent.values);
  }

  Future<CommandExecutionPlan> _buildRelationPlan(CommandIntent intent) async {
    final sourceEntity = intent.sourceEntity!;
    final targetEntity = intent.targetEntity!;
    if (intent.sourceSelector.isEmpty || intent.targetSelector.isEmpty) {
      return CommandExecutionPlan(intent: intent, action: intent.action, entity: sourceEntity, sourceEntity: sourceEntity, targetEntity: targetEntity, status: CommandPlanStatus.invalidRelation, blockingError: 'Faltan los selectores de origen o destino de la relación.');
    }
    final entityResolver = EntityResolver(repository: repository);
    final source = await entityResolver.resolve(sourceEntity, intent.sourceSelector);
    final target = await entityResolver.resolve(targetEntity, intent.targetSelector);
    final sourceStatus = _planStatus(source.status);
    if (sourceStatus != null) return CommandExecutionPlan(intent: intent, action: intent.action, entity: sourceEntity, sourceEntity: sourceEntity, targetEntity: targetEntity, status: sourceStatus, blockingError: '${sourceEntity.name}: ${source.message}');
    final targetStatus = _planStatus(target.status);
    if (targetStatus != null) return CommandExecutionPlan(intent: intent, action: intent.action, entity: sourceEntity, sourceEntity: sourceEntity, targetEntity: targetEntity, sourceRecord: source.record, status: targetStatus, blockingError: '${targetEntity.name}: ${target.message}');

    final sourceRecord = source.record!;
    final targetRecord = target.record!;
    final sourceId = sourceRecord[sourceEntity.idField];
    final targetId = targetRecord[targetEntity.idField];
    if (sourceId == null || targetId == null) {
      return CommandExecutionPlan(intent: intent, action: intent.action, entity: sourceEntity, sourceEntity: sourceEntity, targetEntity: targetEntity, sourceRecord: sourceRecord, relatedRecord: targetRecord, status: CommandPlanStatus.invalidRelation, blockingError: 'La relación no tiene IDs reales resueltos.');
    }

    final relationResolver = RelationResolver.withRepository(repository, schema);
    final bridgeEntity = _bridgeEntityFor(sourceEntity, targetEntity);
    if (bridgeEntity != null) {
      final bridge = await relationResolver.resolveAssociationBridge(sourceEntity: sourceEntity, targetEntity: targetEntity, sourceSelector: intent.sourceSelector, targetSelector: intent.targetSelector, bridgeEntity: bridgeEntity, payload: _explicitBridgePayload(intent.originalText, bridgeEntity));
      if (bridge.status != RelationResolutionStatus.resolved) {
        return CommandExecutionPlan(intent: intent, action: intent.action, entity: sourceEntity, sourceEntity: sourceEntity, targetEntity: targetEntity, bridgeEntity: bridgeEntity, sourceRecord: sourceRecord, relatedRecord: targetRecord, status: CommandPlanStatus.invalidRelation, blockingError: bridge.message);
      }
      return CommandExecutionPlan(intent: intent, action: intent.action, entity: bridgeEntity, sourceEntity: sourceEntity, targetEntity: targetEntity, bridgeEntity: bridgeEntity, sourceRecord: sourceRecord, relatedRecord: targetRecord, relationOperations: [CommandRelationOperation(operation: 'createBridge', sourceEntity: sourceEntity, targetEntity: targetEntity, bridgeEntity: bridgeEntity, sourceId: sourceId, targetId: targetId, payload: bridge.payload)], resolvedIds: {'source': sourceId, 'target': targetId});
    }

    final relationField = intent.relationValues.keys
        .map((name) => sourceEntity.fields.where((field) => field.name == name).firstOrNull)
        .whereType<RuntimeField>()
        .firstOrNull ??
      _relationFieldFor(sourceEntity, targetEntity);
    if (relationField == null) {
      return CommandExecutionPlan(intent: intent, action: intent.action, entity: sourceEntity, sourceEntity: sourceEntity, targetEntity: targetEntity, sourceRecord: sourceRecord, relatedRecord: targetRecord, status: CommandPlanStatus.invalidRelation, blockingError: 'El schema no define una relación válida entre ${sourceEntity.name} y ${targetEntity.name}.');
    }
    final operation = RelationOperationNormalizer.normalize(intent.originalText);
    final relation = await relationResolver.resolveField(sourceEntity: sourceEntity, field: relationField, sourceRecord: sourceRecord, selector: targetRecord[targetEntity.displayField]?.toString() ?? targetId.toString(), operation: operation);
    if (relation.status != RelationResolutionStatus.resolved) {
      return CommandExecutionPlan(intent: intent, action: intent.action, entity: sourceEntity, sourceEntity: sourceEntity, targetEntity: targetEntity, sourceRecord: sourceRecord, relatedRecord: targetRecord, status: CommandPlanStatus.invalidRelation, blockingError: relation.message);
    }
    final payload = relation.payload.isNotEmpty ? relation.payload : {relation.fieldName: relation.valueId};
    return CommandExecutionPlan(intent: intent, action: intent.action, entity: sourceEntity, sourceEntity: sourceEntity, targetEntity: targetEntity, sourceRecord: sourceRecord, relatedRecord: targetRecord, relationOperations: [CommandRelationOperation(operation: operation.name, sourceEntity: sourceEntity, targetEntity: targetEntity, field: relationField, sourceId: sourceId, targetId: targetId, payload: payload)], resolvedIds: {'source': sourceId, 'target': targetId});
  }

  CommandPlanStatus? _planStatus(EntityResolutionStatus status) {
    switch (status) {
      case EntityResolutionStatus.notFound: return CommandPlanStatus.notFound;
      case EntityResolutionStatus.ambiguous: return CommandPlanStatus.ambiguous;
      case EntityResolutionStatus.invalid: return CommandPlanStatus.invalid;
      case EntityResolutionStatus.resolved: return null;
    }
  }

  RuntimeEntity? _bridgeEntityFor(RuntimeEntity sourceEntity, RuntimeEntity targetEntity) {
    for (final entity in schema.entities) {
      final fields = entity.fields.where((field) => field.relation).toList();
      final hasSource = fields.any((field) => field.targetEntity == sourceEntity.name);
      final hasTarget = fields.any((field) => field.targetEntity == targetEntity.name);
      if (hasSource && hasTarget && entity.name != sourceEntity.name && entity.name != targetEntity.name) return entity;
    }
    return null;
  }

  RuntimeField? _relationFieldFor(RuntimeEntity sourceEntity, RuntimeEntity targetEntity) {
    for (final field in sourceEntity.fields) {
      if (field.relation && field.targetEntity == targetEntity.name) return field;
    }
    return null;
  }

  Map<String, dynamic> _explicitBridgePayload(String text, RuntimeEntity bridgeEntity) {
    final payload = <String, dynamic>{};
    for (final field in bridgeEntity.fields.where((field) => !field.relation && field.editable && !field.readOnly && field.name != bridgeEntity.idField)) {
      final label = field.name.replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (match) => '${match.group(1)} ${match.group(2)}');
      final match = RegExp('${RegExp.escape(label)}\\s+(\\d+(?:[.,]\\d+)?)', caseSensitive: false).firstMatch(text);
      if (match == null) continue;
      final raw = match.group(1)!;
      payload[field.requestField ?? field.name] = field.type == 'integer' ? int.parse(raw) : double.tryParse(raw.replaceAll(',', '.')) ?? raw;
    }
    return payload;
  }

  Future<CommandExecutionResult> execute(CommandIntent intent, {bool confirmDelete = false}) async {
    final plan = await buildPlan(intent);
    return executePlan(plan, confirmDelete: confirmDelete);
  }

  Future<CommandExecutionResult> executePlan(CommandExecutionPlan plan, {bool confirmDelete = false}) async {
    final intent = plan.intent;
    final entity = plan.entity;
    if (!plan.executable) return CommandExecutionResult(success: false, entity: entity, message: plan.blockingError);
    if (entity == null) return const CommandExecutionResult(success: false, message: 'No reconocí la entidad.');
    if (intent.action == CommandAction.unknown ||
        intent.confidence < 0.5 ||
        intent.ambiguities.isNotEmpty) {
      return const CommandExecutionResult(
        success: false,
        message: 'No pude interpretar con seguridad el comando.',
      );
    }
    if (plan.relationOperations.isNotEmpty) {
      return _executeRelationPlan(plan);
    }
    switch (intent.action) {
      case CommandAction.list:
        return CommandExecutionResult(success: true, message: 'Abrir ${entity.name}.', entity: entity);
      case CommandAction.get:
        if (intent.recordId == null) {
          return const CommandExecutionResult(
            success: false,
            message: 'Indica el ID del registro que deseas consultar.',
          );
        }
        try {
          final record = plan.targetRecord ?? await repository.getById(entity, intent.recordId);
          return CommandExecutionResult(
            success: true,
            message: 'Abrir ${entity.name}.',
            entity: entity,
            body: record,
          );
        } catch (_) {
          return CommandExecutionResult(
            success: false,
            entity: entity,
            message: 'No existe el registro ${entity.name} #${intent.recordId}.',
          );
        }
      case CommandAction.delete:
        if (intent.recordId == null) return const CommandExecutionResult(success: false, message: 'Indica el ID del registro que deseas eliminar.');
        if (!confirmDelete) return CommandExecutionResult(success: true, requiresConfirmation: true, entity: entity, message: '¿Eliminar ${entity.name} #${intent.recordId}?');
        await repository.delete(entity, intent.recordId);
        return CommandExecutionResult(success: true, entity: entity, message: 'Registro eliminado.');
      case CommandAction.create:
        return _write(intent, entity, create: true, resolvedRecord: plan.targetRecord);
      case CommandAction.update:
        if (intent.recordId == null) return const CommandExecutionResult(success: false, message: 'Indica el ID del registro que deseas editar.');
        return _write(intent, entity, create: false, resolvedRecord: plan.targetRecord);
      case CommandAction.unknown:
        return const CommandExecutionResult(success: false, message: 'No entendí el comando.');
    }
  }

  Future<CommandExecutionResult> _write(CommandIntent intent, RuntimeEntity entity, {required bool create, Map<String, dynamic>? resolvedRecord}) async {
    final body = <String, dynamic>{};
    final invalidKeys = <String>[];
    for (final entry in intent.values.entries) {
      final matchingFields = entity.fields.where((item) => item.name == entry.key || (item.requestField ?? item.name) == entry.key);
      final field = matchingFields.isEmpty ? null : matchingFields.first;
      if (field == null) {
        invalidKeys.add(entry.key);
        continue;
      }
      if (!_safeValueForField(intent.originalText, field, entry.value)) {
        return CommandExecutionResult(
          success: false,
          entity: entity,
          message: 'No inventes campos ni valores no mencionados en el comando.',
        );
      }
    }
    if (invalidKeys.isNotEmpty) {
      return CommandExecutionResult(
        success: false,
        entity: entity,
        message: 'Campo no permitido: ${invalidKeys.first}.',
      );
    }

    Map<String, dynamic>? current;
    if (!create) {
      try {
          current = resolvedRecord ?? await repository.getById(entity, intent.recordId);
      } catch (error) {
        return CommandExecutionResult(
          success: false,
          entity: entity,
          message: 'No existe el registro ${entity.name} #${intent.recordId}.',
        );
      }
    }
    for (final field in entity.fields.where((f) => f.editable && !f.readOnly && f.name != entity.idField)) {
      final requestField = field.requestField ?? field.name;
      if (current != null) {
        if (current.containsKey(requestField)) {
          body[requestField] = current[requestField];
        } else if (current.containsKey(field.name)) {
          body[requestField] = current[field.name];
        }
      }
      if (field.relation) {
        final text = intent.relationValues[field.name];
        if (text == null) continue;
        final target = schema.entityByName(field.targetEntity);
        if (target == null) return CommandExecutionResult(success: false, message: 'No encontré la entidad relacionada.');
        final records = await repository.getAll(target);
        final matches = records.where((record) {
          final display = '${record[target.displayField]}';
          return CommandTextNormalizer.normalize(display) == CommandTextNormalizer.normalize(text) ||
              CommandTextNormalizer.normalize(display).contains(CommandTextNormalizer.normalize(text));
        }).toList();
        if (matches.isEmpty) return CommandExecutionResult(success: false, message: "No encontré ${target.name} '$text'.");
        if (matches.length > 1) return CommandExecutionResult(success: false, message: "Encontré varias opciones para ${target.name} '$text'. Selecciona una.");
        final resolvedId = matches.single[target.idField];
        if (field.collection) {
          final currentValues = current?[requestField] is List ? List.from(current![requestField] as List) : <dynamic>[];
          final merged = [...currentValues, resolvedId];
          final unique = merged.toSet().toList();
          body[requestField] = unique;
        } else {
          body[requestField] = resolvedId;
        }
      } else if (intent.values.containsKey(field.name)) {
        body[requestField] = intent.values[field.name];
      }
    }
    if (create) {
      final missing = entity.fields
          .where((f) => f.required && f.editable && !f.readOnly && !f.collection && !body.containsKey(f.requestField ?? f.name))
          .map((f) => LabelFormatter.fromField(f.name))
          .toList();
      if (missing.isNotEmpty) {
        return CommandExecutionResult(success: false, message: 'Falta completar: ${missing.join(', ')}.');
      }
    }
    if (create) {
      await repository.create(entity, body);
    } else {
      await repository.update(entity, intent.recordId, body);
    }
    return CommandExecutionResult(success: true, entity: entity, body: body, message: create ? 'Registro creado.' : 'Registro actualizado.');
  }

  Future<CommandExecutionResult> _executeRelationPlan(CommandExecutionPlan plan) async {
    final operation = plan.relationOperations.single;
    if (operation.operation == 'createBridge') {
      final result = await repository.create(operation.bridgeEntity!, operation.payload);
      return CommandExecutionResult(success: true, entity: operation.bridgeEntity, body: result, message: 'Relación creada correctamente.');
    }
    final field = operation.field!;
    final current = plan.sourceRecord ?? const <String, dynamic>{};
    final requestField = field.requestField ?? field.name;
    final currentValue = current[requestField] ?? current[field.name];
    dynamic value = operation.payload[requestField] ?? operation.payload[field.name];
    final redirectedPayload = value == null && operation.payload.isNotEmpty ? operation.payload : null;
    if (field.collection) {
      final values = currentValue is List ? List<dynamic>.from(currentValue) : <dynamic>[];
      final targetId = operation.targetId;
      switch (RelationOperationNormalizer.normalize(plan.intent.originalText)) {
        case RelationOperation.add: if (!values.contains(targetId)) values.add(targetId); break;
        case RelationOperation.remove: values.removeWhere((item) => item.toString() == targetId.toString()); break;
        case RelationOperation.replace: values..clear()..add(targetId); break;
        default: if (!values.contains(targetId)) values.add(targetId);
      }
      value = values;
    }
    final body = redirectedPayload ?? {requestField: value};
    final result = await repository.update(operation.sourceEntity!, operation.sourceId, body);
    return CommandExecutionResult(success: true, entity: operation.sourceEntity, body: result.isEmpty ? body : result, message: 'Relación aplicada correctamente.');
  }

  bool _safeValueForField(String originalText, RuntimeField field, dynamic value) {
    final text = CommandTextNormalizer.normalize(originalText);
    final fieldText = CommandTextNormalizer.normalize(field.name);
    final labelText = CommandTextNormalizer.normalize(LabelFormatter.fromField(field.name));
    final matchesField = text.contains(fieldText) || text.contains(labelText);
    if (matchesField) return true;
    if (value == null) return false;
    final valueText = CommandTextNormalizer.normalize(value.toString());
    if (valueText.isEmpty) return false;
    return text.contains(valueText);
  }
}
