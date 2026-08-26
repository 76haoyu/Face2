package com.example.faceswap

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 注册真实端侧换脸原生模块（演示模式下 Dart 不会调用，故不影响默认运行）
        MlFaceSwapPlugin.registerWith(flutterEngine)
    }
}
