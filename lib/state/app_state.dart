import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/identity_model.dart';
import '../models/swap_result.dart';
import '../services/face_identity_service.dart';
import '../services/face_swap_service.dart';
import '../services/local_identity_storage.dart';

/// 是否使用真实端侧 ML 引擎。由构建参数控制：
///   flutter build apk --release --dart-define=USE_REAL_ENGINE=true
/// 不设该参数（本地开发/演示）时默认走 Demo 引擎（无需模型即可跑通交互）。
const bool _useRealEngine = bool.fromEnvironment('USE_REAL_ENGINE', defaultValue: false);

/// 与原生换脸模块通信的通道。
const MethodChannel _ml = MethodChannel('com.example.faceswap/ml');

/// 模型下载进度事件通道（原生推送 percent / stage）。
const EventChannel _modelProgressChannel =
    EventChannel('com.example.faceswap/model_progress');

/// 全局状态：串联身份建立、图片/视频换脸与本地存储。
///
/// 真实引擎模式下，模型不再打包进 APK，改为首次使用时从国内镜像下载。
/// 本类负责：检查模型是否就绪、触发下载、并把下载进度透传给 UI。
class AppState extends ChangeNotifier {
  final LocalIdentityStorage _storage = LocalIdentityStorage();
  final FaceIdentityService _identityService =
      _useRealEngine ? MlFaceIdentityService() : DemoFaceIdentityService();
  final FaceSwapService _swapService =
      _useRealEngine ? MlFaceSwapService() : DemoFaceSwapService();

  StreamSubscription<dynamic>? _modelSub;

  FaceIdentity? _identity;
  bool _identityLoaded = false;

  bool _modelsReady = false;
  bool _preparingModels = false;
  double _modelProgress = 0;
  String? _modelStage;
  String? _modelError;

  List<File> _captured = [];
  bool _building = false;
  double _buildProgress = 0;
  String? _buildMessage;
  String? _buildError;

  SwapResult? _lastResult;
  bool _swapping = false;

  FaceIdentity? get identity => _identity;
  bool get identityLoaded => _identityLoaded;
  List<File> get captured => _captured;
  bool get building => _building;
  double get buildProgress => _buildProgress;
  String? get buildMessage => _buildMessage;
  String? get buildError => _buildError;
  bool get isRealEngine => _useRealEngine;
  SwapResult? get lastResult => _lastResult;
  bool get swapping => _swapping;

  bool get modelsReady => _modelsReady;
  bool get preparingModels => _preparingModels;
  double get modelProgress => _modelProgress;
  String? get modelStage => _modelStage;
  String? get modelError => _modelError;

  /// 启动时尝试恢复已保存的身份模型，并确认模型是否已下载。
  Future<void> init() async {
    _identity = await _storage.load();
    _identityLoaded = true;
    if (_useRealEngine) {
      _modelsReady = await _checkModelsReady();
    } else {
      _modelsReady = true;
    }
    notifyListeners();
  }

  Future<bool> _checkModelsReady() async {
    try {
      return await _ml.invokeMethod<bool>('areModelsReady') ?? false;
    } catch (_) {
      return false;
    }
  }

  void _listenModelProgress() {
    _modelSub?.cancel();
    _modelSub = _modelProgressChannel.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        final type = event['type'];
        if (type == 'progress') {
          _modelProgress = (event['percent'] as num?)?.toDouble() ?? 0;
          _modelStage = event['stage'] as String?;
        } else if (type == 'done') {
          _modelsReady = true;
        } else if (type == 'error') {
          _modelError = event['message'] as String?;
        }
        notifyListeners();
      }
    });
  }

  /// 触发首次模型下载（仅真实引擎需要）。进度通过事件通道推送给 UI。
  Future<void> prepareModels() async {
    if (!_useRealEngine) {
      _modelsReady = true;
      notifyListeners();
      return;
    }
    if (_modelsReady) return;
    _preparingModels = true;
    _modelError = null;
    notifyListeners();
    _listenModelProgress();
    try {
      await _ml.invokeMethod<bool>('prepareModels');
      _modelsReady = await _checkModelsReady();
    } catch (e) {
      _modelError = e
          .toString()
          .replaceFirst('PlatformException: ', '')
          .split(',')[0];
    } finally {
      _preparingModels = false;
      notifyListeners();
    }
  }

  void resetModelError() {
    _modelError = null;
    _modelProgress = 0;
    _modelStage = null;
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

  /// 用已采集的 20 张照建立身份模型。
  Future<void> buildIdentity() async {
    if (_captured.length < 20) return;
    _building = true;
    _buildProgress = 0;
    _buildError = null;
    _buildMessage = _useRealEngine
        ? '正在准备模型并提取人脸特征，首次较慢，请耐心等待…'
        : '正在建立演示模型…';
    notifyListeners();

    try {
      if (!_useRealEngine) {
        // 演示引擎：保留一段 fake 进度，让 UI 有反馈
        for (var i = 1; i <= 10; i++) {
          await Future.delayed(const Duration(milliseconds: 200));
          _buildProgress = i / 10;
          notifyListeners();
        }
      }
      final id = await _identityService.buildIdentity(_captured);
      await _storage.save(id);
      _identity = id;
      _captured.clear();
      _buildMessage = null;
    } catch (e) {
      _buildError = e.toString().replaceFirst('Exception: ', '');
      _buildMessage = '建立失败：$_buildError';
    } finally {
      _building = false;
      notifyListeners();
    }
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

  @override
  void dispose() {
    _modelSub?.cancel();
    super.dispose();
  }
}
