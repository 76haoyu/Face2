# 换脸助手（FaceSwap App）— 真实端侧换脸

上传 **20 张你的人脸照** 在手机本地建立"人脸模型"，再选图片即可一键把其中的脸换成你的脸。
**真实换脸效果**，模型跑在手机本地（ONNX Runtime Mobile，和电脑端 Roop/ReActor 同款），人脸数据不出手机。

- 平台：Flutter 跨平台（本仓库已补齐 Android 工程）
- 执行位置：手机本地（真实换脸，模型随 APK 打包）
- 形态：完整可安装原型

---

## 〇、给不懂代码的你：5 步拿到安装包（不用装任何开发工具）

> 这个对话框没法直接吐出一个 .apk 文件（这里没有安卓编译器）。
> 但可以用**免费的 GitHub 云端编译**自动帮你做出来，你只下载安装即可。

1. **注册 GitHub**（免费）：https://github.com/ 注册一个账号。
2. **新建仓库**：点右上角 `+` → New repository → 名字随便（如 `faceswap`）→ 选 **Public** → 创建。
3. **上传本文件夹**：在仓库页面把 `face_swap_app/` 整个文件夹拖进去（含隐藏的 `.github` 文件夹），提交。
4. **一键编译**：点仓库顶部 `Actions` → 左边 `Build Real FaceSwap APK` → 右边 `Run workflow` → 再次 `Run workflow`。等约 15–25 分钟。
5. **下载安装**：编译完成后，页面下方 `Artifacts` → `faceswap-release-apk` → 下载 `app-release.apk`，传到安卓手机安装（安装时允许"未知来源"）。

装好后：进 App → 传 20 张正脸照 → 建模型 → 选一张图片 → 一键换脸，看前后对比。

> 若编译失败（云端日志里有红字），把日志贴给我，我帮你改。常见原因是某个模型下载地址变动，我会更新工作流。

---

## 一、产品流程

1. 首次进入 → 上传/拍摄 **20 张人脸照**（网格采集，满 20 张才能生成）；
2. 本地"建立人脸模型" → ArcFace 对 20 张照取平均得到 512 维身份向量 + 进度条；
3. 主页选「图片」→ 选目标 → "正在本地替换人脸" → 结果页看前后对比（真实换脸）；
4. 身份模型持久化在手机沙箱，离线可用，并提供"重建模型"入口。

---

## 二、技术架构（真实引擎）

```
Dart (Flutter UI)
   │ MethodChannel(com.example.faceswap/ml)
   ▼
Kotlin (MlFaceSwapPlugin → FaceSwapEngine, ONNX Runtime Mobile)
   ├─ 检测：YuNet            face_detection_yunet_2023mar.onnx
   ├─ 识别：ArcFace          w600k_r50.onnx  (112x112 → 512 维, 20张平均)
   └─ 换脸：inswapper_128    inswapper_128_fp16.onnx (128x128 + embedding → 128x128)
```

模型在构建期由 `.github/workflows/build_apk.yml` 自动下载并打进 APK 的 `assets/models/`。

---

## 三、目录结构

```
face_swap_app/
├─ lib/                        # Flutter(Dart) 源码
│  ├─ state/app_state.dart     # 用 USE_REAL_ENGINE 决定 Demo / 真实引擎
│  ├─ services/                # 身份与换脸服务（Demo + 真实 ML）
│  └─ ui/pages/                # Splash / 采集 / 主页 / 结果
├─ android_overlay/            # 安卓原生增强文件（构建时覆盖进 android/）
│  └─ app/src/main/kotlin/.../
│     ├─ MlFaceSwapPlugin.kt   # MethodChannel 原生桥接
│     ├─ FaceSwapEngine.kt     # 真实换脸推理（ORT，完整实现）
│     └─ MainActivity.kt       # 注册原生模块
├─ .github/workflows/build_apk.yml  # 云端一键构建真实 APK
├─ build_android.bat / .sh     # 本机构建脚本（默认 Demo，可选真实）
├─ docs/ON_DEVICE_ML.md
└─ pubspec.yaml
```

---

## 四、在自己电脑上构建（可选，需装 Flutter + Android SDK）

**默认编译出"演示版"APK（无模型、仅体验流程）：**
```bat
build_android.bat        # Windows
# 或
bash build_android.sh    # macOS/Linux
```

**编译"真实换脸版"APK（本机）：** 在 `build_android.bat/.sh` 的 `flutter build apk` 命令后加
`--dart-define=USE_REAL_ENGINE=true`，并先把三个模型放到
`android/app/src/main/assets/models/`（`yunet.onnx`、`w600k_r50.onnx`、`inswapper_128_fp16.onnx`）。

---

## 五、限制与合规

- 换脸模型（`inswapper_128` 等）仅供**个人非商业 / 研究**用途，请遵守原作者许可证。
- 请仅对自己的肖像或已获授权的素材使用，勿用于欺骗、冒充等违法违规场景。
- 视频逐帧换脸为进阶功能，原生已预留接口（见 `FaceSwapEngine`/工作流注释）。
- 真实引擎为在真机/云端首次编译，个别预处理常数（归一化、landmark 参考点）若与训练不一致可能需微调；如有偏差把现象告诉我即可定位。
