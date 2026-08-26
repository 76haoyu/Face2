@echo off
setlocal
cd /d %~dp0

where flutter >nul 2>nul || (
    echo [错误] 未检测到 flutter，请先安装 Flutter SDK 并加入 PATH。
    echo 参考：https://docs.flutter.dev/get-started/install
    exit /b 1
)

echo [1/4] 生成安卓平台文件（首次会补充 gradle wrapper 与启动图标）...
flutter create --platforms=android .

echo [2/4] 覆盖原生换脸模块与安卓配置...
if exist android\app\src\main\kotlin rmdir /s /q android\app\src\main\kotlin
xcopy /E /I /Y android_overlay\app\src\main\kotlin android\app\src\main\kotlin
copy /Y android_overlay\app\src\main\AndroidManifest.xml android\app\src\main\AndroidManifest.xml
copy /Y android_overlay\app\build.gradle android\app\build.gradle

echo [3/4] 拉取依赖...
flutter pub get

echo [4/4] 构建 release APK...
flutter build apk --release

echo.
echo 完成！APK 位于：build\app\outputs\flutter-apk\app-release.apk
echo 用数据线连接手机，开启"USB 调试"后执行：
echo     flutter install
endlocal
