import 'package:flutter/material.dart';

import '../../schema/model/runtime_schema.dart';
import '../../schema/service/runtime_schema_service.dart';
import '../../core/widgets/app_content_container.dart';
import '../dynamic_list/dynamic_list_page.dart';

class EntitiesPage extends StatefulWidget {
  const EntitiesPage({super.key});

  @override
  State<EntitiesPage> createState() => _EntitiesPageState();
}

class _EntitiesPageState extends State<EntitiesPage> {
  final RuntimeSchemaService _schemaService = RuntimeSchemaService();

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Entidades'),
        actions: [
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
