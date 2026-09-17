import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../core/database/generic_repository.dart';
import '../../schema/model/runtime_schema.dart';
import '../dynamic_list/dynamic_list_page.dart';
import 'command_executor.dart';
import 'command_intent.dart';
import 'local_command_interpreter.dart';

class CommandPage extends StatefulWidget {
  final RuntimeSchema schema;
  const CommandPage({super.key, required this.schema});
  @override State<CommandPage> createState() => _CommandPageState();
}

class _CommandPageState extends State<CommandPage> {
  final _controller = TextEditingController();
  final _interpreter = LocalCommandInterpreter();
  final _speech = SpeechToText();
  late final CommandExecutor _executor = CommandExecutor(schema: widget.schema, repository: GenericRepository());
  CommandIntent? _intent;
  String? _message;
  bool _listening = false, _busy = false, _speechAvailable = false;

  @override void initState() { super.initState(); _initSpeech(); }
  Future<void> _initSpeech() async { final available = await _speech.initialize(onError: (_) => setState(() => _speechAvailable = false)); if (mounted) setState(() => _speechAvailable = available); }
  Future<void> _listen() async { if (!_speechAvailable) { setState(() => _message = 'El reconocimiento de voz no está disponible. Puedes escribir el comando.'); return; } if (_listening) { await _speech.stop(); setState(() => _listening = false); return; } setState(() => _listening = true); await _speech.listen(listenOptions: SpeechListenOptions(localeId: 'es_BO', partialResults: true), onResult: (result) { if (mounted) setState(() => _controller.text = result.recognizedWords); }); }
  void _interpret() { final intent = _interpreter.interpret(_controller.text, widget.schema); setState(() { _intent = intent; _message = intent.entity == null ? 'No reconocí la entidad.' : null; }); }
  Future<void> _execute() async { final intent = _intent; if (intent == null) return; setState(() => _busy = true); try { final result = await _executor.execute(intent); if (!mounted) return; if (result.requiresConfirmation) { final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Confirmar'), content: Text(result.message), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar'))])); if (confirm == true) { final deleted = await _executor.execute(intent, confirmDelete: true); if (mounted) _finish(deleted.message); } } else if (result.entity != null && (intent.action == CommandAction.list || intent.action == CommandAction.get)) { if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DynamicListPage(entity: result.entity!))); } else { _finish(result.message); } } catch (e) { if (mounted) setState(() => _message = e.toString()); } finally { if (mounted) setState(() => _busy = false); } }
  void _finish(String message) { setState(() => _message = message); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))); }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comando')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Escribe una orden genérica o usa el micrófono.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Comando',
              hintText: 'crear una entidad con nombre ...',
              suffixIcon: IconButton(
                onPressed: _listen,
                icon: Icon(_listening ? Icons.stop : Icons.mic_none),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _interpret,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Interpretar'),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _message!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_intent != null && _intent!.entity != null) ...[
            _preview(_intent!),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy || _intent!.action == CommandAction.unknown
                  ? null
                  : _execute,
              icon: const Icon(Icons.play_arrow),
              label: Text(
                _intent!.action == CommandAction.list ||
                        _intent!.action == CommandAction.get
                    ? 'Abrir'
                    : 'Ejecutar',
              ),
            ),
          ],
        ],
      ),
    );
  }
  Widget _preview(CommandIntent intent) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Acción: ${intent.action.name}'), Text('Entidad: ${intent.entity!.name}'), for (final entry in intent.values.entries) Text('${entry.key}: ${entry.value}'), for (final entry in intent.relationValues.entries) Text('${entry.key}: ${entry.value}')])));
  @override void dispose() { _speech.stop(); _controller.dispose(); super.dispose(); }
}
