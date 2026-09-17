import '../../schema/model/runtime_schema.dart';
import 'command_intent.dart';
import 'command_interpreter.dart';
import 'number_words.dart';
import 'text_normalizer.dart';

class LocalCommandInterpreter implements CommandInterpreter {
  CommandIntent interpret(String text, RuntimeSchema schema) {
    final normalized = CommandTextNormalizer.normalize(text);
    final command = _stripFillers(normalized);
    final action = _action(command);
    final entityMatch = _findEntity(command, schema);
    final entity = entityMatch?.entity;
    if (action == CommandAction.unknown || entity == null) {
      return CommandIntent(action: action, entity: entity, originalText: text, confidence: 0.2);
    }
    final recordId = _recordId(command, entity, entityMatch!.position, action);
    final values = <String, dynamic>{};
    final relations = <String, String>{};
    if (action == CommandAction.create || action == CommandAction.update) {
      _parseValues(text, entity, values, relations, action == CommandAction.create);
    }
    return CommandIntent(
      action: action,
      entity: entity,
      recordId: recordId,
      values: values,
      relationValues: relations,
      originalText: text,
      confidence: entityMatch.fuzzy ? 0.65 : 0.9,
    );
  }

  String _stripFillers(String text) => text
      .replaceFirst(RegExp(r'^(?:(?:por favor|quiero(?: que)?|necesito|podrias|me puedes|me podrias)\s+)+'), '')
      .trim();

  CommandAction _action(String text) {
    if (RegExp(r'^(crear|crea|creame|registrar|registra|registrame|agrega|agregar|anade|anadir|nuevo|nueva|dar de alta)\b').hasMatch(text)) return CommandAction.create;
    if (RegExp(r'^(editar|edita|modificar|modifica|actualizar|actualiza|cambiar|cambia|poner|pon|ponle|asignar|asigna)\b').hasMatch(text)) return CommandAction.update;
    if (RegExp(r'^(eliminar|elimina|borrar|borra|quitar|quita|dar de baja)\b').hasMatch(text)) return CommandAction.delete;
    if (RegExp(r'^(listar|lista|mostrar|muestra|muestrame|ver|ensenar|ensena|dame|mostrame)\b').hasMatch(text)) {
      return text.contains(RegExp(r'\b(?:\d+|numero|uno|una|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce|trece|catorce|quince|veinte|treinta|cuarenta|cincuenta|sesenta|setenta|ochenta|noventa)\b')) ? CommandAction.get : CommandAction.list;
    }
    if (RegExp(r'^(buscar|busca|consultar|consulta)\b').hasMatch(text) || text.startsWith('obtener ') || text.startsWith('ver detalle ')) return CommandAction.get;
    return CommandAction.unknown;
  }

  _EntityMatch? _findEntity(String text, RuntimeSchema schema) {
    final subject = text
        .replaceFirst(RegExp(r'^(?:crear|crea|creame|registrar|registra|registrame|agrega|agregar|anade|anadir|nuevo|nueva|editar|edita|modificar|modifica|actualizar|actualiza|cambiar|cambia|poner|pon|ponle|asignar|asigna|eliminar|elimina|borrar|borra|quitar|quita|listar|lista|mostrar|muestra|muestrame|ver|ensenar|ensena|dame|mostrame|buscar|busca|consultar|consulta|dar de alta|dar de baja)\s+'), '')
        .replaceFirst(RegExp(r'^(?:una?|unos?|unas?|los?|las?)\s+'), '');
    RuntimeEntity? exact;
    var exactPosition = 1 << 30;
    for (final candidate in schema.entities) {
      final name = CommandTextNormalizer.normalize(candidate.name);
      for (final option in [name, '${name}s']) {
        final position = subject.indexOf(option);
        if (position >= 0 && position < exactPosition && _wordBoundary(subject, position, option.length)) {
          exact = candidate;
          exactPosition = position;
        }
      }
    }
    if (exact != null) return _EntityMatch(exact, exactPosition, false);
    RuntimeEntity? fuzzy;
    var fuzzyPosition = 1 << 30;
    for (final candidate in schema.entities) {
      final name = CommandTextNormalizer.singular(CommandTextNormalizer.normalize(candidate.name));
      for (final word in RegExp(r'[a-z0-9_-]+').allMatches(subject)) {
        if (_distance(CommandTextNormalizer.singular(word.group(0)!), name) <= 1 && word.start < fuzzyPosition) {
          fuzzy = candidate;
          fuzzyPosition = word.start;
        }
      }
    }
    return fuzzy == null ? null : _EntityMatch(fuzzy, fuzzyPosition, true);
  }

  bool _wordBoundary(String text, int start, int length) {
    final before = start == 0 ? ' ' : text[start - 1];
    final end = start + length;
    final after = end >= text.length ? ' ' : text[end];
    return !RegExp(r'[a-z0-9]').hasMatch(before) && !RegExp(r'[a-z0-9]').hasMatch(after);
  }

  dynamic _recordId(String text, RuntimeEntity entity, int entityPosition, CommandAction action) {
    if (action != CommandAction.update && action != CommandAction.delete && action != CommandAction.get) return null;
    final number = RegExp(r'\b(?:numero|nro)\s+(\d+|[a-z]+(?:\s+y\s+[a-z]+)?)\b').firstMatch(text);
    if (number != null) return _parseNumber(number.group(1)!);
    final exactPosition = text.indexOf(CommandTextNormalizer.normalize(entity.name));
    final start = exactPosition >= 0 ? exactPosition : entityPosition;
    final numeric = RegExp(r'\b(\d+|[a-z]+(?:\s+y\s+[a-z]+)?)\b').firstMatch(text.substring(start + CommandTextNormalizer.normalize(entity.name).length));
    return numeric == null ? null : _parseNumber(numeric.group(1)!);
  }

  dynamic _parseNumber(String value) => int.tryParse(value) ?? SpanishNumberWords.parse(value);

  void _parseValues(String text, RuntimeEntity entity, Map<String, dynamic> values, Map<String, String> relations, bool allowImplicitDisplay) {
    final fields = entity.fields.where((field) => field.editable && !field.readOnly && !field.collection && field.name != entity.idField);
    for (final field in fields) {
      final names = <String>{CommandTextNormalizer.normalize(field.name), CommandTextNormalizer.normalize(_label(field.name))}.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final name in names) {
        final raw = _captureValue(text, name, field.type);
        if (raw == null || raw.isEmpty) continue;
        if (field.relation) relations[field.name] = raw; else values[field.name] = _value(raw, field.type);
        break;
      }
    }
    if (allowImplicitDisplay && entity.displayField.isNotEmpty && !values.containsKey(entity.displayField)) {
      final display = _implicitDisplay(text, entity);
      if (display != null && display.isNotEmpty) values[entity.displayField] = display;
    }
  }

  String? _captureValue(String text, String fieldName, String type) {
    final expected = fieldName.split(RegExp(r'\s+'));
    final tokens = RegExp(r'\S+').allMatches(text).toList();
    for (var i = 0; i + expected.length <= tokens.length; i++) {
      final matches = List.generate(expected.length, (offset) => CommandTextNormalizer.normalize(tokens[i + offset].group(0)!) == expected[offset]).every((match) => match);
      if (!matches) continue;
      var remaining = text.substring(tokens[i + expected.length - 1].end);
      remaining = remaining.replaceFirst(RegExp(r'^\s+(?:a\s+|igual\s+a\s+|en\s+)', caseSensitive: false), ' ');
      final afterId = RegExp(r'\b\d+\s+a\s+(.+)$', caseSensitive: false).firstMatch(remaining);
      if (afterId != null) return afterId.group(1)!.trim();
      final delimiter = RegExp(r'\s+(?:con|y|cambiar|modificar|para|asociada\s+a)\s+', caseSensitive: false).firstMatch(remaining);
      final value = remaining.substring(0, delimiter?.start ?? remaining.length).trim();
      if (value.isNotEmpty &&
          (!_isNumeric(type) || _parseNumber(value) != null || double.tryParse(value.replaceAll(',', '.')) != null)) return value;
      if (_isNumeric(type) && i > 0) {
        for (var start = i - 1; start >= 0 && start >= i - 3; start--) {
          final candidate = text.substring(tokens[start].start, tokens[i].start).trim().replaceFirst(RegExp(r'^(?:con|de|a|en)\s+', caseSensitive: false), '');
          if (_parseNumber(candidate) != null) return candidate;
        }
      }
    }
    return null;
  }

  bool _isNumeric(String type) => type == 'integer' || type == 'decimal';

  String? _implicitDisplay(String text, RuntimeEntity entity) {
    final match = RegExp(RegExp.escape(entity.name), caseSensitive: false).firstMatch(text);
    if (match == null) return null;
    var value = text.substring(match.end).trim().replaceFirst(RegExp(r'^(?:llamada|llamado|de\s+nombre|nombre)\s+', caseSensitive: false), '');
    final end = RegExp(r'\s+(?:con|para|en\s+la|asociada\s+a|de)\s+', caseSensitive: false).firstMatch(value);
    return value.substring(0, end?.start ?? value.length).trim();
  }

  dynamic _value(String raw, String type) {
    switch (type) {
      case 'integer': return _parseNumber(raw);
      case 'decimal': return double.tryParse(raw.replaceAll(',', '.'));
      case 'boolean': return ['true', 'si', 'yes', 'activo', 'verdadero'].contains(CommandTextNormalizer.normalize(raw));
      default: return raw;
    }
  }

  int _distance(String a, String b) {
    final row = List<int>.generate(b.length + 1, (index) => index);
    for (var i = 1; i <= a.length; i++) {
      var previous = row[0]; row[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final current = row[j];
        row[j] = a[i - 1] == b[j - 1] ? previous : 1 + [previous, row[j], row[j - 1]].reduce((x, y) => x < y ? x : y);
        previous = current;
      }
    }
    return row[b.length];
  }

  String _label(String value) {
    var result = value.replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (match) => '${match.group(1)} ${match.group(2)}');
    if (result.toLowerCase().endsWith(' id')) result = result.substring(0, result.length - 3).trim();
    return result;
  }
}

class _EntityMatch {
  final RuntimeEntity entity;
  final int position;
  final bool fuzzy;
  const _EntityMatch(this.entity, this.position, this.fuzzy);
}
