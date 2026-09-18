import 'package:shared_preferences/shared_preferences.dart';

enum LlmInterpretationMode { localAi, localRules }

class LlmPreferenceStore {
  static const _key = 'command_interpretation_mode';

  Future<LlmInterpretationMode> read() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_key) == LlmInterpretationMode.localRules.name
        ? LlmInterpretationMode.localRules
        : LlmInterpretationMode.localAi;
  }

  Future<void> write(LlmInterpretationMode value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, value.name);
  }
}
