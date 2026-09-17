import '../../schema/model/runtime_schema.dart';
import 'command_intent.dart';

/// Contrato local para poder sustituir el intérprete por otro proveedor.
abstract class CommandInterpreter {
  CommandIntent interpret(String text, RuntimeSchema schema);
}
