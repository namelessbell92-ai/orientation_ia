import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'navigation/app_navigation.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/diagnostic_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint("Initialisation Firebase…");
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 3));
    debugPrint("Firebase initialisé !");
  } catch (e) {
    debugPrint("Firebase non disponible (mode local/démo activé) : $e");
  }

  runApp(const OrientationIA());
}

class OrientationIA extends StatelessWidget {
  const OrientationIA({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Orientation IA',
      theme: AppTheme.theme,

      // Routes déclarées ici
      routes: {
        "/login": (context) => const LoginScreen(),
        "/register": (context) => const RegisterScreen(),
        "/diagnostic": (context) => const DiagnosticScreen(),
      },

      // Navigation principale avec accès direct
      home: const AppNavigation(),
    );
  }
}
