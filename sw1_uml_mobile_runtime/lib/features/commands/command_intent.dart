import '../../schema/model/runtime_schema.dart';

enum CommandAction { create, update, delete, list, get, unknown }

class CommandIntent {
  final CommandAction action;
  final RuntimeEntity? entity;
  final RuntimeEntity? sourceEntity;
  final RuntimeEntity? targetEntity;
  final Map<String, dynamic> sourceSelector;
  final Map<String, dynamic> targetSelector;
  final String relationOperation;
  final dynamic recordId;
  final Map<String, dynamic> values;
  final Map<String, String> relationValues;
  final double confidence;
  final List<String> ambiguities;
  final String originalText;

  const CommandIntent({
    required this.action,
    required this.entity,
    this.sourceEntity,
    this.targetEntity,
    this.sourceSelector = const {},
    this.targetSelector = const {},
    this.relationOperation = '',
    this.recordId,
    this.values = const {},
    this.relationValues = const {},
    this.confidence = 1,
    this.ambiguities = const [],
    required this.originalText,
  });
}
