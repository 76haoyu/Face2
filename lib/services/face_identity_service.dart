import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/identity_model.dart';

/// 身份建立服务抽象。
abstract class FaceIdentityService {
  /// 由多张人脸照建立身份模型。
  Future<FaceIdentity> buildIdentity(List<File> photos);
}

/// 演示引擎：不做真实 ML，仅挑选代表脸并生成占位 embedding，
/// 用于在没有重模型的情况下完整跑通产品流程。生产环境请改用 [MlFaceIdentityService]。
class DemoFaceIdentityService extends FaceIdentityService {
  @override
  Future<FaceIdentity> buildIdentity(List<File> photos) async {
    // 模拟建立过程（真实引擎在此做检测/对齐/ArcFace编码/平均）
    await Future.delayed(const Duration(seconds: 2));
    final best = photos.isNotEmpty ? photos[photos.length ~/ 2].path : '';
    // 占位 512 维向量
    final rng = Random(42);
    final embedding = Float32List.fromList(List.generate(512, (_) => rng.nextDouble()));
    return FaceIdentity(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      sourcePhotoPaths: photos.map((e) => e.path).toList(),
      representativeFacePath: best,
      embedding: embedding,
      isDemo: true,
    );
  }
}

/// 生产引擎：通过 MethodChannel 调用 Android(NCNN)/iOS(CoreML) 原生模块建立身份。
/// 原生侧实现见 docs/ON_DEVICE_ML.md 与 android_overlay 中的 MlFaceSwapPlugin.kt。
class MlFaceIdentityService extends FaceIdentityService {
  static const _channel = MethodChannel('com.example.faceswap/ml');

  @override
  Future<FaceIdentity> buildIdentity(List<File> photos) async {
    try {
      final json = await _channel.invokeMethod<String>('buildIdentity', {
        'photos': photos.map((e) => e.path).toList(),
      });
      if (json == null) throw Exception('empty response');
      return FaceIdentity.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } on PlatformException catch (e) {
      throw Exception('原生引擎未就绪：${e.message}');
    }
  }
}
