import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:bai3/firebase_options.dart';
import 'pages/onboard.dart';
import 'pages/login_page.dart';
import 'pages/register_page.dart';
import 'pages/pets_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/onboard',
      routes: {
        '/onboard': (context) => const PetsOnBoardingScreen(),
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/home': (context) => const PetsHomeScreen(),
      },
    );
  }
}
