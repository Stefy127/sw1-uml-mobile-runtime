import 'package:flutter_test/flutter_test.dart';
import 'package:sw1_uml_mobile_runtime/core/database/generic_repository.dart';
import 'package:sw1_uml_mobile_runtime/features/commands/command_execution_plan.dart';
import 'package:sw1_uml_mobile_runtime/features/commands/command_executor.dart';
import 'package:sw1_uml_mobile_runtime/features/commands/local_command_interpreter.dart';
import 'package:sw1_uml_mobile_runtime/schema/model/runtime_schema.dart';

void main() {
  test('el flujo real conserva origen y destino y crea association class', () async {
    final repository = _CommandRepository({
      '/api/libros': [
        {'id': 10, 'titulo': 'Cien años de soledad', 'categoriaIds': []},
      ],
      '/api/categorias': [
        {'id': 20, 'nombre': 'Novela'},
      ],
    });
    final schema = _schema(withBridge: true);
    final intent = LocalCommandInterpreter().interpret(
      'Asocia el libro Cien años de soledad con la categoría Novela',
      schema,
    );
    final executor = CommandExecutor(schema: schema, repository: repository);

    final plan = await executor.buildPlan(intent);

    expect(plan.status, CommandPlanStatus.ready);
    expect(plan.sourceEntity?.name, 'Libro');
    expect(plan.targetEntity?.name, 'Categoria');
    expect(plan.bridgeEntity?.name, 'LibroCategoria');
    expect(plan.resolvedIds, {'source': 10, 'target': 20});
    expect(plan.relationOperations.single.operation, 'createBridge');
    expect(plan.blockingError, isEmpty);

    final result = await executor.executePlan(plan);

    expect(result.success, isTrue);
    expect(repository.createdEntity?.name, 'LibroCategoria');
    expect(repository.createdBody, {'libroId': 10, 'categoriaId': 20});
  });

  test('la frase sin nombres de entidad resuelve endpoints y no busca el bridge', () async {
    final repository = _CommandRepository({
      '/api/libros': [{'id': 10, 'titulo': 'Cien años de soledad'}],
      '/api/categorias': [{'id': 20, 'nombre': 'Novela'}],
    });
    final schema = _schema(withBridge: true);
    final intent = LocalCommandInterpreter().interpret('Asocia cien años de soledad con la categoría novela', schema);
    final plan = await CommandExecutor(schema: schema, repository: repository).buildPlan(intent);

    expect(plan.status, CommandPlanStatus.ready);
    expect(plan.sourceEntity?.name, 'Libro');
    expect(plan.targetEntity?.name, 'Categoria');
    expect(plan.bridgeEntity?.name, 'LibroCategoria');
    expect(plan.relationOperations.single.operation, 'createBridge');
    expect(plan.resolvedIds, {'source': 10, 'target': 20});
  });

  test('la prioridad explícita se incluye en el payload del bridge', () async {
    final repository = _CommandRepository({
      '/api/libros': [{'id': 10, 'titulo': 'Libro A'}],
      '/api/categorias': [{'id': 20, 'nombre': 'Categoria B'}],
    });
    final schema = _schema(withBridge: true, withPriority: true);
    final intent = LocalCommandInterpreter().interpret('Asocia Libro A con Categoria B con prioridad 2', schema);
    final plan = await CommandExecutor(schema: schema, repository: repository).buildPlan(intent);

    expect(plan.status, CommandPlanStatus.ready);
    await CommandExecutor(schema: schema, repository: repository).executePlan(plan);
    expect(repository.createdBody, {'prioridad': 2, 'libroId': 10, 'categoriaId': 20});
  });

  test('el flujo real aplica add y remove N:M sobre el lado propietario', () async {
    final repository = _CommandRepository({
      '/api/libros': [
        {'id': 10, 'titulo': 'Cien años de soledad', 'categoriaIds': [30]},
      ],
      '/api/categorias': [
        {'id': 20, 'nombre': 'Novela'},
        {'id': 30, 'nombre': 'Drama'},
      ],
    });
    final schema = _schema();
    final executor = CommandExecutor(schema: schema, repository: repository);
    final interpreter = LocalCommandInterpreter();

    final add = await executor.buildPlan(interpreter.interpret(
      'Agrega la categoría Novela al libro Cien años de soledad',
      schema,
    ));
    expect(add.status, CommandPlanStatus.ready);
    expect(add.relationOperations.single.operation, 'add');
    await executor.executePlan(add);
    expect(repository.updatedBody['categoriaIds'], [30, 20]);

    repository.updatedBody = {};
    final remove = await executor.buildPlan(interpreter.interpret(
      'Quita la categoría Drama del libro Cien años de soledad',
      schema,
    ));
    expect(remove.status, CommandPlanStatus.ready);
    expect(remove.relationOperations.single.operation, 'remove');
    await executor.executePlan(remove);
    expect(repository.updatedBody['categoriaIds'], isEmpty);
  });

  test('registro inexistente bloquea preview y ejecución', () async {
    final schema = _schema();
    final repository = _CommandRepository({'/api/libros': [], '/api/categorias': []});
    final intent = LocalCommandInterpreter().interpret(
      'Asocia el libro Inexistente con la categoría Novela',
      schema,
    );
    final plan = await CommandExecutor(schema: schema, repository: repository).buildPlan(intent);

    expect(plan.status, CommandPlanStatus.notFound);
    expect(plan.executable, isFalse);
    expect(plan.blockingError, contains('Libro'));
  });

  test('dos coincidencias bloquean el plan como ambiguous', () async {
    final schema = _schema();
    final repository = _CommandRepository({
      '/api/libros': [
        {'id': 10, 'titulo': 'Cien años de soledad', 'categoriaIds': []},
      ],
      '/api/categorias': [
        {'id': 20, 'nombre': 'Novela'},
        {'id': 21, 'nombre': 'Novela'},
      ],
    });
    final intent = LocalCommandInterpreter().interpret(
      'Asocia el libro Cien años de soledad con la categoría Novela',
      schema,
    );
    final plan = await CommandExecutor(schema: schema, repository: repository).buildPlan(intent);

    expect(plan.status, CommandPlanStatus.ambiguous);
    expect(plan.executable, isFalse);
  });

  test('el flujo real resuelve una relación recursiva jefe', () async {
    final schema = _employeeSchema();
    final repository = _CommandRepository({
      '/api/empleados': [
        {'id': 1, 'nombre': 'Juan'},
        {'id': 2, 'nombre': 'María'},
      ],
    });
    final intent = LocalCommandInterpreter().interpret('Asigna a Juan como jefe de María', schema);
    final executor = CommandExecutor(schema: schema, repository: repository);
    final plan = await executor.buildPlan(intent);

    expect(plan.status, CommandPlanStatus.ready);
    expect(plan.sourceRecord?['nombre'], 'María');
    expect(plan.relatedRecord?['nombre'], 'Juan');
    await executor.executePlan(plan);
    expect(repository.updatedBody, {'jefeId': 1});
  });

  test('el flujo real convierte inverse readOnly subordinada al owning side', () async {
    final schema = _employeeSchema();
    final repository = _CommandRepository({
      '/api/empleados': [
        {'id': 3, 'nombre': 'Carla'},
        {'id': 4, 'nombre': 'Luis'},
      ],
    });
    final intent = LocalCommandInterpreter().interpret('Agrega Carla como subordinada de Luis', schema);
    final executor = CommandExecutor(schema: schema, repository: repository);
    final plan = await executor.buildPlan(intent);

    expect(plan.status, CommandPlanStatus.ready);
    await executor.executePlan(plan);
    expect(repository.updatedBody, {'jefeId': 4});
  });
}

RuntimeSchema _schema({bool withBridge = false, bool withPriority = false}) {
  final libro = RuntimeEntity(
    name: 'Libro',
    endpoint: '/api/libros',
    idField: 'id',
    displayField: 'titulo',
    operations: _operations(),
    fields: [
      _field('titulo'),
      RuntimeField(name: 'categoriaIds', type: 'relation', required: false, editable: true, readOnly: false, nullable: true, collection: true, relation: true, targetEntity: 'Categoria', owningSide: true),
    ],
  );
  final categoria = RuntimeEntity(
    name: 'Categoria',
    endpoint: '/api/categorias',
    idField: 'id',
    displayField: 'nombre',
    operations: _operations(),
    fields: [_field('nombre')],
  );
  final entities = <RuntimeEntity>[libro, categoria];
  if (withBridge) {
    entities.add(RuntimeEntity(
      name: 'LibroCategoria',
      endpoint: '/api/libro-categorias',
      idField: 'id',
      displayField: 'id',
      operations: _operations(),
      fields: [
        RuntimeField(name: 'libroId', type: 'relation', required: true, editable: true, readOnly: false, nullable: false, collection: false, relation: true, targetEntity: 'Libro'),
        RuntimeField(name: 'categoriaId', type: 'relation', required: true, editable: true, readOnly: false, nullable: false, collection: false, relation: true, targetEntity: 'Categoria'),
        if (withPriority) RuntimeField(name: 'prioridad', type: 'integer', required: false, editable: true, readOnly: false, nullable: true, collection: false, relation: false),
      ],
    ));
  }
  return RuntimeSchema(schemaVersion: '1', application: 'Test', version: '1', entities: entities);
}

RuntimeOperations _operations() => RuntimeOperations(list: true, get: true, create: true, update: true, delete: true);

RuntimeField _field(String name) => RuntimeField(name: name, type: 'string', required: true, editable: true, readOnly: false, nullable: false, collection: false, relation: false);

RuntimeSchema _employeeSchema() {
  final employee = RuntimeEntity(
    name: 'Empleado',
    endpoint: '/api/empleados',
    idField: 'id',
    displayField: 'nombre',
    operations: _operations(),
    fields: [
      _field('nombre'),
      RuntimeField(name: 'jefeId', type: 'relation', required: false, editable: true, readOnly: false, nullable: true, collection: false, relation: true, targetEntity: 'Empleado', owningSide: true),
      RuntimeField(name: 'subordinados', type: 'relation', required: false, editable: false, readOnly: true, nullable: true, collection: true, relation: true, targetEntity: 'Empleado', owningSide: false),
    ],
  );
  return RuntimeSchema(schemaVersion: '1', application: 'Test', version: '1', entities: [employee]);
}

class _CommandRepository extends GenericRepository {
  final Map<String, List<Map<String, dynamic>>> records;
  Map<String, dynamic> updatedBody = {};
  RuntimeEntity? createdEntity;
  Map<String, dynamic> createdBody = {};

  _CommandRepository(this.records) : super();

  @override
  Future<List<Map<String, dynamic>>> getAll(RuntimeEntity entity) async => records[entity.endpoint] ?? [];

  @override
  Future<Map<String, dynamic>> update(RuntimeEntity entity, dynamic id, Map<String, dynamic> body) async {
    updatedBody = body;
    return body;
  }

  @override
  Future<Map<String, dynamic>> create(RuntimeEntity entity, Map<String, dynamic> body) async {
    createdEntity = entity;
    createdBody = body;
    return body;
  }
}