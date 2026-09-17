import '../../schema/model/runtime_schema.dart';
import 'command_intent.dart';
import 'text_normalizer.dart';

class LocalCommandInterpreter {
  CommandIntent interpret(String text, RuntimeSchema schema) {
    final normalized = CommandTextNormalizer.normalize(text);
    final action = _action(normalized);
    final entity = _entity(normalized, schema);
    if (action == CommandAction.unknown || entity == null) {
      return CommandIntent(
        action: action,
        entity: entity,
        originalText: text,
        confidence: 0.2,
      );
    }

    final normalizedRemainder = _remainder(normalized, entity);
    final originalRemainder = _originalRemainder(text, entity);
    dynamic recordId;
    if (action == CommandAction.update ||
        action == CommandAction.delete ||
        action == CommandAction.get) {
      final match = RegExp(
        r'^(\d+|local-[a-z0-9_-]+|temp-[a-z0-9_-]+)',
      ).firstMatch(normalizedRemainder);
      if (match != null) {
        recordId = int.tryParse(match.group(1)!) ?? match.group(1);
      }
    }

    final values = <String, dynamic>{};
    final relations = <String, String>{};
    if (action == CommandAction.create || action == CommandAction.update) {
      _parseValues(originalRemainder, entity, values, relations);
    }
    return CommandIntent(
      action: action,
      entity: entity,
      recordId: recordId,
      values: values,
      relationValues: relations,
      originalText: text,
      confidence: 0.9,
    );
  }

  CommandAction _action(String text) {
    if (RegExp(r'^(crear|crea|agrega|agregar|anade|nuevo|nueva)\b').hasMatch(text)) {
      return CommandAction.create;
    }
    if (RegExp(r'^(editar|edita|modificar|modifica|cambiar|cambia)\b').hasMatch(text)) {
      return CommandAction.update;
    }
    if (RegExp(r'^(eliminar|elimina|borrar|borra)\b').hasMatch(text)) {
      return CommandAction.delete;
    }
    if (RegExp(r'^(listar|lista|mostrar|muestra|ver)\b').hasMatch(text)) {
      return CommandAction.list;
    }
    if (text.startsWith('obtener ') || text.startsWith('ver detalle ')) {
      return CommandAction.get;
    }
    return CommandAction.unknown;
  }

  RuntimeEntity? _entity(String text, RuntimeSchema schema) {
    final subject = text
        .replaceFirst(
          RegExp(r'^(crear|crea|agrega|agregar|anade|nuevo|nueva|editar|edita|modificar|modifica|cambiar|cambia|eliminar|elimina|borrar|borra|listar|lista|mostrar|muestra|ver)\s+',),
          '',
        )
        .replaceFirst(RegExp(r'^(una?|unos?|unas?)\s+'), '');
    for (final entity in schema.entities) {
      final name = CommandTextNormalizer.normalize(entity.name);
      final pattern = '^${RegExp.escape(name)}s?(?:\\s|' + r'$)';
      if (RegExp(pattern).hasMatch(subject)) {
        return entity;
      }
    }
    return null;
  }

  String _remainder(String text, RuntimeEntity entity) {
    final name = CommandTextNormalizer.normalize(entity.name);
    return text
        .replaceFirst(RegExp('^.*?\\b${RegExp.escape(name)}s?\\b'), '')
        .trim();
  }

  String _originalRemainder(String text, RuntimeEntity entity) {
    final name = RegExp.escape(entity.name);
    return text
        .replaceFirst(
          RegExp('^.*?\\b$name' r's?\\b', caseSensitive: false),
          '',
        )
        .trim();
  }

  void _parseValues(
    String text,
    RuntimeEntity entity,
    Map<String, dynamic> values,
    Map<String, String> relations,
  ) {
    final fields = entity.fields
        .where(
          (field) =>
              field.editable &&
              !field.readOnly &&
              !field.collection &&
              field.name != entity.idField,
        )
        .toList();
    for (final field in fields) {
      final names = [
        CommandTextNormalizer.normalize(field.name),
        CommandTextNormalizer.normalize(_label(field.name)),
      ]..sort((a, b) => b.length.compareTo(a.length));
      for (final name in names) {
        final raw = _captureValue(text, name);
        if (raw == null || raw.isEmpty) continue;
        if (field.relation) {
          relations[field.name] = raw;
        } else {
          values[field.name] = _value(raw, field.type);
        }
        break;
      }
    }
    if (entity.displayField.isNotEmpty &&
        !values.containsKey(entity.displayField)) {
      final called = RegExp(
        r'(?:llamada|llamado)\s+(.+?)(?=\s+con\s+|$)',
        caseSensitive: false,
      ).firstMatch(text);
      if (called != null) {
        values[entity.displayField] = called.group(1)!.trim();
      }
    }
  }

  String? _captureValue(String text, String fieldName) {
    final expectedTokens = fieldName.split(RegExp(r'\s+'));
    final tokens = RegExp(r'\S+').allMatches(text).toList();
    Match? field;
    for (var i = 0; i + expectedTokens.length <= tokens.length; i++) {
      final matches = List.generate(
        expectedTokens.length,
        (offset) => CommandTextNormalizer.normalize(
              tokens[i + offset].group(0)!,
            ) ==
            expectedTokens[offset],
      ).every((match) => match);
      if (matches) {
        field = tokens[i + expectedTokens.length - 1];
        break;
      }
    }
    if (field == null) return null;

    var remaining = text.substring(field.end);
    remaining = remaining.replaceFirst(
      RegExp(r'^\s+(?:a\s+|igual\s+a\s+)', caseSensitive: false),
      ' ',
    );
    final delimiter = RegExp(
      r'\s+(?:con|y|cambiar|modificar)\s+',
      caseSensitive: false,
    ).firstMatch(remaining);
    return remaining
        .substring(0, delimiter?.start ?? remaining.length)
        .trim();
  }

  dynamic _value(String raw, String type) {
    switch (type) {
      case 'integer':
        return int.tryParse(raw);
      case 'decimal':
        return double.tryParse(raw.replaceAll(',', '.'));
      case 'boolean':
        return ['true', 'si', 'yes', 'activo']
            .contains(CommandTextNormalizer.normalize(raw));
      default:
        return raw;
    }
  }

  String _label(String value) {
    var result = value.replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    );
    if (result.toLowerCase().endsWith(' id')) {
      result = result.substring(0, result.length - 3).trim();
    }
    return result;
  }
}
