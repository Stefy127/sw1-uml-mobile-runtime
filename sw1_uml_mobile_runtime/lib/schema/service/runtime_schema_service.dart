import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/api/api_config.dart';
import '../../core/database/local_database.dart';
import '../model/runtime_schema.dart';

enum SchemaSource { online, cache }

class RuntimeSchemaService {
  static const _cacheKey = 'runtime_schema';
  SchemaSource? lastSource;

  Future<RuntimeSchema> load() async {
    try {
      final response = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/api/runtime-schema'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('No se pudo cargar runtime-schema. Código: ${response.statusCode}.');
      }
      final json = Map<String, dynamic>.from(jsonDecode(response.body));
      await LocalDatabase.put(_cacheKey, json);
      lastSource = SchemaSource.online;
      return RuntimeSchema.fromJson(json);
    } on http.ClientException catch (_) {
      // Solo los errores de red deben activar el fallback offline.
      final cached = await LocalDatabase.get(_cacheKey);
      if (cached is Map) {
        lastSource = SchemaSource.cache;
        return RuntimeSchema.fromJson(Map<String, dynamic>.from(cached));
      }
      throw Exception('No se pudo cargar runtime-schema y no existe cache local.');
    } on TimeoutException catch (_) {
      final cached = await LocalDatabase.get(_cacheKey);
      if (cached is Map) {
        lastSource = SchemaSource.cache;
        return RuntimeSchema.fromJson(Map<String, dynamic>.from(cached));
      }
      throw Exception('No se pudo cargar runtime-schema y no existe cache local.');
    }
  }
}
