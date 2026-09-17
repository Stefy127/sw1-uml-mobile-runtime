import 'package:flutter/material.dart';

import '../../schema/model/runtime_schema.dart';
import '../../schema/service/runtime_schema_service.dart';
import '../../core/widgets/app_content_container.dart';
import '../../core/sync/sync_coordinator.dart';
import '../dynamic_list/dynamic_list_page.dart';
import '../commands/command_page.dart';

class EntitiesPage extends StatefulWidget {
  const EntitiesPage({super.key});

  @override
  State<EntitiesPage> createState() => _EntitiesPageState();
}

class _EntitiesPageState extends State<EntitiesPage> {
  final RuntimeSchemaService _schemaService = RuntimeSchemaService();
  final SyncCoordinator _sync = SyncCoordinator.shared;

  late Future<RuntimeSchema> _schemaFuture;

  @override
  void initState() {
    super.initState();
    _schemaFuture = _schemaService.load();
  }

  void _reload() {
    setState(() {
      _schemaFuture = _schemaService.load();
    });
  }

  Future<void> _syncNow() async {
    final completed = await _sync.flush();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _sync.pendingCount == 0
              ? 'Sincronización completa'
              : 'No se pudieron sincronizar todos los cambios.',
        ),
      ),
    );
    if (completed > 0) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Entidades'),
        actions: [
          IconButton(
            tooltip: 'Comando',
            onPressed: () async {
              final schema = await _schemaFuture;
              if (!mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CommandPage(schema: schema),
                ),
              );
            },
            icon: const Icon(Icons.mic_none),
          ),
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<RuntimeSchema>(
        future: _schemaFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_off,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No se pudo cargar el runtime schema.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            );
          }

          final schema = snapshot.data;

          if (schema == null || schema.entities.isEmpty) {
            return const Center(
              child: Text('No se encontraron entidades.'),
            );
          }

          return AppContentContainer(child: Column(
            children: [
              if (_schemaService.lastSource == SchemaSource.cache)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Sin conexión · mostrando datos guardados'),
                  ),
                ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      schema.application,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Runtime schema · ${schema.schemaVersion} · ${schema.entities.length} entidades',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              AnimatedBuilder(
                animation: _sync,
                builder: (context, _) => _SyncBanner(
                  coordinator: _sync,
                  onSync: _syncNow,
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: schema.entities.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entity = schema.entities[index];

                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.table_chart_outlined),
                        ),
                        title: Text(entity.name),
                        subtitle: Text('${entity.fields.length} campos'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: entity.operations.list
                            ? () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => DynamicListPage(
                                      entity: entity,
                                    ),
                                  ),
                                );
                              }
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ],
          ));
        },
      ),
    );
  }
}

class _SyncBanner extends StatelessWidget {
  final SyncCoordinator coordinator;
  final Future<void> Function() onSync;

  const _SyncBanner({required this.coordinator, required this.onSync});

  @override
  Widget build(BuildContext context) {
    if (coordinator.pendingCount == 0 &&
        coordinator.state != SyncState.syncing &&
        coordinator.state != SyncState.syncError) {
      return const SizedBox.shrink();
    }
    final syncing = coordinator.state == SyncState.syncing;
    final error = coordinator.state == SyncState.syncError;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              syncing
                  ? 'Sincronizando...'
                  : error
                      ? '${coordinator.pendingCount} cambios pendientes · Error al sincronizar'
                      : '${coordinator.pendingCount} cambios pendientes',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (!syncing)
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
