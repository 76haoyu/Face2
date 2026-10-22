import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import 'capture_identity_page.dart';
import 'home_page.dart';
import 'prepare_models_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final state = context.read<AppState>();
      await state.init();
      if (!mounted) return;
      // 真实引擎且模型未下载：先进入下载页
      if (state.isRealEngine && !state.modelsReady) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => const PrepareModelsPage(),
        ));
        return;
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) =>
            state.identity != null ? const HomePage() : const CaptureIdentityPage(),
      ));
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}
