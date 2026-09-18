import 'package:llama_flutter_android/llama_flutter_android.dart';

import 'llm_model_manager.dart';
import 'local_llm_engine.dart';

class LocalLlamaEngine implements LocalLlmEngine {
  final LlmModelManager modelManager;
  final LlamaController _controller = LlamaController();
  bool _initialized = false;

  LocalLlamaEngine({required this.modelManager});

  @override
  bool get isAvailable => _initialized;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    if (!await modelManager.isInstalled()) {
      throw StateError('El modelo LLM local aún no está instalado.');
    }
    final gpu = await _controller.detectGpu();
    await _controller.loadModel(
      modelPath: await modelManager.modelPath(),
      contextSize: 2048,
      threads: 4,
      gpuLayers: gpu.recommendedGpuLayers,
    );
    _initialized = true;
  }

  @override
  Future<String> generate(String prompt) async {
    if (!_initialized) await initialize();
    final buffer = StringBuffer();
    await for (final token in _controller.generate(
      prompt: prompt,
      maxTokens: 128,
      temperature: 0.2,
      topP: 0.8,
      topK: 20,
      repeatPenalty: 1.1,
    )) {
      buffer.write(token);
    }
    return buffer.toString();
  }

  @override
  Future<String> generateChat({required String systemPrompt, required String userPrompt}) async {
    if (!_initialized) await initialize();
    await _controller.clearContext();
    final buffer = StringBuffer();
    await for (final token in _controller.generateChat(
      messages: [
        ChatMessage(role: 'system', content: systemPrompt),
        ChatMessage(role: 'user', content: '$userPrompt\n/no_think'),
      ],
      maxTokens: 128,
      temperature: 0.2,
      topP: 0.8,
      topK: 20,
      repeatPenalty: 1.1,
    )) {
      buffer.write(token);
    }
    return buffer.toString();
  }

  @override
  Future<void> clearContext() => _controller.clearContext();

  @override
  Future<void> dispose() async {
    _initialized = false;
    await _controller.dispose();
  }
}
