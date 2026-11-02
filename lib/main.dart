import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/erp_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ErpApi.instance.init();
  final user = await ErpApi.instance.getLoggedUser();
  runApp(SalesVisitApp(loggedIn: user != null));
}

class SalesVisitApp extends StatelessWidget {
  const SalesVisitApp({super.key, required this.loggedIn});

  final bool loggedIn;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily Report Sales',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.green),
      home: loggedIn ? const HomeScreen() : const LoginScreen(),
    );
  }
}