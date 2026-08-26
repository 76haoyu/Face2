# 端侧换脸引擎接入指南（Android / iOS + NCNN）

本文说明如何把"真实换脸"接入 Flutter App。默认 `DemoFaceSwapService` 仅做演示，
切换到 `MlFaceSwapService` 后，所有重计算都发生在**手机本地**，人脸数据不出端。

---

## 一、MethodChannel 契约

Dart 侧已定义通道 `com.example.faceswap/ml`，原生侧需实现以下方法：

| 方法 | 入参 | 回参 | 说明 |
| --- | --- | --- | --- |
| `buildIdentity` | `{photos: List<String>}` | `{id, createdAt, sourcePhotoPaths, representativeFacePath, embedding: List<double>}` | 用 20 张照检测/对齐/ArcFace 编码并平均，得到身份向量 |
| `swapImage` | `{target: String, identity: Map}` | `String?`（输出图路径） | 把目标图人脸替换为该身份 |
| `swapVideo` | `{target: String, identity: Map}` | `String?`（输出视频路径） | 逐帧替换后重新封装 |

> `identity` 是 `FaceIdentity.toJson()` 的 Map，原生侧直接读 `embedding` 字段。

切换方式（`lib/state/app_state.dart`）：

```dart
final FaceIdentityService _identityService = MlFaceIdentityService();
final FaceSwapService _swapService = MlFaceSwapService();
```

---

## 二、模型清单（均需自行获取，注意许可证）

| 用途 | 模型 | 常见来源 | 格式 |
| --- | --- | --- | --- |
| 人脸检测 | SCRFD（如 `scrfd_10g`） | InsightFace / 官方 repo | ONNX → NCNN |
| 人脸识别 | ArcFace（`w600k_r50` / `buffalo_l`） | InsightFace | ONNX → NCNN |
| 换脸生成 | `inswapper_128.onnx` | 社区（如 deepinsight/inswapper） | ONNX → NCNN |
| 备选换脸 | MobileFaceSwap | 论文官方实现 | ONNX → NCNN |
| 视频处理 | ffmpeg | 各平台 | 二进制 |

> ⚠️ `inswapper_128` 等权重有使用限制，仅供个人非商业/研究用途，请遵守原作者许可证。

---

## 三、ONNX → NCNN 转换

依赖：`onnxsim`、`ncnn` 工具链（`onnx2ncnn`）。可用 `scripts/prepare_models.py` 自动跑：

```bash
pip install onnxsim
# 把 onnx2ncnn 加到 PATH（来自 ncnn 构建产物）
python scripts/prepare_models.py --input inswapper_128.onnx --out ./models
```

生成 `inswapper_128.param` + `inswapper_128.bin`，放入 `android/app/src/main/assets/` 与 iOS 的 `Runner` 资源中。

---

## 四、Android（Kotlin + NCNN）

1. 在 `android/app/build.gradle` 引入 NCNN AAR：
   ```gradle
   implementation 'com.tencent:ncnn:20240820'
   ```
2. 把 `.param/.bin` 放进 `android/app/src/main/assets/`。
3. 新建 `MlFaceSwapPlugin.kt` 实现 `MethodCallHandler`：

```kotlin
class MlFaceSwapPlugin : MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "buildIdentity" -> {
                val photos = call.argument<List<String>>("photos")!!
                // 1) SCRFD 检测 + 对齐；2) ArcFace 提取 512 维；3) 平均
                val embedding = buildEmbedding(photos)
                result.success(mapOf(
                    "id" to System.currentTimeMillis().toString(),
                    "createdAt" to Instant.now().toString(),
                    "sourcePhotoPaths" to photos,
                    "representativeFacePath" to photos[photos.size / 2],
                    "embedding" to embedding  // List<Double>
                ))
            }
            "swapImage" -> {
                val target = call.argument<String>("target")!!
                val identity = call.argument<Map<String, Any>>("identity")!!
                val emb = (identity["embedding"] as List<Double>).map { it.toFloat() }.toFloatArray()
                val out = swapOneImage(target, emb) // SCRFD + inswapper_128
                result.success(out)
            }
            "swapVideo" -> {
                val target = call.argument<String>("target")!!
                val identity = call.argument<Map<String, Any>>("identity")!!
                val out = swapVideoFrames(target, identity) // ffmpeg 抽帧→换脸→封装
                result.success(out)
            }
            else -> result.notImplemented()
        }
    }
}
```

4. 在 `MainActivity.configureFlutterEngine` 中注册：
   ```kotlin
   MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.faceswap/ml")
       .setMethodCallHandler(MlFaceSwapPlugin())
   ```

关键推理片段（伪代码）：

```kotlin
// 检测 + 对齐
val faces = ScrfdDetector.detect(bitmap)          // 返回 bbox + 5 点 landmark
val aligned = FaceAlign.align(bitmap, faces[0])    // 112x112
// 识别 → 512 维
val emb = ArcFace(aligned).normalize()            // L2 归一化
// 换脸：把 emb 作为源条件送入 inswapper_128，对目标对齐后人脸做生成
val swapped = Inswapper(targetAligned, sourceEmb = emb).forward()
```

---

## 五、iOS（Swift + NCNN / ONNX Runtime）

思路一致，用 Swift 封装 NCNN（或 ONNX Runtime for iOS）：

- 把 `.param/.bin` 加入 `Runner` 的 Copy Bundle Resources；
- 在 `AppDelegate` / `FLTObjc` 插件中注册 `FlutterMethodChannel(name: "com.example.faceswap/ml")`；
- 实现 `handle(_ call: FlutterMethodCall, result:)` 处理三个方法；
- 视频用 `ffmpeg-kit` 抽帧/封装。

如追求更高画质且机型较新，也可用 CoreML 版的 ArcFace/inswapper（需 `coremltools` 转换 `.mlmodel`）。

---

## 六、视频逐帧流程（ffmpeg）

```
ffmpeg -i input.mp4 -vf fps=30 frame_%05d.png   # 抽帧
# 对每帧调用 swapImage 同款推理
ffmpeg -framerate 30 -i swapped_%05d.png -i input.mp4 -map 0:v -map 1:a -c:a copy out.mp4
```

移动端建议降分辨率（如最长边 720p）以控制耗时与发热；长视频提示用户分段。

---

## 七、性能与隐私建议

- 模型量化到 NCNN int8，推理速度可提升 2~4 倍；
- 识别在端侧完成，embedding 仅存于应用沙箱，不上传；
- 提供"清除人脸模型"按钮（已接 `AppState.clearIdentity`），尊重用户删除权；
- 低端机可对视频做关键帧间隔抽帧，平衡速度与连贯性。
