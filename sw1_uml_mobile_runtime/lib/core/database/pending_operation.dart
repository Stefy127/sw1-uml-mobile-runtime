enum PendingOperationType { create, update, delete }

bool isTemporaryId(dynamic value) =>
    RegExp(r'^(local|temp)-', caseSensitive: false).hasMatch('$value');

class PendingOperation {
  final String id;
  final String entityEndpoint;
  final PendingOperationType operationType;
  final dynamic recordId;
  final String? idField;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final String status;

  const PendingOperation({
    required this.id,
    required this.entityEndpoint,
    required this.operationType,
    required this.recordId,
    this.idField,
    required this.payload,
    required this.createdAt,
    this.status = 'pending',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'entityEndpoint': entityEndpoint,
        'operationType': operationType.name,
        'recordId': recordId,
        'idField': idField,
        'payload': payload,
        'createdAt': createdAt.toIso8601String(),
        'status': status,
      };

  factory PendingOperation.fromJson(Map<String, dynamic> json) =>
      PendingOperation(
        id: json['id'] as String,
        entityEndpoint: json['entityEndpoint'] as String,
        operationType: PendingOperationType.values.byName(
          json['operationType'] as String,
        ),
        recordId: json['recordId'],
        idField: json['idField'] as String?,
        payload: json['payload'] is Map
            ? Map<String, dynamic>.from(json['payload'] as Map)
            : <String, dynamic>{},
        createdAt: DateTime.parse(json['createdAt'] as String),
        status: json['status'] as String? ?? 'pending',
      );
}
