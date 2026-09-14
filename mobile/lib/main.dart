import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/categoria_cupones_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/super_admin_screen.dart';

void main() {
  runApp(const CuponApp());
}

class CuponApp extends StatelessWidget {
  const CuponApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cupón App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/categorias': (context) => const CategoriaCuponesScreen(),
        '/home': (context) => const HomeScreen(),
        '/admin': (context) => const AdminScreen(),
        '/super-admin': (context) => const SuperAdminScreen(),
      },
    );
  }
}
