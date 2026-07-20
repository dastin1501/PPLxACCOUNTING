import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screens/app_shell.dart';
import 'theme/app_theme.dart';

void main() {
  // sqflite's default implementation only works on Android/iOS (via platform
  // channels). On desktop platforms we swap in the FFI-based sqlite3
  // implementation so stock data can still be persisted locally, which is
  // handy for testing on a PC before deploying to the tablet.
  if (!Platform.isAndroid && !Platform.isIOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const PosApp());
}

class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'POS Stock Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AppShell(),
    );
  }
}
