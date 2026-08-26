import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/identity_model.dart';
import '../models/swap_result.dart';
import '../services/face_identity_service.dart';
import '../services/face_swap_service.dart';
import '../services/local_identity_storage.dart';

/// 是否使用真实端侧 ML 引擎。由构建参数控制：
///   flutter build apk --release --dart-define=USE_REAL_ENGINE=true
/// 不设该参数（本地开发/演示）时默认走 Demo 引擎（无需模型即可跑通交互）。
const bool _useRealEngine = bool.fromEnvironment('USE_REAL_ENGINE', defaultValue: false);

/// 全局状态：串联身份建立、图片/视频换脸与本地存储。
///
/// 默认使用 [DemoFaceIdentityService] / [DemoFaceSwapService]（可运行、无需模型文件）。
/// 构建时传入 USE_REAL_ENGINE=true 则自动切换到 [MlFaceIdentityService] / [MlFaceSwapService]，
/// 前提是已按 .github/workflows/build_apk.yml 把模型打包进 APK。
class AppState extends ChangeNotifier {
  final LocalIdentityStorage _storage = LocalIdentityStorage();
  final FaceIdentityService _identityService =
      _useRealEngine ? MlFaceIdentityService() : DemoFaceIdentityService();
  final FaceSwapService _swapService =
      _useRealEngine ? MlFaceSwapService() : DemoFaceSwapService();

  FaceIdentity? _identity;
  bool _identityLoaded = false;

  List<File> _captured = [];
  bool _building = false;
  double _buildProgress = 0;

  SwapResult? _lastResult;
  bool _swapping = false;

  FaceIdentity? get identity => _identity;
  bool get identityLoaded => _identityLoaded;
  List<File> get captured => _captured;
  bool get building => _building;
  double get buildProgress => _buildProgress;
  SwapResult? get lastResult => _lastResult;
  bool get swapping => _swapping;

  /// 启动时尝试恢复已保存的身份模型。
  Future<void> init() async {
    _identity = await _storage.load();
    _identityLoaded = true;
    notifyListeners();
  }

  void addPhoto(File f) {
    if (_captured.length < 20) {
      _captured.add(f);
      notifyListeners();
    }
  }

  void removePhoto(int i) {
    if (i >= 0 && i < _captured.length) {
      _captured.removeAt(i);
      notifyListeners();
    }
  }

  void resetCaptured() {
    _captured.clear();
    notifyListeners();
  }

  /// 用已采集的 20 张照建立身份模型（含进度模拟）。
  Future<void> buildIdentity() async {
    if (_captured.length < 20) return;
    _building = true;
    _buildProgress = 0;
    notifyListeners();
    for (var i = 1; i <= 10; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      _buildProgress = i / 10;
      notifyListeners();
    }
    final id = await _identityService.buildIdentity(_captured);
    await _storage.save(id);
    _identity = id;
    _building = false;
    _captured.clear();
    notifyListeners();
  }

  Future<void> swapImage(File target) async {
    if (_identity == null) return;
    _swapping = true;
    notifyListeners();
    _lastResult = await _swapService.swapImage(target: target, identity: _identity!);
    _swapping = false;
    notifyListeners();
  }

  Future<void> swapVideo(File target) async {
    if (_identity == null) return;
    _swapping = true;
    notifyListeners();
    _lastResult = await _swapService.swapVideo(target: target, identity: _identity!);
    _swapping = false;
    notifyListeners();
  }

  Future<void> clearIdentity() async {
    await _storage.clear();
    _identity = null;
    notifyListeners();
  }
}
