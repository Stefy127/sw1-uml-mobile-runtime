import 'package:shared_preferences/shared_preferences.dart';

enum SpeechPreference { offline, system }

class SpeechPreferenceStore {
  static const _key = 'speech_preference';

  Future<SpeechPreference> read() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_key) == SpeechPreference.system.name
        ? SpeechPreference.system
        : SpeechPreference.offline;
  }

  Future<void> write(SpeechPreference value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, value.name);
  }
}
