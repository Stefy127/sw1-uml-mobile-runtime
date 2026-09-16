import 'package:sembast/sembast.dart';
import 'database_factory.dart';

class LocalDatabase {
  static const databaseName = 'sw1_uml_mobile_runtime.db';
  static final _store = StoreRef<String, dynamic>.main();
  static Database? _database;
  static Future<Database> Function(String name)? _databaseOpener;

  static Future<Database> get instance async =>
      _database ??= await (_databaseOpener ?? openRuntimeDatabase)(databaseName);

  static void configure({
    Database? database,
    Future<Database> Function(String name)? databaseOpener,
  }) {
    if (_database != null) {
      throw StateError('LocalDatabase debe reiniciarse antes de configurarse.');
    }
    _database = database;
    _databaseOpener = databaseOpener;
  }

  static Future<void> reset({bool close = true}) async {
    final database = _database;
    _database = null;
    _databaseOpener = null;
    if (close && database != null) await database.close();
  }

  static Future<void> put(String key, dynamic value) async {
    final database = await instance;
    await _store.record(key).put(database, value);
  }

  static Future<dynamic> get(String key) async {
    final database = await instance;
    return _store.record(key).get(database);
  }

  static Future<void> delete(String key) async {
    final database = await instance;
    await _store.record(key).delete(database);
  }

  static Future<Map<String, dynamic>> entries() async {
    final database = await instance;
    final records = await _store.find(database);
    return {
      for (final record in records) record.key: record.value,
    };
  }
}
