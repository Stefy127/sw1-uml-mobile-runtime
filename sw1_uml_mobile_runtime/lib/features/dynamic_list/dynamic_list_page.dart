import 'package:flutter/material.dart';

import '../../core/database/generic_repository.dart';
import '../../core/formatters/label_formatter.dart';
import '../../core/widgets/app_content_container.dart';
import '../../core/sync/sync_coordinator.dart';
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
  final GenericRepository _repository = GenericRepository();
  final SyncCoordinator _sync = SyncCoordinator.shared;
  final RuntimeSchemaService _schemas = RuntimeSchemaService();

  late Future<RepositoryResult> _future;
  RuntimeSchema? _schema;

  @override
  void initState() {
    super.initState();
    _future = _repository.getAllWithSource(widget.entity);
  }

  void _reload() {
    setState(() {
      _future = _repository.getAllWithSource(widget.entity);
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
      body: FutureBuilder<RepositoryResult>(
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

          final result = snapshot.data!;
          final records = result.records;

          if (records.isEmpty) {
            return EmptyState(
              message: 'No hay registros de ${widget.entity.name}.',
            );
          }

          return AppContentContainer(
            child: Column(
              children: [
                AnimatedBuilder(
                  animation: _sync,
                  builder: (context, _) => _ListSyncStatus(
                    coordinator: _sync,
                    onSync: _reload,
                  ),
                ),
                if (result.fromCache)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Sin conexión · mostrando datos guardados'),
                    ),
                  ),
                Expanded(
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
                ),
              ],
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

class _ListSyncStatus extends StatelessWidget {
  final SyncCoordinator coordinator;
  final VoidCallback onSync;

  const _ListSyncStatus({required this.coordinator, required this.onSync});

  @override
  Widget build(BuildContext context) {
    if (coordinator.pendingCount == 0 && coordinator.state != SyncState.syncError) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              coordinator.state == SyncState.syncing
                  ? 'Sincronizando...'
                  : '${coordinator.pendingCount} cambios pendientes',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (coordinator.state != SyncState.syncing)
            TextButton.icon(
              onPressed: onSync,
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('Sincronizar'),
            ),
        ],
      ),
    );
  }
}
