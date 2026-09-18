import '../../schema/model/runtime_schema.dart';
import 'command_intent.dart';

enum CommandPlanStatus {
  ready,
  notFound,
  ambiguous,
  missingRequiredFields,
  invalidRelation,
  offlineUnresolved,
  readOnlyWithoutOwningSide,
  invalid,
}

class CommandRelationOperation {
  final String operation;
  final RuntimeEntity? sourceEntity;
  final RuntimeEntity? targetEntity;
  final RuntimeEntity? bridgeEntity;
  final RuntimeField? field;
  final dynamic sourceId;
  final dynamic targetId;
  final Map<String, dynamic> payload;

  const CommandRelationOperation({
    required this.operation,
    this.sourceEntity,
    this.targetEntity,
    this.bridgeEntity,
    this.field,
    this.sourceId,
    this.targetId,
    this.payload = const {},
  });
}

class CommandExecutionPlan {
  final CommandIntent intent;
  final CommandAction action;
  final RuntimeEntity? entity;
  final RuntimeEntity? sourceEntity;
  final RuntimeEntity? targetEntity;
  final RuntimeEntity? bridgeEntity;
  final Map<String, dynamic>? targetRecord;
  final Map<String, dynamic>? sourceRecord;
  final Map<String, dynamic>? relatedRecord;
  final Map<String, dynamic> scalarChanges;
  final List<CommandRelationOperation> relationOperations;
  final Map<String, dynamic> resolvedIds;
  final CommandPlanStatus status;
  final String blockingError;

  const CommandExecutionPlan({
    required this.intent,
    required this.action,
    this.entity,
    this.sourceEntity,
    this.targetEntity,
    this.bridgeEntity,
    this.targetRecord,
    this.sourceRecord,
    this.relatedRecord,
    this.scalarChanges = const {},
    this.relationOperations = const [],
    this.resolvedIds = const {},
    this.status = CommandPlanStatus.ready,
    this.blockingError = '',
  });

  bool get executable => status == CommandPlanStatus.ready && blockingError.isEmpty;
}