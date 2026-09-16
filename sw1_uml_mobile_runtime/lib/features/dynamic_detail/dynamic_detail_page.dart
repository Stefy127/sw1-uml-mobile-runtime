import 'package:flutter/material.dart';
import '../../core/api/relation_resolver.dart';
import '../../core/database/generic_repository.dart';
import '../../core/formatters/label_formatter.dart';
import '../../schema/model/runtime_schema.dart';
import '../dynamic_form/dynamic_form_page.dart';

class DynamicDetailPage extends StatefulWidget {
  final RuntimeEntity entity;
  final Map<String, dynamic> record;
  final RuntimeSchema schema;
  const DynamicDetailPage({super.key, required this.entity, required this.record, required this.schema});
  @override State<DynamicDetailPage> createState() => _DynamicDetailPageState();
}

class _DynamicDetailPageState extends State<DynamicDetailPage> {
  final _repository = GenericRepository();
  late final RelationResolver _resolver =
      RelationResolver.withRepository(_repository, widget.schema);
  Map<String, String> _values = {};
  bool _loading = true;
  @override void initState() { super.initState(); _resolve(); }
  Future<void> _resolve() async { final values = <String, String>{}; for (final field in widget.entity.fields) { if (field.collection) { values[field.name] = widget.record[field.name]?.toString() ?? '—'; } else if (field.relation) { values[field.name] = await _resolver.display(field, widget.record[field.name]); } else { values[field.name] = widget.record[field.name]?.toString() ?? '—'; } } if (mounted) setState(() { _values = values; _loading = false; }); }
  Future<void> _delete() async {
    final title = widget.record[widget.entity.displayField]?.toString() ?? widget.record[widget.entity.idField]?.toString() ?? widget.entity.name;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('¿Eliminar este registro?'), content: Text('${widget.entity.name}: $title'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar'))]));
    if (confirmed != true || !mounted) return;
    try { await _repository.delete(widget.entity, widget.record[widget.entity.idField]); if (mounted) Navigator.pop(context, true); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo eliminar. Puede tener registros relacionados.'))); }
  }
  @override Widget build(BuildContext context) { final title = widget.record[widget.entity.displayField]?.toString() ?? widget.entity.name; return Scaffold(appBar: AppBar(title: Text(title), actions: [if (widget.entity.operations.update) IconButton(tooltip: 'Editar', onPressed: () async { final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => DynamicFormPage(entity: widget.entity, existingRecord: widget.record, schema: widget.schema))); if (result == true && mounted) Navigator.pop(context, true); }, icon: const Icon(Icons.edit_outlined)), if (widget.entity.operations.delete) IconButton(tooltip: 'Eliminar', onPressed: _delete, icon: const Icon(Icons.delete_outline))]), body: _loading ? const Center(child: CircularProgressIndicator()) : ListView.separated(padding: const EdgeInsets.all(20), itemCount: widget.entity.fields.length, separatorBuilder: (_, __) => const SizedBox(height: 10), itemBuilder: (_, index) { final field = widget.entity.fields[index]; return Card(child: ListTile(title: Text(LabelFormatter.fromField(field.name)), subtitle: Text(_values[field.name] ?? '—'), trailing: field.readOnly ? const Icon(Icons.lock_outline, size: 18) : null)); })); }
}
