import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class GenericApiService {
  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');
  static const _headers = {'Content-Type': 'application/json'};
  void _ensureSuccess(http.Response response, String action) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('$action. Código: ${response.statusCode}. ${response.body}');
    }
  }
  Future<List<Map<String, dynamic>>> getAll(String path) async {
    final response = await http.get(_uri(path));
    _ensureSuccess(response, 'No se pudieron cargar los registros');
    final data = jsonDecode(response.body);
    if (data is! List) throw Exception('La respuesta del backend no es una lista.');
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }
  Future<Map<String, dynamic>> getById(String path, dynamic id) async {
    final response = await http.get(_uri('$path/$id'));
    _ensureSuccess(response, 'No se pudo cargar el registro');
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }
  Future<Map<String, dynamic>> create(String path, Map<String, dynamic> body) async {
    final response = await http.post(_uri(path), headers: _headers, body: jsonEncode(body));
    _ensureSuccess(response, 'No se pudo crear el registro');
    if (response.body.isEmpty) return {};
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }
  Future<Map<String, dynamic>> update(String path, dynamic id, Map<String, dynamic> body) async {
    final response = await http.put(_uri('$path/$id'), headers: _headers, body: jsonEncode(body));
    _ensureSuccess(response, 'No se pudo actualizar el registro');
    if (response.body.isEmpty) return {};
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }
  Future<void> delete(String path, dynamic id) async {
    final response = await http.delete(_uri('$path/$id'), headers: _headers);
    _ensureSuccess(response, 'No se pudo eliminar el registro');
  }
}
