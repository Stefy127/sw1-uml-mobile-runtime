import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../schema/model/runtime_schema.dart';
import 'command_intent.dart';

class LlmIntentParser {
  const LlmIntentParser();

  CommandIntent parse(String raw, String originalText, RuntimeSchema schema) {
    final json = _decodeJson(raw);
    if (json == null) return _invalid(originalText, 'JSON inválido');
    final actionName = '${json['action'] ?? ''}'.toLowerCase();
    final action = _actions[actionName];
    final entityName = json['entity']?.toString();
    final entity = schema.entityByName(entityName);
    final rawAmbiguities = json['ambiguities'] is List
        ? (json['ambiguities'] as List).map((value) => value.toString()).toList()
        : const <String>[];
    final ambiguities = _normalizeAmbiguities(rawAmbiguities);
    if (action == null) ambiguities.add('action desconocida');
    if (entity == null) ambiguities.add('entidad no encontrada');
    if (ambiguities.isNotEmpty) {
      return CommandIntent(
        action: action ?? CommandAction.unknown,
        entity: entity,
        recordId: _recordId(json['recordId']),
        originalText: originalText,
        confidence: 0.1,
        ambiguities: ambiguities,
      );
    }

    final values = <String, dynamic>{};
    final relations = <String, String>{};
    final fields = {for (final field in entity!.fields) field.name: field};
    final rawValues = json['values'] is Map ? Map<Object?, Object?>.from(json['values'] as Map) : const <Object?, Object?>{};
    for (final entry in rawValues.entries) {
      final field = fields[entry.key?.toString()];
      if (field == null) {
        ambiguities.add('campo no permitido: ${entry.key}');
        continue;
      }
      if (!_editable(field, entity)) {
        ambiguities.add('campo no editable: ${field.name}');
        continue;
      }
      final value = _valueForField(entry.value, field);
      if (value != null) {
        values[field.name] = value;
      } else if (entry.value != null) {
        ambiguities.add('tipo inválido: ${field.name}');
      }
    }
    final rawRelations = json['relations'] is Map ? Map<Object?, Object?>.from(json['relations'] as Map) : const <Object?, Object?>{};
    for (final entry in rawRelations.entries) {
      final field = fields[entry.key?.toString()];
      if (field == null) {
        ambiguities.add('relación no permitida: ${entry.key}');
        continue;
      }
      if (!_editable(field, entity) || !field.relation) {
        ambiguities.add('relación no editable: ${field.name}');
        continue;
      }
      if (entry.value != null && entry.value.toString().trim().isNotEmpty) {
        relations[field.name] = entry.value.toString().trim();
      }
    }
    final confidence = _confidence(json['confidence']);
    final recordId = _recordId(json['recordId']);
    final normalizedAction = action!;
    if ((normalizedAction == CommandAction.get || normalizedAction == CommandAction.update || normalizedAction == CommandAction.delete) && recordId == null) {
      ambiguities.add('recordId requerido');
    }
    if (normalizedAction == CommandAction.list && recordId != null) {
      ambiguities.add('list no acepta recordId');
    }
    if (normalizedAction == CommandAction.get) {
      if (values.isNotEmpty || relations.isNotEmpty) {
        ambiguities.add('get no acepta values ni relations');
        values.clear();
        relations.clear();
      }
    }
    if (normalizedAction == CommandAction.list) {
      if (values.isNotEmpty || relations.isNotEmpty) {
        ambiguities.add('list no acepta values ni relations');
        values.clear();
        relations.clear();
      }
    }
    return CommandIntent(
      action: normalizedAction,
      entity: entity,
      recordId: recordId,
      values: values,
      relationValues: relations,
      originalText: originalText,
      confidence: ambiguities.isEmpty ? confidence : 0.1,
      ambiguities: ambiguities,
    );
  }

  List<String> _normalizeAmbiguities(List<String> values) {
    const generic = {
      'unknown',
      'none',
      'null',
      'n/a',
      '',
      'sin ambigüedad',
      'sin ambiguedad',
      'ninguna',
    };
    final normalized = <String>[];
    for (final value in values) {
      final clean = value.trim().toLowerCase();
      if (generic.contains(clean)) {
        if (clean.isNotEmpty) {
          debugPrint('LLM ambiguities normalized: ["$value"] -> []');
        }
        continue;
      }
      normalized.add(value.trim());
    }
    return normalized;
  }

  Map<String, dynamic>? _decodeJson(String raw) {
    final trimmed = raw
        .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
        .trim();
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start < 0 || end <= start) {
      debugPrint('LLM PARSE FAILED: no JSON object found');
      return null;
    }
    try {
      final value = jsonDecode(trimmed.substring(start, end + 1));
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } catch (error) {
      debugPrint('LLM PARSE FAILED: $error');
      return null;
    }
  }

  bool _editable(RuntimeField field, RuntimeEntity entity) =>
      field.name != entity.idField && field.editable && !field.readOnly && !field.collection;

  dynamic _valueForField(dynamic value, RuntimeField field) {
    if (value == null) return null;
    switch (field.type.toLowerCase()) {
      case 'integer':
        return value is int ? value : int.tryParse(value.toString());
      case 'decimal':
        return value is num ? value : double.tryParse(value.toString().replaceAll(',', '.'));
      case 'boolean':
        if (value is bool) return value;
        final text = value.toString().toLowerCase();
        if (text == 'true' || text == 'sí' || text == 'si') return true;
        if (text == 'false' || text == 'no') return false;
        return null;
      default:
        return value.toString();
    }
  }

  dynamic _recordId(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return int.tryParse(text) ?? (text.isEmpty ? null : text);
  }

  double _confidence(dynamic value) {
    if (value is num) return value.toDouble().clamp(0.0, 1.0);
    switch ('$value'.toLowerCase()) {
      case 'high': return 0.95;
      case 'medium': return 0.7;
      case 'low': return 0.3;
      default: return 0.3;
    }
  }

  CommandIntent _invalid(String text, String reason) => CommandIntent(
        action: CommandAction.unknown,
        entity: null,
        originalText: text,
        confidence: 0,
        ambiguities: [reason],
      );

  static const _actions = <String, CommandAction>{
    'create': CommandAction.create,
    'update': CommandAction.update,
    'delete': CommandAction.delete,
    'list': CommandAction.list,
    'get': CommandAction.get,
  };
}
