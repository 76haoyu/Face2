enum SwapTargetType { image, video }

/// 一次换脸的结果。
class SwapResult {
  final String targetPath; // 原图/原视频路径
  final String? outputPath; // 合成结果路径（演示或原生引擎产出）
  final SwapTargetType type;
  final bool isDemo; // 是否为演示合成（非真实换脸）
  final String? note; // 提示信息（如引擎未就绪、演示说明）

  const SwapResult({
    required this.targetPath,
    this.outputPath,
    required this.type,
    this.isDemo = false,
    this.note,
  });
}
