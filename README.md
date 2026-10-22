# 图片预览 Preview Images

使用 Flutter 开发的多区域图片浏览应用，支持 Windows、macOS、Android 和 iOS 工程。

- 同时浏览 1–36 个图片区域，每个区域独立选择文件夹和翻页。
- 双击进入大图预览，支持缩放与拖动。
- 可切换显示浏览进度，通过滑块定位图片。
- 自动保存最多 10 条历史记录，恢复区域布局、文件夹和浏览位置。
- 支持删除单条历史记录或清空记录。

## 获取 Windows 版

打开 [Build Windows EXE](https://github.com/601652267/previewimages/actions/workflows/build-windows.yml)，选择最近一次成功的运行，在 **Artifacts** 中下载 **previewimages-windows-x64**。

解压下载文件，再解压其中的运行包 ZIP，在 Windows x64 上双击 `previewimages.exe`。请保留同目录的 DLL 和 `data` 文件夹。

## 构建

项目使用 Flutter **3.29.3**。

```sh
flutter pub get
flutter analyze
flutter test
```

仓库管理员可以在 Actions 中选择 **Build Windows EXE → Run workflow**，使用 Windows 2022 云端环境测试并编译 Release。构建产物保留 14 天。

也可以在安装好 Flutter 与 Visual Studio 2022 C++ 桌面开发工具的 Windows 电脑上运行 `build-windows.cmd`。详细步骤见 [Windows 打包说明](WINDOWS_BUILD.md)。
