import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'screens/home_screen.dart';
import 'db/database_helper.dart';
import 'screens/splash_screen.dart';

final GoogleSignIn googleSignIn = GoogleSignIn(
  scopes: <String>[
    'https://www.googleapis.com/auth/drive.file',
  ],
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.instance.database; // ensure DB is ready
  runApp(const InventoryApp());
}

class InventoryApp extends StatelessWidget {
  const InventoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Event Collection',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        brightness: Brightness.light,
		useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true),
      ),
	  darkTheme: ThemeData(
		colorSchemeSeed: Colors.teal,
		brightness: Brightness.dark,
		useMaterial3: true,
	  ),
	  themeMode: ThemeMode.system, // follow system dark/light mode
      home: const SplashScreen(),
    );
  }
}