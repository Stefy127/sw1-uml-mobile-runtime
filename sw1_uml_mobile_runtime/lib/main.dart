import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/entities/entities_page.dart';

void main() {
  runApp(const Sw1MobileRuntimeApp());
}

class Sw1MobileRuntimeApp extends StatelessWidget {
  const Sw1MobileRuntimeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SW1 Mobile Runtime',
      theme: AppTheme.light,
      home: const EntitiesPage(),
    );
  }
}
