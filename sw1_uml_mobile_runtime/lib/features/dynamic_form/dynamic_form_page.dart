import 'package:flutter/material.dart';
import '../../core/api/generic_api_service.dart';
import '../../core/formatters/label_formatter.dart';
import '../../schema/model/runtime_schema.dart';
import '../../schema/service/runtime_schema_service.dart';

class DynamicFormPage extends StatefulWidget {
  final RuntimeEntity entity;
  final Map<String, dynamic>? existingRecord;
  final RuntimeSchema? schema;
  const DynamicFormPage({super.key, required this.entity, this.existingRecord, this.schema});
  bool get isEditing => existingRecord != null;
  @override State<DynamicFormPage> createState() => _DynamicFormPageState();
}

class _DynamicFormPageState extends State<DynamicFormPage> {
  final _key = GlobalKey<FormState>();
  final _api = GenericApiService();
  final _schemaService = RuntimeSchemaService();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _booleans = {};
  final Map<String, dynamic> _relations = {};
  RuntimeSchema? _schema;
  bool _loading = true, _saving = false;
  String? _error;
  List<RuntimeField> get _fields => widget.entity.fields.where((f) => f.editable && !f.readOnly && !f.collection && f.name != widget.entity.idField).toList();
  @override void initState() { super.initState(); _schema = widget.schema; _prepare(); _loadSchema(); }
  void _prepare() { for (final field in _fields) { final value = widget.existingRecord?[field.name]; if (field.relation) _relations[field.name] = value; else if (field.type == 'boolean') _booleans[field.name] = value == true; else _controllers[field.name] = TextEditingController(text: value?.toString() ?? ''); } }
  Future<void> _loadSchema() async { try { _schema ??= await _schemaService.load(); if (mounted) setState(() => _loading = false); } catch (e) { if (mounted) setState(() { _loading = false; _error = e.toString(); }); } }
  RuntimeEntity? _target(String? name) => _schema?.entityByName(name);
  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    final body = <String, dynamic>{};
    for (final field in _fields) { final key = field.requestField ?? field.name; if (field.relation) { if (_relations[field.name] != null) body[key] = _relations[field.name]; continue; } if (field.type == 'boolean') { body[key] = _booleans[field.name] ?? false; continue; } final text = _controllers[field.name]?.text.trim() ?? ''; if (text.isEmpty && !field.required) continue; body[key] = field.type == 'integer' ? int.tryParse(text) : field.type == 'decimal' ? double.tryParse(text) : text; }
    setState(() { _saving = true; _error = null; });
    try { final id = widget.existingRecord?[widget.entity.idField]; if (widget.isEditing) { await _api.update(widget.entity.endpoint, id, body); } else { await _api.create(widget.entity.endpoint, body); } if (mounted) Navigator.of(context).pop(true); } catch (e) { if (mounted) setState(() => _error = e.toString()); } finally { if (mounted) setState(() => _saving = false); }
  }
  @override Widget build(BuildContext context) { final title = widget.isEditing ? 'Editar ${widget.entity.name}' : 'Nuevo ${widget.entity.name}'; if (_loading) return Scaffold(appBar: AppBar(title: Text(title)), body: const Center(child: CircularProgressIndicator())); return Scaffold(appBar: AppBar(title: Text(title)), body: Form(key: _key, child: ListView(padding: const EdgeInsets.all(20), children: [if (_error != null) Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)))), for (final field in _fields) ...[_buildField(field), const SizedBox(height: 14)], if (widget.entity.fields.any((f) => f.collection)) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('Las colecciones se conservan sin edición en este formulario.', style: Theme.of(context).textTheme.bodySmall)), FilledButton.icon(onPressed: _saving ? null : _save, icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined), label: Text(_saving ? 'Guardando...' : 'Guardar'))]))); }
  Widget _buildField(RuntimeField field) { if (field.relation) return _relationField(field); if (field.type == 'boolean') return SwitchListTile(title: Text(_label(field)), value: _booleans[field.name] ?? false, onChanged: (v) => setState(() => _booleans[field.name] = v)); if (field.type == 'date' || field.type == 'datetime') return _dateField(field); return TextFormField(controller: _controllers[field.name], keyboardType: field.type == 'integer' ? TextInputType.number : field.type == 'decimal' ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text, decoration: InputDecoration(labelText: _label(field)), validator: (value) { if (field.required && (value == null || value.trim().isEmpty)) return 'Este campo es obligatorio.'; if (value != null && value.trim().isNotEmpty && field.type == 'integer' && int.tryParse(value.trim()) == null) return 'Ingrese un entero válido.'; if (value != null && value.trim().isNotEmpty && field.type == 'decimal' && double.tryParse(value.trim()) == null) return 'Ingrese un número válido.'; return null; }); }
  Widget _dateField(RuntimeField field) => TextFormField(controller: _controllers[field.name], readOnly: true, decoration: InputDecoration(labelText: _label(field), suffixIcon: const Icon(Icons.calendar_month_outlined)), onTap: () async { final date = await showDatePicker(context: context, firstDate: DateTime(1900), lastDate: DateTime(2200), initialDate: DateTime.tryParse(_controllers[field.name]!.text) ?? DateTime.now()); if (date == null || !mounted) return; var value = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'; if (field.type == 'datetime') { final time = await showTimePicker(context: context, initialTime: TimeOfDay.now()); if (time != null) value += 'T${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00'; } _controllers[field.name]!.text = value; });
  Widget _relationField(RuntimeField field) { final target = _target(field.targetEntity); if (target == null) return const Text('Entidad relacionada no disponible.'); return FutureBuilder<List<Map<String, dynamic>>>(future: _api.getAll(target.endpoint), builder: (context, snapshot) { if (!snapshot.hasData) return const LinearProgressIndicator(); return DropdownButtonFormField<dynamic>(value: _relations[field.name], decoration: InputDecoration(labelText: _label(field)), items: snapshot.data!.map((r) => DropdownMenuItem(value: r[target.idField], child: Text(r[target.displayField]?.toString() ?? '${target.name} #${r[target.idField]}'))).toList(), onChanged: (v) => setState(() => _relations[field.name] = v), validator: (v) => field.required && v == null ? 'Seleccione una opción.' : null); }); }
  String _label(RuntimeField f) => '${LabelFormatter.fromField(f.name)}${f.required ? ' *' : ''}';
  @override void dispose() { for (final c in _controllers.values) c.dispose(); super.dispose(); }
}
