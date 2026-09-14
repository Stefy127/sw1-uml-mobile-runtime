enum PendingOperationType { create, update, delete }

class PendingOperation {
  final String id;
  final String entityEndpoint;
  final PendingOperationType operationType;
  final dynamic recordId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final String status;

  const PendingOperation({
    required this.id,
    required this.entityEndpoint,
    required this.operationType,
    required this.recordId,
    required this.payload,
    required this.createdAt,
    this.status = 'pending',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'entityEndpoint': entityEndpoint,
        'operationType': operationType.name,
        'recordId': recordId,
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
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        createdAt: DateTime.parse(json['createdAt'] as String),
        status: json['status'] as String? ?? 'pending',
      );
}
