import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import 'capture_identity_page.dart';
import 'result_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final f = await _picker.pickImage(source: ImageSource.gallery);
    if (f == null) return;
    final state = context.read<AppState>();
    await state.swapImage(File(f.path));
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ResultPage()),
    );
  }

  Future<void> _pickVideo() async {
    final f = await _picker.pickVideo(source: ImageSource.gallery);
    if (f == null) return;
    final state = context.read<AppState>();
    await state.swapVideo(File(f.path));
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ResultPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('换脸助手'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重建人脸模型',
            onPressed: () async {
              await state.clearIdentity();
              if (!mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const CaptureIdentityPage()),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [Tab(text: '图片'), Tab(text: '视频')],
        ),
      ),
      body: Center(
        child: state.swapping
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('正在本地替换人脸…'),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.face, size: 72, color: Colors.deepPurple),
                  const SizedBox(height: 16),
                  const Text('选择要替换人脸的图片或视频',
                      style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    icon: const Icon(Icons.image),
                    label: const Text('选择图片'),
                    onPressed: _pickImage,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.videocam),
                    label: const Text('选择视频'),
                    onPressed: _pickVideo,
                  ),
                  if (state.identity?.isDemo == true)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Text('当前为演示模式：合成效果非真实换脸。',
                          style: TextStyle(color: Colors.grey)),
                    ),
                ],
              ),
      ),
    );
  }
}
