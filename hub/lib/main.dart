import 'package:flutter/material.dart';

import 'screens/boot_screen.dart';
import 'theme/tokens.dart';

void main() => runApp(const DartOsApp());

class DartOsApp extends StatelessWidget {
  const DartOsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dart OS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Td.beton,
        fontFamily: 'Inter',
        colorScheme: const ColorScheme.dark(primary: Td.sunset, secondary: Td.crepuscule, surface: Td.asphalte),
      ),
      home: const Scaffold(body: BootScreen()),
    );
  }
}
