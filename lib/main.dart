import 'package:flutter/material.dart';

import 'services/app_instance_service.dart';

import 'screens/map_screen.dart';
import 'platform/launch_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  appInstance.startTracking();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Maple Crossing',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF82D5B0),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MapScreen(onReady: finishLaunch),
    );
  }
}
