import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';

Future<Database> openRuntimeDatabase(String name) =>
    databaseFactoryIo.openDatabase(name);
