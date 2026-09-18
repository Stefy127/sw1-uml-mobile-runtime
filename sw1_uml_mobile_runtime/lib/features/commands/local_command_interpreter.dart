import '../../schema/model/runtime_schema.dart';
import 'command_intent.dart';
import 'command_interpreter.dart';
import 'number_words.dart';
import 'text_normalizer.dart';

class LocalCommandInterpreter extends CommandInterpreter {
  @override
  CommandIntent interpret(String text, RuntimeSchema schema) {
    final originalText = text;
    final normalized = CommandTextNormalizer.normalize(originalText);
    final command = _stripFillers(normalized);
    final action = _action(command);

    final relationContext = _detectRelationContext(originalText, schema);
    if (relationContext != null) {
      final sourceEntity = relationContext.sourceEntity;
      final targetEntity = relationContext.targetEntity;
      return CommandIntent(
          action: CommandAction.update,
          entity: sourceEntity,
          sourceEntity: sourceEntity,
          targetEntity: targetEntity,
          sourceSelector: relationContext.sourceSelector,
          targetSelector: relationContext.targetSelector,
          relationOperation: relationContext.operation,
          recordId: null,
          values: const {},
          relationValues: relationContext.relationValues,
          originalText: originalText,
          confidence: 0.9,
        );
    }

    final entityMatch = _findEntity(command, schema);
    final entity = entityMatch?.entity;
    if (action == CommandAction.unknown || entity == null) {
      return CommandIntent(action: action, entity: entity, originalText: originalText, confidence: 0.2);
    }
    final recordId = _recordId(originalText, entity, entityMatch!.position, action);
    final values = <String, dynamic>{};
    final relations = <String, String>{};
    if (action == CommandAction.create || action == CommandAction.update) {
      _parseValues(originalText, entity, values, relations, action == CommandAction.create, schema);
    }
    return CommandIntent(
      action: action,
      entity: entity,
      recordId: recordId,
      values: values,
      relationValues: relations,
      originalText: originalText,
      confidence: entityMatch.fuzzy ? 0.65 : 0.9,
    );
  }

  String _stripFillers(String text) => text
      .replaceFirst(RegExp(r'^(?:(?:por favor|quiero(?: que)?|necesito|podrias|me puedes|me podrias)\s+)+'), '')
      .trim();

  CommandAction _action(String text) {
    if (RegExp(r'^(eliminar|elimina|borrar|borra|quitar|quita|dar de baja)\b').hasMatch(text)) return CommandAction.delete;
    if (RegExp(r'^(crear|crea|creame|registrar|registra|registrame|agrega|agregar|anade|anadir|nuevo|nueva|dar de alta)\b').hasMatch(text)) return CommandAction.create;
    if (RegExp(r'^(editar|edita|modificar|modifica|actualizar|actualiza|cambiar|cambia|poner|pon|ponle|asignar|asigna|asocia|relaciona|vincula|relacionar|desasocia|desvincula|desrelaciona|quita|quitar|elimina|eliminar|borrar|borra)\b').hasMatch(text) ||
        RegExp(r'^(?:asocia|relaciona|vincula|asigna|agrega\s+a|agrega|anade|añade|quita\s+de|desasocia|desvincula|desrelaciona)\b').hasMatch(text)) {
      return CommandAction.update;
    }
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

  _RelationContext? _detectRelationContext(String text, RuntimeSchema schema) {
    final relationPattern = RegExp(
      r'(?:asocia|relaciona|vincula|asigna|agrega|añade|suma|quita|desasocia|desvincula|desrelaciona)\b',
      caseSensitive: false,
    );
    if (!relationPattern.hasMatch(text)) return null;

    final recursive = _detectRecursiveRelation(text, schema);
    if (recursive != null) return recursive;

    final matches = <_EntityMatch>[];
    final normalizedText = CommandTextNormalizer.normalize(text);
    for (final candidate in schema.entities) {
      final normalizedName = CommandTextNormalizer.normalize(candidate.name);
      final position = normalizedText.indexOf(normalizedName);
      if (position >= 0) {
        matches.add(_EntityMatch(candidate, position, false));
      }
    }
    if (matches.isEmpty) return null;

    RuntimeEntity? sourceEntity;
    RuntimeEntity? targetEntity;
    if (matches.length > 1) {
      for (final sourceMatch in matches) {
        for (final targetMatch in matches) {
          if (sourceMatch.entity == targetMatch.entity) continue;
          if (_relationFieldFor(sourceMatch.entity, targetMatch.entity) != null) {
            sourceEntity = sourceMatch.entity;
            targetEntity = targetMatch.entity;
            break;
          }
        }
        if (sourceEntity != null) break;
      }
    }
    final resolvedTarget = targetEntity ?? matches.reduce((a, b) => a.position > b.position ? a : b).entity;
    final resolvedSource = sourceEntity ?? _inferSourceEntityForTarget(resolvedTarget, schema);
    if (resolvedSource == null) return null;
    final relationField = _relationFieldFor(resolvedSource, resolvedTarget);
    final bridge = schema.entities.where((entity) => _isAssociationBridge(entity, schema)).where((entity) {
      final targets = entity.fields.where((field) => field.relation).map((field) => field.targetEntity).toSet();
      return targets.contains(resolvedSource.name) && targets.contains(resolvedTarget.name);
    }).firstOrNull;
    if (relationField == null && bridge == null) return null;

    final sourceSelector = relationField == null
        ? _selectorFromRelationPart(text, resolvedSource, beforeConnector: true)
        : _selectorFromText(text, resolvedSource, resolvedTarget, resolvedSource == resolvedTarget);
    final targetSelector = relationField == null
        ? _selectorFromRelationPart(text, resolvedTarget, beforeConnector: false)
        : _selectorFromText(text, resolvedTarget, resolvedSource, resolvedSource == resolvedTarget);
    if (sourceSelector.isEmpty || targetSelector.isEmpty) return null;

    final targetDisplay = targetSelector[resolvedTarget.displayField];
    final targetValue = targetDisplay is String ? targetDisplay : (targetSelector.values.isNotEmpty ? targetSelector.values.first : null);
    return _RelationContext(
      sourceEntity: resolvedSource,
      targetEntity: resolvedTarget,
      operation: 'add',
      sourceSelector: sourceSelector,
      targetSelector: targetSelector,
      relationValues: relationField == null ? const {} : {relationField.name: (targetValue ?? '').toString().trim()},
    );
  }

  Map<String, dynamic> _selectorFromRelationPart(String text, RuntimeEntity entity, {required bool beforeConnector}) {
    final parts = text.split(RegExp(r'\s+(?:con|a la|al|de|del)\s+', caseSensitive: false));
    if (parts.length < 2) return const {};
    var value = (beforeConnector ? parts.first : parts.last).trim();
    value = value.replaceFirst(RegExp(r'^(?:asocia|asociar|relaciona|relacionar|vincula|vincular|la|el|los|las|una?|un)\s+', caseSensitive: false), '').trim();
    final entityLabel = CommandTextNormalizer.normalize(entity.name);
    final normalizedValue = CommandTextNormalizer.normalize(value);
    if (!beforeConnector && normalizedValue.startsWith(entityLabel)) {
      value = value.substring(entityLabel.length).trim();
    }
    return value.isEmpty ? const {} : {entity.displayField: value};
  }

  _RelationContext? _detectRecursiveRelation(String text, RuntimeSchema schema) {
    for (final entity in schema.entities) {
      for (final field in entity.fields.where((candidate) => candidate.relation && candidate.targetEntity == entity.name)) {
        final fieldLabel = _label(field.name);
        final singularLabel = CommandTextNormalizer.singular(fieldLabel);
        final feminineLabel = singularLabel.endsWith('o') ? '${singularLabel.substring(0, singularLabel.length - 1)}a' : singularLabel;
        final fieldPattern = '(?:${RegExp.escape(fieldLabel)}|${RegExp.escape(singularLabel)}|${RegExp.escape(feminineLabel)})';
        final match = RegExp(
          '(?:asigna|asignar|agrega|agregar|anade|añade)\\s+a?\\s*(.+?)\\s+como\\s+$fieldPattern\\s+de\\s+(.+)\$',
          caseSensitive: false,
        ).firstMatch(text);
        if (match == null) continue;
        final first = match.group(1)?.trim();
        final second = match.group(2)?.trim();
        if (first == null || second == null || first.isEmpty || second.isEmpty) continue;
        final fieldText = CommandTextNormalizer.normalize(field.name);
        final sourceText = fieldText.contains('jefe') ? second : first;
        final targetText = fieldText.contains('jefe') ? first : second;
        final sourceSelector = {entity.displayField: _cleanSelectorValue(sourceText)};
        final targetSelector = {entity.displayField: _cleanSelectorValue(targetText)};
        return _RelationContext(
          sourceEntity: entity,
          targetEntity: entity,
          operation: 'set',
          sourceSelector: sourceSelector,
          targetSelector: targetSelector,
          relationValues: {field.name: targetSelector[entity.displayField] ?? ''},
        );
      }
    }
    return null;
  }

  String _cleanSelectorValue(String value) => value
      .replaceFirst(RegExp(r'^(?:el|la|los|las|un|una|unos|unas)\s+', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  RuntimeEntity? _inferSourceEntityForTarget(RuntimeEntity targetEntity, RuntimeSchema schema) {
    for (final candidate in schema.entities) {
      if (_isAssociationBridge(candidate, schema)) continue;
      for (final field in candidate.fields) {
        if (field.relation && field.targetEntity == targetEntity.name) {
          return candidate;
        }
      }
    }
    for (final bridge in schema.entities.where((entity) => _isAssociationBridge(entity, schema))) {
      final endpoint = bridge.fields
          .where((field) => field.relation && field.targetEntity != targetEntity.name)
          .map((field) => schema.entityByName(field.targetEntity))
          .whereType<RuntimeEntity>()
          .firstOrNull;
      if (endpoint != null) return endpoint;
    }
    return null;
  }

  bool _isAssociationBridge(RuntimeEntity entity, RuntimeSchema schema) {
    final targets = entity.fields
        .where((field) => field.relation && field.targetEntity != null)
        .map((field) => field.targetEntity)
        .whereType<String>()
        .toSet();
    return targets.length >= 2 && targets.every((target) => schema.entityByName(target) != null);
  }

  RuntimeField? _relationFieldFor(RuntimeEntity sourceEntity, RuntimeEntity targetEntity) {
    for (final field in sourceEntity.fields) {
      if (field.relation && field.targetEntity == targetEntity.name) return field;
    }
    return null;
  }

  Map<String, dynamic> _selectorFromText(String text, RuntimeEntity entity, RuntimeEntity? otherEntity, bool selfReference) {
    final displayField = entity.displayField;
    final normalizedText = CommandTextNormalizer.normalize(text);
    final entityKey = CommandTextNormalizer.normalize(entity.name);
    final normalizedIndex = normalizedText.indexOf(entityKey);
    final entityMatch = RegExp(RegExp.escape(entity.name), caseSensitive: false).firstMatch(text);
    if (normalizedIndex >= 0 || entityMatch != null) {
      final tail = normalizedIndex >= 0
          ? text.substring(normalizedIndex + entityKey.length)
          : text.substring(entityMatch!.end);
        final value = tail.split(RegExp(r'\s+(?:con|a la|al|de|del|como|y)\s+', caseSensitive: false)).first;
        final clean = value
          .replaceFirst(RegExp(r'^(?:con|a la|al|de|del|como|y|la|el|los|las|un|una|unos|unas)\s+', caseSensitive: false), '')
          .trim();
      if (clean.isNotEmpty) {
        return {displayField: clean.replaceAll(RegExp(r'\s+'), ' ').trim()};
      }
    }

    final splitPattern = RegExp(r'\b(?:con|a la|al|de|del|como|y)\b', caseSensitive: false);
    final parts = text.split(splitPattern);
    if (parts.isNotEmpty) {
      final rawCandidate = selfReference
          ? parts.isNotEmpty ? parts.last : ''
          : parts.firstWhere((part) => part.trim().isNotEmpty && part.trim().length > 3, orElse: () => '');
      final clean = rawCandidate
          .replaceFirst(RegExp(r'^(?:asocia|relaciona|vincula|asigna|agrega|añade|suma|quita|desasocia|desvincula|desrelaciona|la|el|los|las|con|a|de|del|al|como)\s+', caseSensitive: false), '')
          .trim();
      if (clean.isNotEmpty) {
        return {displayField: clean.replaceAll(RegExp(r'\s+'), ' ').trim()};
      }
    }
    return {};
  }

  bool _wordBoundary(String text, int start, int length) {
    final before = start == 0 ? ' ' : text[start - 1];
    final end = start + length;
    final after = end >= text.length ? ' ' : text[end];
    return !RegExp(r'[a-z0-9]').hasMatch(before) && !RegExp(r'[a-z0-9]').hasMatch(after);
  }

  dynamic _recordId(String text, RuntimeEntity entity, int entityPosition, CommandAction action) {
    if (action != CommandAction.update && action != CommandAction.delete && action != CommandAction.get) return null;
    final normalizedText = CommandTextNormalizer.normalize(text);
    final entityKey = CommandTextNormalizer.normalize(entity.name);
    final number = RegExp(r'\b(?:numero|nro)\s+(\d+|[a-z]+(?:\s+y\s+[a-z]+)?)\b').firstMatch(normalizedText);
    if (number != null) return _parseNumber(number.group(1)!);
    final exactPosition = normalizedText.indexOf(entityKey);
    final start = exactPosition >= 0 ? exactPosition : entityPosition;
    final numeric = RegExp(r'\b(\d+|[a-z]+(?:\s+y\s+[a-z]+)?)\b').firstMatch(normalizedText.substring(start + entityKey.length));
    return numeric == null ? null : _parseNumber(numeric.group(1)!);
  }

  dynamic _parseNumber(String value) => int.tryParse(value) ?? SpanishNumberWords.parse(value);

  void _parseValues(String text, RuntimeEntity entity, Map<String, dynamic> values, Map<String, String> relations, bool allowImplicitDisplay, [RuntimeSchema? schema]) {
    final fields = entity.fields.where((field) => field.editable && !field.readOnly && field.name != entity.idField);
    for (final field in fields) {
      final names = <String>{CommandTextNormalizer.normalize(field.name), CommandTextNormalizer.normalize(_label(field.name))}.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final name in names) {
        final raw = _captureValue(text, name, field.type);
        if (raw == null || raw.isEmpty) continue;
        if (field.relation) {
          relations[field.name] = raw;
        } else {
          values[field.name] = _value(raw, field.type);
        }
        break;
      }
    }
    if (schema != null) {
      final inferredRelations = _inferRelationTargets(text, entity, schema);
      if (inferredRelations.isNotEmpty) {
        relations.addAll(inferredRelations);
      }
    }
    if (allowImplicitDisplay && entity.displayField.isNotEmpty && !values.containsKey(entity.displayField)) {
      final display = _implicitDisplay(text, entity);
      if (display != null && display.isNotEmpty) values[entity.displayField] = display;
    }
  }

  Map<String, String> _inferRelationTargets(String originalText, RuntimeEntity entity, RuntimeSchema schema) {
    final relations = <String, String>{};
    final relationFields = entity.fields.where((field) => field.relation && field.editable && !field.readOnly).toList();
    if (relationFields.isEmpty) return relations;
    final normalizedText = CommandTextNormalizer.normalize(originalText);
    final originalTokens = originalText.split(RegExp(r'\s+'));
    final normalizedTokens = normalizedText.split(RegExp(r'\s+'));

    for (final field in relationFields) {
      final targetEntity = schema.entityByName(field.targetEntity);
      if (targetEntity == null) continue;
      final targetPattern = CommandTextNormalizer.normalize(targetEntity.name).split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
      if (targetPattern.isEmpty) continue;
      for (var i = 0; i + targetPattern.length <= normalizedTokens.length; i++) {
        var matches = true;
        for (var j = 0; j < targetPattern.length; j++) {
          if (normalizedTokens[i + j] != targetPattern[j]) {
            matches = false;
            break;
          }
        }
        if (!matches) continue;
        final remainder = originalTokens.sublist(i + targetPattern.length);
        final value = remainder
            .takeWhile((token) => !['con', 'y', 'para', 'de', 'del', 'al', 'como', 'que', 'en', 'la', 'el', 'los', 'las', 'a', 'as']
                .contains(CommandTextNormalizer.normalize(token)))
            .join(' ')
            .trim();
        if (value.isNotEmpty && value.toLowerCase() != 'null') {
          relations[field.name] = value;
        }
        break;
      }
    }
    return relations;
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

class _RelationContext {
  final RuntimeEntity sourceEntity;
  final RuntimeEntity targetEntity;
  final String operation;
  final Map<String, dynamic> sourceSelector;
  final Map<String, dynamic> targetSelector;
  final Map<String, String> relationValues;

  const _RelationContext({
    required this.sourceEntity,
    required this.targetEntity,
    required this.operation,
    required this.sourceSelector,
    required this.targetSelector,
    required this.relationValues,
  });
}
