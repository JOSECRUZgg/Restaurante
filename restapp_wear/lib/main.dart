import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Autenticación anónima para cumplir con las reglas de Firestore
  // sin necesidad de cambiar la base de datos.
  try {
    await FirebaseAuth.instance.signInAnonymously();
  } catch (e) {
    debugPrint('Error en Auth: $e');
  }

  runApp(const RestApp());
}

class RestApp extends StatelessWidget {
  const RestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RestApp',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2ECC71),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0E14),
        fontFamily: 'Roboto',
      ),
      home: const DashboardScreen(),
    );
  }
}
