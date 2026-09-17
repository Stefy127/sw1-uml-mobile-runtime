import 'package:flutter/material.dart';

import '../../core/database/generic_repository.dart';
import '../../schema/model/runtime_schema.dart';
import '../dynamic_detail/dynamic_detail_page.dart';
import '../dynamic_list/dynamic_list_page.dart';
import '../speech/model_manager.dart';
import '../speech/offline_sherpa_speech_recognizer.dart';
import '../speech/speech_preference_store.dart';
import '../speech/speech_recognizer_engine.dart';
import '../speech/system_speech_recognizer_adapter.dart';
import 'command_executor.dart';
import 'command_intent.dart';
import 'local_command_interpreter.dart';

class CommandPage extends StatefulWidget {
  final RuntimeSchema schema;
  const CommandPage({super.key, required this.schema});

  @override
  State<CommandPage> createState() => _CommandPageState();
}

class _CommandPageState extends State<CommandPage> {
  final _controller = TextEditingController();
  final _interpreter = LocalCommandInterpreter();
  final _modelManager = ModelManager();
  final _preferences = SpeechPreferenceStore();
  late final CommandExecutor _executor = CommandExecutor(
    schema: widget.schema,
    repository: GenericRepository(),
  );
  CommandIntent? _intent;
  SpeechRecognizerEngine? _engine;
  SpeechPreference _speechPreference = SpeechPreference.offline;
  String? _message;
  String _voiceStatus = 'Listo';
  ModelInstallProgress? _downloadProgress;
  bool _installingModel = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSpeechPreference();
  }

  Future<void> _loadSpeechPreference() async {
    final value = await _preferences.read();
    if (mounted) setState(() => _speechPreference = value);
  }

  Future<void> _onMicrophone() async {
    if (_installingModel) return;
    if (_engine?.isListening == true) {
      await _engine!.stopListening();
      if (mounted) setState(() => _voiceStatus = 'Listo');
      return;
    }
    if (_speechPreference == SpeechPreference.system) {
      await _startEngine(SystemSpeechRecognizerAdapter());
      return;
    }
    if (!await _modelManager.isInstalled()) {
      await _showModelDialog();
      return;
    }
    await _startEngine(OfflineSherpaSpeechRecognizer(modelManager: _modelManager));
  }

  Future<void> _showModelDialog() async {
    final install = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Voz offline'),
        content: const Text('Para usar voz sin internet necesitas instalar el modelo local.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Instalar')),
        ],
      ),
    );
    if (install != true || !mounted) return;
    setState(() {
      _installingModel = true;
      _voiceStatus = 'Descargando modelo';
    });
    try {
      await _modelManager.download(
        onProgress: (progress) => mounted
            ? setState(() => _downloadProgress = progress)
            : null,
        onStatus: (status) => mounted
            ? setState(() => _voiceStatus = status)
            : null,
      );
      if (mounted) {
        setState(() {
          _downloadProgress = null;
          _installingModel = false;
          _voiceStatus = 'Modelo instalado';
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Modelo offline instalado.')));
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _downloadProgress = null;
          _voiceStatus = 'Error';
          _message = 'No se pudo completar la descarga del modelo. Puedes intentarlo nuevamente.';
        });
        setState(() => _installingModel = false);
      }
    }
  }

  Future<void> _startEngine(SpeechRecognizerEngine engine) async {
    try {
      setState(() => _voiceStatus = 'Preparando reconocimiento');
      await engine.initialize();
      await engine.startListening(onText: (text) {
        if (!mounted) return;
        _controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        setState(() => _voiceStatus = 'Escuchando...');
      });
      _engine = engine;
      if (mounted) setState(() => _voiceStatus = 'Escuchando...');
    } catch (error) {
      await engine.dispose();
      if (!mounted) return;
      if (engine is OfflineSherpaSpeechRecognizer) {
        final useSystem = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Voz offline no disponible'),
            content: Text('$error\n\n¿Usar reconocimiento del sistema?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Usar sistema')),
            ],
          ),
        );
        if (useSystem == true) await _startEngine(SystemSpeechRecognizerAdapter());
      } else {
        setState(() { _voiceStatus = 'Error'; _message = error.toString(); });
      }
    }
  }

  Future<void> _changeSpeechPreference(SpeechPreference value) async {
    await _preferences.write(value);
    if (mounted) setState(() => _speechPreference = value);
  }

  void _interpret() {
    final intent = _interpreter.interpret(_controller.text, widget.schema);
    setState(() {
      _intent = intent;
      _message = intent.entity == null ? 'No reconocí la entidad.' : null;
    });
  }

  Future<void> _execute() async {
    final intent = _intent;
    if (intent == null) return;
    setState(() => _busy = true);
    try {
      final result = await _executor.execute(intent);
      if (!mounted) return;
      if (result.requiresConfirmation) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Confirmar'),
            content: Text(result.message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar')),
            ],
          ),
        );
        if (confirmed == true) {
          final deleted = await _executor.execute(intent, confirmDelete: true);
          if (mounted) _finish(deleted.message);
        }
      } else if (!result.success) {
        _finish(result.message);
      } else if (intent.action == CommandAction.get) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DynamicDetailPage(entity: result.entity!, record: result.body, schema: widget.schema)));
      } else if (intent.action == CommandAction.list) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DynamicListPage(entity: result.entity!)));
      } else {
        _finish(result.message);
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finish(String message) {
    setState(() => _message = message);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final intent = _intent;
    final canExecute = intent != null && intent.entity != null && intent.action != CommandAction.unknown && intent.confidence >= 0.5 && intent.ambiguities.isEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Comando')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('El reconocimiento offline se procesa en este dispositivo.'),
          const SizedBox(height: 12),
          DropdownButtonFormField<SpeechPreference>(
            value: _speechPreference,
            decoration: const InputDecoration(labelText: 'Reconocimiento de voz'),
            items: const [
              DropdownMenuItem(value: SpeechPreference.offline, child: Text('Offline local')),
              DropdownMenuItem(value: SpeechPreference.system, child: Text('Sistema')),
            ],
            onChanged: (value) { if (value != null) _changeSpeechPreference(value); },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Comando',
              hintText: 'crear una entidad con nombre ...',
              suffixIcon: IconButton(onPressed: _installingModel ? null : _onMicrophone, icon: Icon(_installingModel ? Icons.downloading : (_engine?.isListening == true ? Icons.stop : Icons.mic_none))),
            ),
          ),
          if (_downloadProgress != null) ...[
            LinearProgressIndicator(value: _downloadProgress!.overallFraction),
            Text(_downloadProgressLabel()),
            /*
              'Descargando ${_downloadProgress!.fileName}: '
              '${(_downloadProgress!.fileFraction * 100).floor()}% — '
              '${(_downloadProgress!.downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB / '
              '${(_downloadProgress!.totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
            ),
            */
          ],
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(_voiceStatus)),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _interpret, icon: const Icon(Icons.auto_awesome), label: const Text('Interpretar')),
          if (_message != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (intent?.entity != null) ...[
            _preview(intent!),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: _busy || !canExecute ? null : _execute, icon: const Icon(Icons.play_arrow), label: Text(intent.action == CommandAction.list || intent.action == CommandAction.get ? 'Abrir' : 'Ejecutar')),
          ],
        ],
      ),
    );
  }

  String _downloadProgressLabel() {
    final progress = _downloadProgress!;
    final fraction = progress.fileFraction;
    if (fraction == null) return 'Descargando ${progress.fileName}...';
    return 'Descargando ${progress.fileName}: '
        '${((fraction * 100).clamp(0, 100)).floor()}% - '
        '${(progress.downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB / '
        '${(progress.totalBytes! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _preview(CommandIntent intent) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Acción: ${intent.action.name}'),
            Text('Entidad: ${intent.entity!.name}'),
            if (intent.recordId != null) Text('ID: ${intent.recordId}'),
            for (final entry in intent.values.entries) Text('${entry.key}: ${entry.value}'),
            for (final entry in intent.relationValues.entries) Text('${entry.key}: ${entry.value}'),
          ]),
        ),
      );

  @override
  void dispose() {
    _engine?.dispose();
    _controller.dispose();
    super.dispose();
  }
}
