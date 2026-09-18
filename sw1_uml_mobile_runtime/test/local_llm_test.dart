import 'package:flutter_test/flutter_test.dart';
import 'package:sw1_uml_mobile_runtime/features/commands/command_intent.dart';
import 'package:sw1_uml_mobile_runtime/features/commands/llm_intent_parser.dart';
import 'package:sw1_uml_mobile_runtime/features/commands/local_llm_command_interpreter.dart';
import 'package:sw1_uml_mobile_runtime/features/llm/local_llm_engine.dart';
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
          operations: RuntimeOperations(list: true, get: true, create: true, update: true, delete: true),
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
          fields: [RuntimeField(name: 'nombre', type: 'string', required: true, editable: true, readOnly: false, nullable: false, collection: false, relation: false)],
        ),
      ],
    );

class _FakeEngine implements LocalLlmEngine {
  final String response;
  _FakeEngine(this.response);
  @override
  bool get isAvailable => true;
  @override
  Future<void> initialize() async {}
  @override
  Future<String> generate(String prompt) async => response;
  @override
  Future<String> generateChat({required String systemPrompt, required String userPrompt}) async => response;
  @override
  Future<void> clearContext() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  test('parses valid JSON and validates schema fields', () {
    final intent = const LlmIntentParser().parse(
      '{"action":"update","entity":"Materia","recordId":"8","values":{"creditos":6},"relations":{},"confidence":"high","ambiguities":[]}',
      'la materia ocho tiene seis créditos',
      _schema(),
    );
    expect(intent.action, CommandAction.update);
    expect(intent.recordId, 8);
    expect(intent.values, {'creditos': 6});
    expect(intent.confidence, greaterThan(0.5));
  });

  test('rejects malformed JSON and unknown entity', () {
    final parser = const LlmIntentParser();
    expect(parser.parse('no json', 'haz cualquier cosa', _schema()).action, CommandAction.unknown);
    final intent = parser.parse('{"action":"list","entity":"Paciente","ambiguities":[]}', 'listar pacientes', _schema());
    expect(intent.entity, isNull);
    expect(intent.ambiguities, isNotEmpty);
  });

  test('recovers JSON after Qwen thinking output', () {
    final intent = const LlmIntentParser().parse(
      '<think>reasoning interno</think>{"action":"update","entity":"Materia","recordId":"8","values":{"creditos":6},"relations":{},"confidence":"high","ambiguities":[]}',
      'la materia ocho ahora tiene seis créditos',
      _schema(),
    );
    expect(intent.action, CommandAction.update);
    expect(intent.entity!.name, 'Materia');
    expect(intent.recordId, 8);
    expect(intent.values['creditos'], 6);
  });

  test('ignores generic unknown ambiguity for a valid update', () {
    final intent = const LlmIntentParser().parse(
      '{"action":"update","entity":"Materia","recordId":"8","values":{"creditos":6},"relations":{},"confidence":"high","ambiguities":["unknown"]}',
      'la materia ocho ahora tiene seis créditos',
      _schema(),
    );
    expect(intent.action, CommandAction.update);
    expect(intent.entity!.name, 'Materia');
    expect(intent.recordId, 8);
    expect(intent.values['creditos'], 6);
    expect(intent.ambiguities, isEmpty);
    expect(intent.confidence, greaterThan(0.5));
  });

  test('parses GET and LIST intents deterministically', () {
    final parser = const LlmIntentParser();
    final get = parser.parse(
      '{"action":"get","entity":"Materia","recordId":"8","values":{},"relations":{},"confidence":"high","ambiguities":[]}',
      'mostrame la materia ocho',
      _schema(),
    );
    final list = parser.parse(
      '{"action":"list","entity":"Materia","recordId":null,"values":{},"relations":{},"confidence":"high","ambiguities":[]}',
      'mostrame todas las materias',
      _schema(),
    );
    expect(get.action, CommandAction.get);
    expect(get.recordId, 8);
    expect(get.values, isEmpty);
    expect(get.relationValues, isEmpty);
    expect(list.action, CommandAction.list);
    expect(list.recordId, isNull);
    expect(list.values, isEmpty);
    expect(list.relationValues, isEmpty);
  });

  test('rejects GET or LIST with incompatible values', () {
    final parser = const LlmIntentParser();
    final get = parser.parse(
      '{"action":"get","entity":"Materia","recordId":8,"values":{"creditos":6},"relations":{},"confidence":"high","ambiguities":[]}',
      'mostrame la materia ocho',
      _schema(),
    );
    final list = parser.parse(
      '{"action":"list","entity":"Materia","recordId":null,"values":{"creditos":6},"relations":{},"confidence":"high","ambiguities":[]}',
      'mostrame todas las materias',
      _schema(),
    );
    expect(get.confidence, lessThan(0.5));
    expect(get.values, isEmpty);
    expect(list.confidence, lessThan(0.5));
    expect(list.values, isEmpty);
  });

  test('rejects a concrete ambiguity', () {
    final intent = const LlmIntentParser().parse(
      '{"action":"update","entity":"Materia","recordId":"8","values":{"creditos":6},"relations":{},"confidence":"high","ambiguities":["Falta identificar la materia"]}',
      'cambia algo',
      _schema(),
    );
    expect(intent.entity, isNotNull);
    expect(intent.confidence, lessThan(0.5));
    expect(intent.ambiguities, contains('Falta identificar la materia'));
  });

  test('marks invented fields as unsafe', () {
    final intent = const LlmIntentParser().parse(
      '{"action":"update","entity":"Materia","recordId":8,"values":{"inventado":true},"confidence":"high","ambiguities":[]}',
      'cambia algo',
      _schema(),
    );
    expect(intent.values, isEmpty);
    expect(intent.confidence, lessThan(0.5));
    expect(intent.ambiguities, isNotEmpty);
  });

  test('uses deterministic fallback when fake LLM output is invalid', () async {
    final interpreter = LocalLlmCommandInterpreter(engine: _FakeEngine('not json'));
    final intent = await interpreter.interpretAsync('listar materias', _schema());
    expect(intent.action, CommandAction.list);
    expect(intent.entity!.name, 'Materia');
  });

  test('keeps DELETE safe and requires an ID', () {
    final intent = const LlmIntentParser().parse(
      '{"action":"delete","entity":"Materia","recordId":null,"values":{},"relations":{},"confidence":"high","ambiguities":[]}',
      'elimina todo',
      _schema(),
    );
    expect(intent.action, CommandAction.delete);
    expect(intent.confidence, lessThan(0.5));
    expect(intent.ambiguities, isNotEmpty);
  });
}
