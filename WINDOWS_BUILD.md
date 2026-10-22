# Windows 打包

项目使用 Flutter 3.29.3。macOS 无法直接编译 Flutter Windows 应用；必须在 Windows 上完成构建。

## 在 Windows 电脑构建

1. 从 [Flutter 官方版本归档](https://docs.flutter.dev/install/archive) 选择并安装 **Windows x64、3.29.3**，把 `flutter\bin` 加入 PATH。
2. 安装 [Visual Studio 2022](https://visualstudio.microsoft.com/vs/)，选择“使用 C++ 的桌面开发”工作负载，包含 Windows SDK 和 MSVC v143。
3. 解压源码包。若 Flutter 提示需要符号链接权限，在 Windows 设置中开启开发者模式，再重新打包。
4. 双击 `build-windows.cmd`。脚本依次安装项目依赖、静态检查、运行测试、编译 Release，并打包运行所需文件。

成功后生成：

- `dist\previewimages-windows-x64\previewimages.exe`：应用程序。
- `dist\previewimages-windows-x64.zip`：完整的 Windows x64 运行包，包含 exe、Flutter DLL、资源文件和 Visual C++ 运行库。

使用时解压整个运行包，再双击 `previewimages.exe`。分发时请发送完整 ZIP；单独复制 exe 无法运行。

## 使用 GitHub 云端构建

项目包含 `.github/workflows/build-windows.yml`，只有手动触发才会构建。把项目提交到自己的 GitHub 仓库后，在 Actions 中选择 **Build Windows EXE → Run workflow**，完成后下载 **previewimages-windows-x64** artifact。解压 artifact 后，再解压里面的运行包 ZIP 即可使用。

工作流在 Windows 2022 环境构建，产物保留 14 天。构建失败时，可在相应运行的失败步骤中查看日志。

Windows 打包要求与运行包结构参考 [Flutter 官方说明](https://docs.flutter.dev/platform-integration/windows/building)。
