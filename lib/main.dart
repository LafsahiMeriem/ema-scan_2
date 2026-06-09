import 'dart:io'; // Import nécessaire pour HttpOverrides
import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/sap_service.dart'; // Importe ton service pour accéder à MyHttpOverrides

void main() {
  // Cette ligne est CRUCIALE pour autoriser la connexion à ton serveur SAP local
  HttpOverrides.global = MyHttpOverrides();

  runApp(const EmaScanApp());
}

class EmaScanApp extends StatelessWidget {
  const EmaScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0056D2)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}