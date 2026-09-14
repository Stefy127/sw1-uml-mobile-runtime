import 'package:flutter/material.dart';

import '../../core/api/generic_api_service.dart';
import '../../core/formatters/label_formatter.dart';
import '../../core/widgets/app_content_container.dart';
import '../../schema/model/runtime_schema.dart';
import '../../schema/service/runtime_schema_service.dart';
import '../dynamic_detail/dynamic_detail_page.dart';
import '../dynamic_form/dynamic_form_page.dart';

class DynamicListPage extends StatefulWidget {
  final RuntimeEntity entity;

  const DynamicListPage({
    super.key,
    required this.entity,
  });

  @override
  State<DynamicListPage> createState() => _DynamicListPageState();
}

class _DynamicListPageState extends State<DynamicListPage> {
  final GenericApiService _api = GenericApiService();
  final RuntimeSchemaService _schemas = RuntimeSchemaService();

  late Future<List<Map<String, dynamic>>> _future;
  RuntimeSchema? _schema;

  @override
  void initState() {
    super.initState();
    _future = _api.getAll(widget.entity.endpoint);
  }

  void _reload() {
    setState(() {
      _future = _api.getAll(widget.entity.endpoint);
    });
  }

  Future<void> _openNewForm() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DynamicFormPage(
          entity: widget.entity,
          schema: _schema,
        ),
      ),
    );

    if (result == true) {
      _reload();
    }
  }

  Future<void> _openDetail(Map<String, dynamic> record) async {
    _schema ??= await _schemas.load();

    if (!mounted) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DynamicDetailPage(
          entity: widget.entity,
          record: record,
          schema: _schema!,
        ),
      ),
    );

    if (result == true) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entity.name),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: widget.entity.operations.create
          ? FloatingActionButton.extended(
              onPressed: _openNewForm,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo'),
            )
          : null,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingState();
          }

          if (snapshot.hasError) {
            return ErrorState(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final records = snapshot.data ?? [];

          if (records.isEmpty) {
            return EmptyState(
              message: 'No hay registros de ${widget.entity.name}.',
            );
          }

          return AppContentContainer(
            child: RefreshIndicator(
              onRefresh: () async {
                _reload();
                await _future;
              },
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                itemCount: records.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final record = records[index];

                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 5,
                      ),
                      title: Text(
                        _title(record),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: _subtitle(record).isEmpty
                          ? null
                          : Text(
                              _subtitle(record),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                      trailing: widget.entity.operations.get
                          ? const Icon(Icons.chevron_right)
                          : null,
                      onTap: widget.entity.operations.get
                          ? () => _openDetail(record)
                          : null,
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  String _title(Map<String, dynamic> record) {
    final display = record[widget.entity.displayField];
    if (display != null) {
      return display.toString();
    }

    final id = record[widget.entity.idField];
    return id == null ? widget.entity.name : '${widget.entity.name} #$id';
  }

  String _subtitle(Map<String, dynamic> record) {
    return record.entries
        .where(
          (entry) =>
              entry.key != widget.entity.displayField &&
              entry.key != widget.entity.idField,
        )
        .take(3)
        .map(
          (entry) =>
              '${LabelFormatter.fromField(entry.key)}: ${entry.value ?? '—'}',
        )
        .join(' · ');
  }
}
