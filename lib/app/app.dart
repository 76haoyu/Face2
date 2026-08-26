import 'package:flutter/material.dart';
import '../ui/pages/splash_page.dart';

class FaceSwapApp extends StatelessWidget {
  const FaceSwapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '换脸助手',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6750A4),
        brightness: Brightness.light,
      ),
      home: const SplashPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
