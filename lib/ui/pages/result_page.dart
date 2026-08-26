import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';

class ResultPage extends StatelessWidget {
  const ResultPage({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final r = state.lastResult;
    return Scaffold(
      appBar: AppBar(title: const Text('替换结果')),
      body: r == null
          ? const Center(child: Text('暂无结果'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (r.note != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      color: Colors.amber.shade100,
                      child: Text(r.note!),
                    ),
                  const SizedBox(height: 12),
                  const Text('原图', style: TextStyle(fontWeight: FontWeight.bold)),
                  Image.file(File(r.targetPath)),
                  const SizedBox(height: 12),
                  const Text('结果', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (r.outputPath != null)
                    Image.file(File(r.outputPath!))
                  else
                    const Text('（演示模式暂无输出，或原生引擎未就绪）'),
                ],
              ),
            ),
    );
  }
}
