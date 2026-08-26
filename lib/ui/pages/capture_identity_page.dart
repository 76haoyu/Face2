import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import 'home_page.dart';

class CaptureIdentityPage extends StatefulWidget {
  const CaptureIdentityPage({super.key});
  @override
  State<CaptureIdentityPage> createState() => _CaptureIdentityPageState();
}

class _CaptureIdentityPageState extends State<CaptureIdentityPage> {
  final _picker = ImagePicker();

  Future<void> _pick(ImageSource src) async {
    final state = context.read<AppState>();
    if (state.captured.length >= 20) return;
    if (src == ImageSource.camera) {
      final f = await _picker.pickImage(source: ImageSource.camera);
      if (f != null) state.addPhoto(File(f.path));
    } else {
      final files = await _picker.pickMultiImage();
      for (final f in files) {
        if (state.captured.length >= 20) break;
        state.addPhoto(File(f.path));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final n = state.captured.length;
    return Scaffold(
      appBar: AppBar(title: const Text('建立人脸模型')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('请上传 20 张清晰、正脸、不同光照的人脸照（$n / 20）',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: 20,
                itemBuilder: (_, i) {
                  if (i < n) {
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Image.file(File(state.captured[i].path),
                              fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => state.removePhoto(i),
                          ),
                        ),
                      ],
                    );
                  }
                  return DashedTile(onTap: () => _pick(ImageSource.gallery));
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('拍照'),
                    onPressed: () => _pick(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('生成模型'),
                    onPressed: n == 20 && !state.building
                        ? () async {
                            await state.buildIdentity();
                            if (!mounted) return;
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (_) => const HomePage()),
                            );
                          }
                        : null,
                  ),
                ),
              ],
            ),
            if (state.building)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  children: [
                    const Text('正在本地建立人脸模型…'),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: state.buildProgress),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class DashedTile extends StatelessWidget {
  final VoidCallback onTap;
  const DashedTile({super.key, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.add, color: Colors.grey),
        ),
      );
}
