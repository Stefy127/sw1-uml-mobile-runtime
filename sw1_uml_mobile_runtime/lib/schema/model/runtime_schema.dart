class RuntimeSchema {
  final String schemaVersion;
  final String application;
  final String version;
  final List<RuntimeEntity> entities;

  RuntimeSchema({
    required this.schemaVersion,
    required this.application,
    required this.version,
    required this.entities,
  });

  factory RuntimeSchema.fromJson(Map<String, dynamic> json) {
    return RuntimeSchema(
      schemaVersion: json['schemaVersion'] ?? '',
      application: json['application'] ?? '',
      version: json['version'] ?? '',
      entities: (json['entities'] as List? ?? [])
          .map((e) => RuntimeEntity.fromJson(
                Map<String, dynamic>.from(e),
              ))
          .toList(),
    );
  }

  RuntimeEntity? entityByName(String? name) => name == null
      ? null
      : entities.where((entity) => entity.name == name).firstOrNull;
}

class RuntimeEntity {
  final String name;
  final String endpoint;
  final String idField;
  final String displayField;
  final RuntimeOperations operations;
  final List<RuntimeField> fields;

  RuntimeEntity({
    required this.name,
    required this.endpoint,
    required this.idField,
    required this.displayField,
    required this.operations,
    required this.fields,
  });

  factory RuntimeEntity.fromJson(Map<String, dynamic> json) {
    return RuntimeEntity(
      name: json['name'] ?? '',
      endpoint: json['endpoint'] ?? '',
      idField: json['idField'] ?? 'id',
      displayField: json['displayField'] ?? 'id',
      operations: RuntimeOperations.fromJson(
        Map<String, dynamic>.from(json['operations'] ?? {}),
      ),
      fields: (json['fields'] as List? ?? [])
          .map((e) => RuntimeField.fromJson(
                Map<String, dynamic>.from(e),
              ))
          .toList(),
    );
  }
}

class RuntimeOperations {
  final bool list;
  final bool get;
  final bool create;
  final bool update;
  final bool delete;

  RuntimeOperations({
    required this.list,
    required this.get,
    required this.create,
    required this.update,
    required this.delete,
  });

  factory RuntimeOperations.fromJson(Map<String, dynamic> json) {
    return RuntimeOperations(
      list: json['list'] == true,
      get: json['get'] == true,
      create: json['create'] == true,
      update: json['update'] == true,
      delete: json['delete'] == true,
    );
  }
}

class RuntimeField {
  final String name;
  final String type;
  final bool required;
  final bool editable;
  final bool readOnly;
  final bool nullable;
  final bool collection;
  final bool relation;
  final String? targetEntity;
  final bool? owningSide;
  final String? requestField;

  RuntimeField({
    required this.name,
    required this.type,
    required this.required,
    required this.editable,
    required this.readOnly,
    required this.nullable,
    required this.collection,
    required this.relation,
    this.targetEntity,
    this.owningSide,
    this.requestField,
  });

  factory RuntimeField.fromJson(Map<String, dynamic> json) {
    return RuntimeField(
      name: json['name'] ?? '',
      type: json['type'] ?? 'string',
      required: json['required'] == true,
      editable: json['editable'] == true,
      readOnly: json['readOnly'] == true,
      nullable: json['nullable'] == true,
      collection: json['collection'] == true,
      relation: json['relation'] == true,
      targetEntity: json['targetEntity'],
      owningSide: json['owningSide'],
      requestField: json['requestField'],
    );
  }
}
