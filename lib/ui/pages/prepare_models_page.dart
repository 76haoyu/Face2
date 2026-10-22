import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import 'capture_identity_page.dart';
import 'home_page.dart';

/// 首次使用：从国内镜像下载换脸模型（约 750MB），带进度条；完成后进入主流程。
class PrepareModelsPage extends StatefulWidget {
  const PrepareModelsPage({super.key});
  @override
  State<PrepareModelsPage> createState() => _PrepareModelsPageState();
}

class _PrepareModelsPageState extends State<PrepareModelsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final state = context.read<AppState>();
    await state.prepareModels();
    if (!mounted) return;
    if (state.modelsReady) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              state.identity != null ? const HomePage() : const CaptureIdentityPage(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pct = (state.modelProgress * 100).clamp(0, 100).toInt();
    return Scaffold(
      appBar: AppBar(title: const Text('首次准备')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_download, size: 72, color: Colors.deepPurple),
            const SizedBox(height: 16),
            const Text('首次使用需下载换脸模型',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('约 750MB，建议在 WiFi 下下载，仅需一次，之后完全离线可用。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            if (state.modelError == null) ...[
              LinearProgressIndicator(value: state.modelProgress),
              const SizedBox(height: 12),
              Text(state.modelStage ?? '正在准备…', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('$pct%', style: const TextStyle(color: Colors.grey)),
            ] else ...[
              Text('下载失败：${state.modelError}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
                onPressed: () {
                  state.resetModelError();
                  _start();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
