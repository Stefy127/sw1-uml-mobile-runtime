import 'package:sembast/sembast.dart';
import 'package:sembast_web/sembast_web.dart';

Future<Database> openRuntimeDatabase(String name) =>
    databaseFactoryWeb.openDatabase(name);
