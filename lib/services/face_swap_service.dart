import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../models/identity_model.dart';
import '../models/swap_result.dart';

/// 换脸服务抽象。
abstract class FaceSwapService {
  Future<SwapResult> swapImage({
    required File target,
    required FaceIdentity identity,
  });

  Future<SwapResult> swapVideo({
    required File target,
    required FaceIdentity identity,
  });
}

/// 演示引擎：用 [img] 包做"中心区域羽化贴图"，可在无重模型时跑通交互。
/// 这不是真实换脸，仅用于产品流程演示；真实效果由 [MlFaceSwapService] 提供。
class DemoFaceSwapService extends FaceSwapService {
  @override
  Future<SwapResult> swapImage({
    required File target,
    required FaceIdentity identity,
  }) async {
    await Future.delayed(const Duration(milliseconds: 800));
    final out = await _blend(target, File(identity.representativeFacePath));
    return SwapResult(
      targetPath: target.path,
      outputPath: out?.path,
      type: SwapTargetType.image,
      isDemo: true,
      note: '演示合成：仅做中心区域羽化贴图，非真实换脸。接入原生 ML 引擎后即为真换脸。',
    );
  }

  @override
  Future<SwapResult> swapVideo({
    required File target,
    required FaceIdentity identity,
  }) async {
    // 演示模式只处理首帧缩略图
    return SwapResult(
      targetPath: target.path,
      type: SwapTargetType.video,
      isDemo: true,
      note: '演示模式仅支持图片。视频逐帧换脸需原生引擎（详见 docs/ON_DEVICE_ML.md）。',
    );
  }

  Future<File?> _blend(File target, File source) async {
    try {
      final t = img.decodeImage(await target.readAsBytes());
      final s = img.decodeImage(await source.readAsBytes());
      if (t == null || s == null) return null;

      // 取源图中心脸区域
      final faceSize = (min(s.width, s.height) * 0.6).round();
      final sx = (s.width - faceSize) ~/ 2;
      final sy = (s.height - faceSize) ~/ 2;
      final face = img.copyCrop(s, x: sx, y: sy, width: faceSize, height: faceSize);

      // 目标上的放置框（中心，略小于目标短边）
      final box = (min(t.width, t.height) * 0.45).round();
      final scaled = img.copyResize(face, width: box, height: box);
      final dx = (t.width - box) ~/ 2;
      final dy = (t.height - box) ~/ 2;

      // 羽化贴图：椭圆遮罩 + 边缘 alpha 渐变
      final result = img.copyResize(t, width: t.width, height: t.height);
      const feather = 18;
      final inner = 1.0 - feather / (box / 2);
      for (var y = 0; y < box; y++) {
        for (var x = 0; x < box; x++) {
          final nx = (x - box / 2) / (box / 2);
          final ny = (y - box / 2) / (box / 2);
          final r = sqrt(nx * nx + ny * ny);
          if (r > 1.0) continue;
          final a = smoothstep(inner, 1.0, r).clamp(0.0, 1.0);
          final sp = scaled.getPixel(x, y);
          final tp = t.getPixel(dx + x, dy + y);
          final cr = (sp.r * a + tp.r * (1 - a)).round();
          final cg = (sp.g * a + tp.g * (1 - a)).round();
          final cb = (sp.b * a + tp.b * (1 - a)).round();
          result.setPixel(dx + x, dy + y, img.ColorRgb8(cr, cg, cb));
        }
      }

      final dir = await _outDir;
      await dir.create(recursive: true);
      final outFile = File('${dir.path}/swap_${DateTime.now().millisecondsSinceEpoch}.png');
      await outFile.writeAsBytes(img.encodePng(result));
      return outFile;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> get _outDir async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/swaps');
  }
}

double smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// 生产引擎：通过 MethodChannel 调用 Android(NCNN)/iOS(CoreML) 原生换脸模块。
/// 原生侧实现见 docs/ON_DEVICE_ML.md。未接入模型时回退信息由 [SwapResult.note] 承载。
class MlFaceSwapService extends FaceSwapService {
  static const _channel = MethodChannel('com.example.faceswap/ml');

  @override
  Future<SwapResult> swapImage({
    required File target,
    required FaceIdentity identity,
  }) async {
    try {
      final path = await _channel.invokeMethod<String>('swapImage', {
        'target': target.path,
        'identity': identity.toJson(),
      });
      return SwapResult(
        targetPath: target.path,
        outputPath: path,
        type: SwapTargetType.image,
        isDemo: false,
      );
    } on PlatformException catch (e) {
      return SwapResult(
        targetPath: target.path,
        type: SwapTargetType.image,
        isDemo: false,
        note: '原生引擎未就绪：${e.message}',
      );
    }
  }

  @override
  Future<SwapResult> swapVideo({
    required File target,
    required FaceIdentity identity,
  }) async {
    try {
      final path = await _channel.invokeMethod<String>('swapVideo', {
        'target': target.path,
        'identity': identity.toJson(),
      });
      return SwapResult(
        targetPath: target.path,
        outputPath: path,
        type: SwapTargetType.video,
        isDemo: false,
      );
    } on PlatformException catch (e) {
      return SwapResult(
        targetPath: target.path,
        type: SwapTargetType.video,
        isDemo: false,
        note: '原生引擎未就绪：${e.message}',
      );
    }
  }
}
