import '../../schema/model/runtime_schema.dart';
import 'command_intent.dart';
import 'command_interpreter.dart';

class CommandInterpreterRouter extends CommandInterpreter {
  final CommandInterpreter primary;
  final CommandInterpreter fallback;

  CommandInterpreterRouter({required this.primary, required this.fallback});

  @override
  CommandIntent interpret(String text, RuntimeSchema schema) => fallback.interpret(text, schema);

  @override
  Future<CommandIntent> interpretAsync(String text, RuntimeSchema schema) async {
    final intent = await primary.interpretAsync(text, schema);
    if (intent.entity != null && intent.confidence >= 0.5 && intent.ambiguities.isEmpty) return intent;
    return fallback.interpret(text, schema);
  }
}
