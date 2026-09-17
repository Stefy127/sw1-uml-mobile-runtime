import '../../core/database/generic_repository.dart';
import '../../core/formatters/label_formatter.dart';
import '../../schema/model/runtime_schema.dart';
import 'command_intent.dart';
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

  Future<CommandExecutionResult> execute(CommandIntent intent, {bool confirmDelete = false}) async {
    final entity = intent.entity;
    if (entity == null) return const CommandExecutionResult(success: false, message: 'No reconocí la entidad.');
    if (intent.action == CommandAction.unknown ||
        intent.confidence < 0.5 ||
        intent.ambiguities.isNotEmpty) {
      return const CommandExecutionResult(
        success: false,
        message: 'No pude interpretar con seguridad el comando.',
      );
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
          final record = await repository.getById(entity, intent.recordId);
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
        return _write(intent, entity, create: true);
      case CommandAction.update:
        if (intent.recordId == null) return const CommandExecutionResult(success: false, message: 'Indica el ID del registro que deseas editar.');
        return _write(intent, entity, create: false);
      case CommandAction.unknown:
        return const CommandExecutionResult(success: false, message: 'No entendí el comando.');
    }
  }

  Future<CommandExecutionResult> _write(CommandIntent intent, RuntimeEntity entity, {required bool create}) async {
    final body = <String, dynamic>{};
    Map<String, dynamic>? current;
    if (!create) {
      try {
        current = await repository.getById(entity, intent.recordId);
      } catch (error) {
        return CommandExecutionResult(
          success: false,
          entity: entity,
          message: 'No existe el registro ${entity.name} #${intent.recordId}.',
        );
      }
    }
    for (final field in entity.fields.where((f) => f.editable && !f.readOnly && !f.collection && f.name != entity.idField)) {
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
        final matches = records.where((record) => CommandTextNormalizer.normalize('${record[target.displayField]}') == CommandTextNormalizer.normalize(text)).toList();
        if (matches.isEmpty) return CommandExecutionResult(success: false, message: "No encontré ${target.name} '$text'.");
        if (matches.length > 1) return CommandExecutionResult(success: false, message: "Encontré varias opciones para ${target.name} '$text'. Selecciona una.");
        body[requestField] = matches.single[target.idField];
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
    if (create) await repository.create(entity, body); else await repository.update(entity, intent.recordId, body);
    return CommandExecutionResult(success: true, entity: entity, body: body, message: create ? 'Registro creado.' : 'Registro actualizado.');
  }
}
