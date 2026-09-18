import 'local_llm_engine.dart';

class UnsupportedLocalLlmEngine implements LocalLlmEngine {
  @override
  bool get isAvailable => false;
  @override
  Future<void> initialize() async => throw StateError('LLM local no disponible en esta plataforma.');
  @override
  Future<String> generate(String prompt) async => throw StateError('LLM local no disponible en esta plataforma.');
  @override
  Future<String> generateChat({required String systemPrompt, required String userPrompt}) async =>
      throw StateError('LLM local no disponible en esta plataforma.');
  @override
  Future<void> clearContext() async {}
  @override
  Future<void> dispose() async {}
}

class LocalLlamaEngine extends UnsupportedLocalLlmEngine {
  LocalLlamaEngine({required Object modelManager});
}
