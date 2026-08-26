#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

command -v flutter >/dev/null 2>&1 || { echo "[错误] 未检测到 flutter，请先安装并加入 PATH。"; exit 1; }

echo "[1/4] 生成安卓平台文件..."
flutter create --platforms=android .

echo "[2/4] 覆盖原生换脸模块与安卓配置..."
rm -rf android/app/src/main/kotlin
cp -r android_overlay/app/src/main/kotlin android/app/src/main/kotlin
cp -f android_overlay/app/src/main/AndroidManifest.xml android/app/src/main/AndroidManifest.xml
cp -f android_overlay/app/build.gradle android/app/build.gradle

echo "[3/4] 拉取依赖..."
flutter pub get

echo "[4/4] 构建 release APK..."
flutter build apk --release

echo "完成！APK 位于 build/app/outputs/flutter-apk/app-release.apk"
echo "安装到手机：flutter install"
