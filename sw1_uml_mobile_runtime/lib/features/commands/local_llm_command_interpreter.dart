import 'package:flutter/foundation.dart';

import '../../schema/model/runtime_schema.dart';
import 'command_intent.dart';
import 'command_interpreter.dart';
import 'llm_intent_parser.dart';
import '../llm/local_llm_engine.dart';
import 'local_command_interpreter.dart';

class LocalLlmCommandInterpreter extends CommandInterpreter {
  final LocalLlmEngine engine;
  final CommandInterpreter fallback;
  final LlmIntentParser parser;

  LocalLlmCommandInterpreter({
    required this.engine,
    CommandInterpreter? fallback,
    this.parser = const LlmIntentParser(),
  }) : fallback = fallback ?? LocalCommandInterpreter();

  @override
  CommandIntent interpret(String text, RuntimeSchema schema) => fallback.interpret(text, schema);

  @override
  Future<CommandIntent> interpretAsync(String text, RuntimeSchema schema) async {
    debugPrint('LLM REQUEST: $text');
    try {
      if (!engine.isAvailable) await engine.initialize();
      final raw = await engine.generateChat(
        systemPrompt: _systemPrompt(schema),
        userPrompt: text,
      );
      debugPrint('LLM RAW OUTPUT: $raw');
      final intent = parser.parse(raw, text, schema);
      if (intent.entity != null && intent.confidence >= 0.5 && intent.ambiguities.isEmpty) {
        debugPrint('LLM PARSE SUCCESS: ${intent.action.name} ${intent.entity!.name}');
        return intent;
      }
      debugPrint('LLM PARSE FAILED: ${intent.ambiguities.join(', ')}');
    } catch (_) {
      // El fallback determinista es la ruta segura cuando el modelo no está listo.
    }
    debugPrint('Using rule-based fallback');
    return fallback.interpret(text, schema);
  }

  String _systemPrompt(RuntimeSchema schema) {
    final schemaText = schema.entities.map((entity) {
      final fields = entity.fields.map((field) {
        final relation = field.relation ? ' relation->${field.targetEntity}' : '';
        return '${field.name}:${field.type}$relation';
      }).join(', ');
      return '${entity.name} [id=${entity.idField}, display=${entity.displayField}] {$fields}';
    }).join('\n');
    return '''Eres un intérprete CRUD local. No ejecutes acciones y no inventes datos.
Devuelve ÚNICAMENTE JSON válido, sin markdown ni explicación.
Acciones válidas: create, update, delete, list, get. Si la frase es de relación (asocia, relaciona, vincula, asigna, quita, desasocia) usa action="update" y describe la relación en "relations".
Usa solo entidades y campos del esquema. Si hay duda usa action="unknown" y ambiguities.
Nunca inventes IDs, ISBN, nombres, fechas, precios, cantidades ni relaciones no mencionadas.
Formato exacto: {"action":"...","entity":"...","recordId":null,"values":{},"relations":{},"confidence":"high","ambiguities":[]}
Si el comando está completamente resuelto, devuelve "ambiguities": []. No uses "ambiguities": ["unknown"]. Usa "unknown" únicamente como action cuando no puedas resolver el comando.
Para relation usa relations con el texto visible; para update no inventes campos omitidos.
Reconoce sinónimos: crear=crea, agrega, registra, añade; actualizar=actualiza, modifica, cambia, edita; eliminar=elimina, borra, quita; consultar=muestra, busca, dame, consulta; listar=lista, muestra todos; relacionar=asocia, relaciona, vincula, asigna, agrega a; desrelacionar=quita de, desvincula, desasocia, elimina de.
/no_think
Ejemplo de salida update: {"action":"update","entity":"Materia","recordId":"8","values":{"creditos":6},"relations":{},"confidence":"high","ambiguities":[]}
GET es un registro específico identificado por ID; LIST son todos los registros de una entidad.
Ejemplo GET: "mostrame la materia ocho" -> {"action":"get","entity":"Materia","recordId":"8","values":{},"relations":{},"confidence":"high","ambiguities":[]}
Ejemplo GET: "quiero ver la persona cuatro" -> {"action":"get","entity":"Persona","recordId":"4","values":{},"relations":{},"confidence":"high","ambiguities":[]}
Ejemplo LIST: "mostrame todas las materias" -> {"action":"list","entity":"Materia","recordId":null,"values":{},"relations":{},"confidence":"high","ambiguities":[]}
Ejemplo LIST: "lista las carreras" -> {"action":"list","entity":"Carrera","recordId":null,"values":{},"relations":{},"confidence":"high","ambiguities":[]}
Esquema:
$schemaText
''';
  }
}
