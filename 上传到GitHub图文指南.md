# 把项目上传到 GitHub（不用写代码，全程鼠标点）

目标：让 GitHub 云端自动把"真实换脸 App"编译成安卓安装包（APK）。
你只需要一个**免费的 GitHub 账号**：https://github.com/join

---

## 第 0 步：让 Windows 显示隐藏文件夹（必须做！）

GitHub Actions 自动编译脚本放在 `.github` 文件夹里，它是隐藏的，不显示出来就传不上去。

1. 打开任意一个**文件夹窗口**（此电脑 / 文档都行）。
2. 顶部菜单点 **"查看"(View)**。
3. 在右侧找到 **"隐藏的项目"**（有的系统叫"隐藏的项目"复选框），**打勾 ✅**。

> 做完这一步，你就能在 `face_swap_app` 里看到灰色的 `.github` 文件夹了。

---

## 第 1 步：新建一个仓库

1. 打开 https://github.com 并登录。
2. 右上角点 **"+"** → 选 **"New repository"**（新建仓库）。
3. Repository name（仓库名）：随便填，比如 `faceswap`（只能英文/数字/横线）。
4. 下面选 **Public**（公开，免费；选 Private 也行但 Actions 免费额度少）。
5. **不要**勾任何 "Add a README / .gitignore / license" 的勾选框（保持空的，避免冲突）。
6. 点 **"Create repository"**（创建仓库）。

---

## 第 2 步：把 face_swap_app 里面的内容传上去

创建好后会进入一个空仓库页面，中间有上传区域。

1. 在你电脑上打开 `face_swap_app` 这个文件夹
   （路径大概在：`此电脑 ▸ C盘 ▸ Users ▸ Acer ▸ WorkBuddy ▸ 电脑 ▸ face_swap_app`）。
2. 按 **Ctrl + A** 全选里面的所有东西——你会看到包括：
   - 灰色的 `.github` 文件夹
   - `lib`、`android_overlay`、`docs`、`scripts` 等文件夹
   - `pubspec.yaml`、`README.md`、`build_android.bat` 等文件
3. 把这**一整片选中内容**直接**拖进** GitHub 网页那个虚线框里（"drag files here"）。
   - ⚠️ 是拖"里面的内容"，**不是**拖 `face_swap_app` 这个大文件夹本身。
   - 拖进去后页面会列出一堆文件，确认里面有 `.github/workflows/build_apk.yml` 这一项。
4. 页面最下方填一行说明（随便写，如 `first upload`），点绿色的 **"Commit changes"**（提交）。

> 提交成功 = 你已经把代码"推"到了 main 分支，GitHub 会**立刻自动开始编译**（不用再去找 Actions 按钮）。

---

## 第 3 步：等编译完成，下载安装包

1. 点仓库顶部的 **"Actions"** 标签。
2. 你会看到一条名为 **"Build Real FaceSwap APK"** 的记录正在跑（黄色圆点 = 进行中）。
3. 等 **15~25 分钟**（首次更久）。变成**绿色对勾** = 成功；红色叉 = 失败。
4. 点进那条记录，页面底部 **"Artifacts"** 区域会有 `faceswap-release-apk`。
5. 点它下载，得到一个 **`app-release.apk`**。

---

## 第 4 步：装到手机

1. 把 `app-release.apk` 传到安卓手机（微信发给自己 / 数据线 / 网盘都行）。
2. 手机上点它安装。
   - 可能提示"允许安装未知来源应用"→ 点允许。
3. 打开 App → 传 **20 张正脸照** → 建模型 → 选图片 → 一键换脸。

---

## 如果出错了怎么办

- **Actions 里根本没有 "Build Real FaceSwap APK" 这条记录**：说明 `.github` 没传上去。回到第 0 步确认"隐藏的项目"已打勾，重新上传（或单独把 `.github` 文件夹拖进去一次）。
- **编译红叉**：把红色报错文字截图发我，我帮你改。
- **实在搞不定上传**：告诉我，我可以改用"我帮你生成一个压缩包，你解压后直接拖"的更简单方式，或换别的方案。
