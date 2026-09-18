import 'package:flutter_test/flutter_test.dart';
import 'package:sw1_uml_mobile_runtime/core/database/generic_repository.dart';
import 'package:sw1_uml_mobile_runtime/features/commands/command_intent.dart';
import 'package:sw1_uml_mobile_runtime/features/commands/command_executor.dart';
import 'package:sw1_uml_mobile_runtime/features/commands/local_command_interpreter.dart';
import 'package:sw1_uml_mobile_runtime/features/commands/text_normalizer.dart';
import 'package:sw1_uml_mobile_runtime/schema/model/runtime_schema.dart';

RuntimeSchema _schema() => RuntimeSchema(
      schemaVersion: '1',
      application: 'Test',
      version: '1',
      entities: [
        RuntimeEntity(
          name: 'Materia',
          endpoint: '/api/materias',
          idField: 'id',
          displayField: 'nombre',
          operations: RuntimeOperations(
            list: true,
            get: true,
            create: true,
            update: true,
            delete: true,
          ),
          fields: [
            RuntimeField(name: 'nombre', type: 'string', required: true, editable: true, readOnly: false, nullable: false, collection: false, relation: false),
            RuntimeField(name: 'creditos', type: 'integer', required: true, editable: true, readOnly: false, nullable: false, collection: false, relation: false),
            RuntimeField(name: 'carreraId', type: 'relation', required: false, editable: true, readOnly: false, nullable: true, collection: false, relation: true, targetEntity: 'Carrera'),
          ],
        ),
        RuntimeEntity(
          name: 'Carrera',
          endpoint: '/api/carreras',
          idField: 'id',
          displayField: 'nombre',
          operations: RuntimeOperations(list: true, get: true, create: true, update: true, delete: true),
          fields: [
            RuntimeField(name: 'nombre', type: 'string', required: true, editable: true, readOnly: false, nullable: false, collection: false, relation: false),
          ],
        ),
      ],
    );

void main() {
  final interpreter = LocalCommandInterpreter();

  test('normalizes accents and articles', () {
    expect(CommandTextNormalizer.normalize('Crear una Matería'), 'crear una materia');
  });

  test('parses generic create, integer and relation display text', () {
    final intent = interpreter.interpret('crear una materia llamada Redes 2 con creditos 5 con carrera Informatica', _schema());
    expect(intent.action, CommandAction.create);
    expect(intent.entity!.name, 'Materia');
    expect(intent.values['nombre'], 'Redes 2');
    expect(intent.values['creditos'], 5);
    expect(intent.relationValues['carreraId'], 'Informatica');
  });

  test('parses integer fields accent-insensitively', () {
    final intent = interpreter.interpret(
      'Crea una materia llamada Redes 2 con créditos 5',
      _schema(),
    );
    expect(intent.values['creditos'], 5);
  });

  test('understands natural commands and number words', () {
    final create = interpreter.interpret(
      'Registrame una nueva materia Redes 2 de cinco cr\u00e9ditos',
      _schema(),
    );
    final update = interpreter.interpret(
      'Ponle seis cr\u00e9ditos a la materia 8',
      _schema(),
    );
    final get = interpreter.interpret('Mostrame la materia ocho', _schema());
    expect(create.action, CommandAction.create);
    expect(create.values['nombre'], 'Redes 2');
    expect(create.values['creditos'], 5);
    expect(update.action, CommandAction.update);
    expect(update.recordId, 8);
    expect(update.values['creditos'], 6);
    expect(get.action, CommandAction.get);
    expect(get.recordId, 8);
  });

  test('extracts IDs and distinguishes list from get', () {
    final getDigits = interpreter.interpret('mostrame la materia 8', _schema());
    final getWords = interpreter.interpret('consultar materia ocho', _schema());
    final list = interpreter.interpret('listar materias', _schema());
    final getNumber = interpreter.interpret('mostrar carrera n\u00famero 5', _schema());
    final delete = interpreter.interpret('borra materia n\u00famero cuatro', _schema());

    expect(getDigits.action, CommandAction.get);
    expect(getDigits.recordId, 8);
    expect(getWords.action, CommandAction.get);
    expect(getWords.recordId, 8);
    expect(list.action, CommandAction.list);
    expect(list.recordId, isNull);
    expect(getNumber.action, CommandAction.get);
    expect(getNumber.recordId, 5);
    expect(delete.action, CommandAction.delete);
    expect(delete.recordId, 4);
  });

  test('parses plural list and update id', () {
    final list = interpreter.interpret('listar materias', _schema());
    final update = interpreter.interpret('editar materia 8 cambiar creditos a 6', _schema());
    expect(list.action, CommandAction.list);
    expect(update.action, CommandAction.update);
    expect(update.recordId, 8);
    expect(update.values['creditos'], 6);
  });

  test('recognizes natural action variants', () {
    expect(interpreter.interpret('Crea una materia llamada Redes', _schema()).action, CommandAction.create);
    expect(interpreter.interpret('Edita materia 8 cambiar creditos a 6', _schema()).action, CommandAction.update);
    expect(interpreter.interpret('Elimina materia 4', _schema()).action, CommandAction.delete);
    expect(interpreter.interpret('Muestra materias', _schema()).action, CommandAction.list);
  });

  test('keeps the primary entity when a relation target is mentioned', () {
    final intent = interpreter.interpret(
      'Crear una materia llamada Redes Voz con carrera Carrera Offline final',
      _schema(),
    );
    expect(intent.entity!.name, 'Materia');
    expect(intent.values['nombre'], 'Redes Voz');
    expect(intent.relationValues['carreraId'], 'Carrera Offline final');
  });

  test('update does not require unrelated required fields', () async {
    final base = _schema().entities.first;
    final entity = RuntimeEntity(
      name: base.name,
      endpoint: base.endpoint,
      idField: base.idField,
      displayField: base.displayField,
      operations: base.operations,
      fields: [
        ...base.fields,
        RuntimeField(
          name: 'requiredRelationId',
          type: 'relation',
          required: true,
          editable: true,
          readOnly: false,
          nullable: false,
          collection: false,
          relation: true,
          targetEntity: 'Carrera',
        ),
      ],
    );
    final intent = CommandIntent(
      action: CommandAction.update,
      entity: entity,
      recordId: 8,
      values: {'creditos': 6},
      originalText: 'Editar materia 8 cambiar creditos a 6',
    );
    final repository = _RecordingRepository();
    final executor = CommandExecutor(
      schema: RuntimeSchema(
        schemaVersion: '1',
        application: 'Test',
        version: '1',
        entities: [entity, ..._schema().entities.skip(1)],
      ),
      repository: repository,
    );
    final result = await executor.execute(intent);
    expect(result.success, isTrue);
    expect(repository.lastBody['nombre'], 'Sistemas');
    expect(repository.lastBody['carreraId'], 5);
    expect(repository.lastBody['creditos'], 6);
  });

  test('detects generic relation phrases through schema', () {
    final schema = RuntimeSchema(
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
            RuntimeField(name: 'categoriaIds', type: 'relation', required: false, editable: true, readOnly: false, nullable: true, collection: true, relation: true, targetEntity: 'Categoria'),
          ],
        ),
        RuntimeEntity(
          name: 'Categoria',
          endpoint: '/api/categorias',
          idField: 'id',
          displayField: 'nombre',
          operations: RuntimeOperations(list: true, get: true, create: true, update: true, delete: true),
          fields: [
            RuntimeField(name: 'nombre', type: 'string', required: true, editable: true, readOnly: false, nullable: false, collection: false, relation: false),
          ],
        ),
      ],
    );

    final intent = interpreter.interpret('Asocia el libro Cien años de soledad con la categoría Novela', schema);
    expect(intent.action, CommandAction.update);
    expect(intent.entity!.name, 'Libro');
    expect(intent.relationValues['categoriaIds'], 'Novela');
  });

  test('rejects invented ids and fields before execution', () async {
    final entity = RuntimeEntity(
      name: 'Libro',
      endpoint: '/api/libros',
      idField: 'id',
      displayField: 'titulo',
      operations: RuntimeOperations(list: true, get: true, create: true, update: true, delete: true),
      fields: [
        RuntimeField(name: 'titulo', type: 'string', required: true, editable: true, readOnly: false, nullable: false, collection: false, relation: false),
        RuntimeField(name: 'isbn', type: 'string', required: false, editable: true, readOnly: false, nullable: true, collection: false, relation: false),
        RuntimeField(name: 'categoriaIds', type: 'relation', required: false, editable: true, readOnly: false, nullable: true, collection: true, relation: true, targetEntity: 'Categoria'),
      ],
    );
    final schema = RuntimeSchema(
      schemaVersion: '1',
      application: 'Test',
      version: '1',
      entities: [
        entity,
        RuntimeEntity(
          name: 'Categoria',
          endpoint: '/api/categorias',
          idField: 'id',
          displayField: 'nombre',
          operations: RuntimeOperations(list: true, get: true, create: true, update: true, delete: true),
          fields: [RuntimeField(name: 'nombre', type: 'string', required: true, editable: true, readOnly: false, nullable: false, collection: false, relation: false)],
        ),
      ],
    );

    final repository = _RecordingRepository();
    final executor = CommandExecutor(schema: schema, repository: repository);
    final result = await executor.execute(CommandIntent(
      action: CommandAction.update,
      entity: entity,
      recordId: 7,
      values: {'isbn': '978-1-4651056340'},
      relationValues: {'categoriaIds': 'Novela'},
      originalText: 'Actualiza el libro Cien años de soledad y asigna la categoría Novela',
    ));

    expect(result.success, isFalse);
    expect(result.message, contains('No inventes'));
  });

  test('unknown entity and command remain unknown', () {
    expect(interpreter.interpret('listar pacientes', _schema()).entity, isNull);
    expect(interpreter.interpret('hacer algo', _schema()).action, CommandAction.unknown);
  });
}

class _RecordingRepository extends GenericRepository {
  Map<String, dynamic> lastBody = {};

  _RecordingRepository() : super();

  @override
  Future<Map<String, dynamic>> getById(
    RuntimeEntity entity,
    dynamic id,
  ) async => {
    entity.idField: id,
    'nombre': 'Sistemas',
    'creditos': 5,
    'carreraId': 5,
  };

  @override
  Future<Map<String, dynamic>> update(
    RuntimeEntity entity,
    dynamic id,
    Map<String, dynamic> body,
  ) async {
    lastBody = body;
    return body;
  }
}
