import 'package:flutter_test/flutter_test.dart';
import 'package:sw1_uml_mobile_runtime/core/api/entity_resolver.dart';
import 'package:sw1_uml_mobile_runtime/core/api/generic_api_service.dart';
import 'package:sw1_uml_mobile_runtime/core/api/relation_resolver.dart';
import 'package:sw1_uml_mobile_runtime/core/database/generic_repository.dart';
import 'package:sw1_uml_mobile_runtime/schema/model/runtime_schema.dart';

class _TestApi extends GenericApiService {
  final List<Map<String, dynamic>> _data = [
    {'id': 1, 'nombre': 'Novela', 'titulo': 'Cien años de soledad'},
    {'id': 2, 'nombre': 'Drama', 'titulo': 'Libro A'},
    {'id': 3, 'nombre': 'Gabriel García Márquez', 'titulo': 'Libro B'},
    {'id': 4, 'nombre': 'Juan', 'titulo': 'Libro C'},
    {'id': 5, 'nombre': 'María', 'titulo': 'Libro D'},
    {'id': 6, 'nombre': 'Luis', 'titulo': 'Libro E'},
    {'id': 7, 'nombre': 'Perfil principal', 'titulo': 'Perfil'},
  ];

  @override
  Future<List<Map<String, dynamic>>> getAll(String path) async {
    return _data.where((item) => path.endsWith('categorias') ? item.containsKey('nombre') : true).toList();
  }
}

class _TestRepository extends GenericRepository {
  _TestRepository() : super(api: _TestApi());

  @override
  Future<List<Map<String, dynamic>>> getAll(RuntimeEntity entity) async {
    final data = <Map<String, dynamic>>[
      {'id': 1, 'nombre': 'Novela', 'titulo': 'Cien años de soledad'},
      {'id': 2, 'nombre': 'Drama', 'titulo': 'Libro A'},
      {'id': 3, 'nombre': 'Gabriel García Márquez', 'titulo': 'Libro B'},
      {'id': 4, 'nombre': 'Juan', 'titulo': 'Libro C'},
      {'id': 5, 'nombre': 'María', 'titulo': 'Libro D'},
      {'id': 6, 'nombre': 'Luis', 'titulo': 'Libro E'},
      {'id': 7, 'nombre': 'Perfil principal', 'titulo': 'Perfil'},
    ];
    if (entity.name == 'Categoria') {
      return data.where((item) => item.containsKey('nombre')).toList();
    }
    if (entity.name == 'Autor') {
      return [
        {'id': 3, 'nombre': 'Gabriel García Márquez'},
        {'id': 4, 'nombre': 'Juan'},
        {'id': 5, 'nombre': 'María'},
      ];
    }
    if (entity.name == 'Perfil') {
      return [
        {'id': 7, 'nombre': 'Perfil principal'},
      ];
    }
    if (entity.name == 'Empleado') {
      return [
        {'id': 4, 'nombre': 'Juan'},
        {'id': 5, 'nombre': 'María'},
        {'id': 6, 'nombre': 'Luis'},
      ];
    }
    return data;
  }
}

RuntimeSchema _schema() => RuntimeSchema(
      schemaVersion: '1',
      application: 'Test',
      version: '1',
      entities: [
        RuntimeEntity(
          name: 'Libro',
          endpoint: '/api/libros',
          idField: 'id',
          displayField: 'titulo',
          operations: RuntimeOperations(list: true, get: true, create: true, update: true, delete: true),
          fields: [
            RuntimeField(name: 'titulo', type: 'string', required: true, editable: true, readOnly: false, nullable: false, collection: false, relation: false),
            RuntimeField(name: 'autorId', type: 'relation', required: false, editable: true, readOnly: false, nullable: true, collection: false, relation: true, targetEntity: 'Autor', owningSide: true),
            RuntimeField(name: 'categoriaIds', type: 'relation', required: false, editable: true, readOnly: false, nullable: true, collection: true, relation: true, targetEntity: 'Categoria', owningSide: true),
          ],
        ),
        RuntimeEntity(
          name: 'Autor',
          endpoint: '/api/autores',
          idField: 'id',
          displayField: 'nombre',
          operations: RuntimeOperations(list: true, get: true, create: true, update: true, delete: true),
          fields: [
            RuntimeField(name: 'nombre', type: 'string', required: true, editable: true, readOnly: false, nullable: false, collection: false, relation: false),
            RuntimeField(name: 'perfilId', type: 'relation', required: false, editable: true, readOnly: false, nullable: true, collection: false, relation: true, targetEntity: 'Perfil', owningSide: true),
          ],
        ),
        RuntimeEntity(
          name: 'Perfil',
          endpoint: '/api/perfiles',
          idField: 'id',
          displayField: 'nombre',
          operations: RuntimeOperations(list: true, get: true, create: true, update: true, delete: true),
          fields: [
            RuntimeField(name: 'nombre', type: 'string', required: true, editable: true, readOnly: false, nullable: false, collection: false, relation: false),
          ],
        ),
        RuntimeEntity(
          name: 'Categoria',
          endpoint: '/api/categorias',
          idField: 'id',
          displayField: 'nombre',
          operations: RuntimeOperations(list: true, get: true, create: true, update: true, delete: true),
          fields: [RuntimeField(name: 'nombre', type: 'string', required: true, editable: true, readOnly: false, nullable: false, collection: false, relation: false)],
        ),
        RuntimeEntity(
          name: 'Empleado',
          endpoint: '/api/empleados',
          idField: 'id',
          displayField: 'nombre',
          operations: RuntimeOperations(list: true, get: true, create: true, update: true, delete: true),
          fields: [
            RuntimeField(name: 'nombre', type: 'string', required: true, editable: true, readOnly: false, nullable: false, collection: false, relation: false),
            RuntimeField(name: 'jefeId', type: 'relation', required: false, editable: true, readOnly: false, nullable: true, collection: false, relation: true, targetEntity: 'Empleado', owningSide: true),
            RuntimeField(name: 'subordinadosIds', type: 'relation', required: false, editable: false, readOnly: true, nullable: true, collection: true, relation: true, targetEntity: 'Empleado', owningSide: false),
          ],
        ),
        RuntimeEntity(
          name: 'LibroCategoria',
          endpoint: '/api/libro-categorias',
          idField: 'id',
          displayField: 'id',
          operations: RuntimeOperations(list: true, get: true, create: true, update: true, delete: true),
          fields: [
            RuntimeField(name: 'libroId', type: 'relation', required: true, editable: true, readOnly: false, nullable: false, collection: false, relation: true, targetEntity: 'Libro', owningSide: true),
            RuntimeField(name: 'categoriaId', type: 'relation', required: true, editable: true, readOnly: false, nullable: false, collection: false, relation: true, targetEntity: 'Categoria', owningSide: true),
            RuntimeField(name: 'prioridad', type: 'integer', required: true, editable: true, readOnly: false, nullable: false, collection: false, relation: false),
          ],
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('EntityResolver resolves by human field and exact match', () async {
    final repository = _TestRepository();
    final resolver = EntityResolver(repository: repository);

    final resolved = await resolver.resolve(_schema().entityByName('Categoria')!, {'nombre': 'Novela'});
    expect(resolved.status, EntityResolutionStatus.resolved);
    expect(resolved.record!['id'], 1);
  });

  test('RelationResolver resolves 1:N and N:M add operations', () async {
    final schema = _schema();
    final repository = _TestRepository();
    final resolver = RelationResolver.withRepository(repository, schema);

    final libro = schema.entityByName('Libro')!;
    final categoria = schema.entityByName('Categoria')!;
    final field = libro.fields.firstWhere((item) => item.name == 'categoriaIds');

    final relation = await resolver.resolveField(
      sourceEntity: libro,
      field: field,
      sourceRecord: {'id': 1, 'titulo': 'Cien años de soledad'},
      selector: 'Novela',
      operation: RelationOperation.add,
    );
    expect(relation.status, RelationResolutionStatus.resolved);
    expect(relation.targetIds, contains(1));
    expect(relation.operation, RelationOperation.add);

    final autorField = libro.fields.firstWhere((item) => item.name == 'autorId');
    final autorRelation = await resolver.resolveField(
      sourceEntity: libro,
      field: autorField,
      sourceRecord: {'id': 1, 'titulo': 'Cien años de soledad'},
      selector: 'Gabriel García Márquez',
      operation: RelationOperation.set,
    );
    expect(autorRelation.status, RelationResolutionStatus.resolved);
    expect(autorRelation.valueId, 3);
  });

  test('RelationResolver resolves inverse readOnly to owning side', () async {
    final schema = _schema();
    final repository = _TestRepository();
    final resolver = RelationResolver.withRepository(repository, schema);

    final empleado = schema.entityByName('Empleado')!;
    final field = empleado.fields.firstWhere((item) => item.name == 'subordinadosIds');
    final relation = await resolver.resolveField(
      sourceEntity: empleado,
      field: field,
      sourceRecord: {'id': 6, 'nombre': 'Luis'},
      selector: 'Juan',
      operation: RelationOperation.add,
    );

    expect(relation.status, RelationResolutionStatus.resolved);
    expect(relation.owningFieldName, 'jefeId');
    expect(relation.valueId, 4);
  });

  test('RelationResolver resolves recursive self-reference', () async {
    final schema = _schema();
    final repository = _TestRepository();
    final resolver = RelationResolver.withRepository(repository, schema);

    final empleado = schema.entityByName('Empleado')!;
    final field = empleado.fields.firstWhere((item) => item.name == 'jefeId');
    final relation = await resolver.resolveField(
      sourceEntity: empleado,
      field: field,
      sourceRecord: {'id': 5, 'nombre': 'María'},
      selector: 'Juan',
      operation: RelationOperation.set,
    );

    expect(relation.status, RelationResolutionStatus.resolved);
    expect(relation.valueId, 4);
    expect(relation.fieldName, 'jefeId');
  });

  test('RelationResolver resolves association class explicit and required extra fields', () async {
    final schema = _schema();
    final repository = _TestRepository();
    final resolver = RelationResolver.withRepository(repository, schema);

    final bridge = schema.entityByName('LibroCategoria')!;
    final result = await resolver.resolveAssociationBridge(
      sourceEntity: schema.entityByName('Libro')!,
      targetEntity: schema.entityByName('Categoria')!,
      sourceSelector: {'titulo': 'Cien años de soledad'},
      targetSelector: {'nombre': 'Novela'},
      bridgeEntity: bridge,
      payload: {'prioridad': 2},
    );

    expect(result.status, RelationResolutionStatus.resolved);
    expect(result.payload['prioridad'], 2);
    expect(result.payload['libroId'], 1);
    expect(result.payload['categoriaId'], 1);
  });

  test('RelationOperationNormalizer classifies operations', () {
    expect(RelationOperationNormalizer.normalize('asigna Novela a Libro A'), RelationOperation.set);
    expect(RelationOperationNormalizer.normalize('agrega Novela a las categorías de Libro A'), RelationOperation.add);
    expect(RelationOperationNormalizer.normalize('quita Novela de Libro A'), RelationOperation.remove);
    expect(RelationOperationNormalizer.normalize('deja solamente Novela y Drama como categorías de Libro A'), RelationOperation.replace);
  });
}
