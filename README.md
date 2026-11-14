# 图片预览 Preview Images

使用 Flutter 开发的多区域图片浏览应用，支持 Windows、macOS、Android 和 iOS 工程。

- 同时浏览 1–36 个图片区域，每个区域独立选择文件夹和翻页。
- 图片按文件名自然升序排列，数字名称按 `1、2、10` 排列，忽略大小写。
- 双击进入大图预览，支持缩放与拖动。
- 可切换显示浏览进度，通过滑块定位图片。
- 自动保存最多 10 条历史记录，恢复区域布局、文件夹和浏览位置。
- 支持删除单条历史记录或清空记录。

## 获取 Windows 版

打开 [Build Windows EXE](https://github.com/601652267/previewimages/actions/workflows/build-windows.yml)，选择最近一次成功的运行，在 **Artifacts** 中下载 **previewimages-windows-x64**。

解压下载文件，再解压其中的运行包 ZIP，在 Windows x64 上双击 `previewimages.exe`。请保留同目录的 DLL 和 `data` 文件夹。

## 代码结构

```text
lib/
  main.dart                       # 启动入口
  app.dart                        # 应用主题与首页配置
  core/
    platform/                     # Android 存储权限、macOS 文件夹授权
    services/                     # 图片文件扫描
    utils/                        # 文件路径处理
  features/
    folder_picker/                # Android 文件夹选择页面
      mixins/                     # 文件夹选择与权限交互
      models/
      widgets/
    history/                      # 历史记录页面
      models/                     # 历史数据与 JSON 格式
      repositories/               # 本地持久化与最多 10 条的规则
      widgets/                    # 历史记录列表项
    image_preview/                # 大图预览页面
      mixins/                     # 缩放、拖动、翻页手势与控制器生命周期
    image_regions/                # 多区域浏览页面
      mixins/                     # 历史记录加载、保存与授权保留
      models/
      widgets/                    # 布局、区域卡片、区域数与进度显示
  shared/widgets/                 # 页面间共用的组件
```

每个页面单独一个文件，页面专用组件放在所属功能的 `widgets/` 中。依赖 `State` 生命周期的页面行为可以放入 `mixins/`，通过抽象 getter 明确所需状态，并在覆盖生命周期方法时调用 `super`。文件扫描、平台通道和持久化各自独立。

测试直接导入被测试的页面、组件或存储类。历史记录的存储 key、JSON 格式和原生通道名保持兼容。

## 构建

项目使用 Flutter **3.29.3**。

```sh
flutter pub get
flutter analyze
flutter test
```

仓库管理员可以在 Actions 中选择 **Build Windows EXE → Run workflow**，使用 Windows 2022 云端环境测试并编译 Release。构建产物保留 14 天。

也可以在安装好 Flutter 与 Visual Studio 2022 C++ 桌面开发工具的 Windows 电脑上运行 `build-windows.cmd`。详细步骤见 [Windows 打包说明](WINDOWS_BUILD.md)。
