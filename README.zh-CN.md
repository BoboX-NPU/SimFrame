# SimFrame

[English](README.md) | 简体中文

SimFrame 是一款纯本地 macOS 应用，可以将 iOS 模拟器截图和录屏制作成带设备外框的精美图片或视频。

导入你自己的 Apple 产品外框，拖入截图或录屏，调整设备框和画布，然后导出可直接用于演示或宣传的成品。设备框资源、源媒体、预览和渲染结果都只保存在你的 Mac 上。

## 主要功能

- 所有处理均在本地完成，不会上传媒体或设备框素材。
- 支持 PNG、JPEG、HEIC、MOV 和 MP4 格式的模拟器截图与录屏。
- 根据像素尺寸、宽高比、文件名和上一次选择自动判断设备与方向。
- 可手动选择设备、横屏或竖屏方向以及外框样式。
- 提供 Original、Balanced 和 Spacious 三种画布布局，支持透明背景和自定义纯色背景。
- 静态图片可导出为 PNG，视频可导出为 MOV 或 MP4，并支持显示进度和取消导出。
- 视频导出时会保留可用的音轨。
- 根据设备框 Alpha 通道生成屏幕形状，使圆角保持干净，并确保设备硬件区域显示在内容上方。
- 记录最近打开的媒体，并提供检查工具来修正导入设备框的元数据。

## 系统要求

- macOS 15.0 或更高版本
- 如需从源码构建，需要支持 macOS 15 SDK 和 Swift 6 的 Xcode
- 来自 [Apple Design Resources](https://developer.apple.com/design/resources/) 的透明 PNG 设备外框

SimFrame 不内置 Apple 设备美术资源，本仓库也不会存储这些文件。分发使用 Apple 产品图片制作的内容前，请阅读 [Apple 营销指南](https://developer.apple.com/app-store/marketing/guidelines/)。

## 快速开始

1. 克隆仓库：

   ```bash
   git clone https://github.com/BoboX-NPU/SimFrame.git
   cd SimFrame
   ```

2. 构建并启动应用：

   ```bash
   ./script/build_and_run.sh
   ```

   也可以在 Xcode 中打开 `SimFrame.xcodeproj`，然后运行 `SimFrame` scheme。

3. 从 Apple Design Resources 下载所需的产品外框并解压。首次打开 SimFrame 时，选择包含透明 PNG 文件的目录。

4. 将模拟器截图或录屏拖入窗口，或使用 **Open Capture** 打开文件。

5. 确认自动识别的设备框，选择画布和背景，然后在检查器中导出。

导入后的设备框库会复制到应用的 Application Support 目录。替换设备框库时采用原子安装：取消导入或导入失败都不会破坏原有资源库。

## 媒体与导出格式

| 源媒体 | 支持的输入格式 | 导出格式 | 说明 |
| --- | --- | --- | --- |
| 图片 | PNG、JPEG、HEIC | PNG | 支持透明或纯色背景，也可以复制到剪贴板。 |
| 视频 | MOV、MP4 | MOV、MP4 | MOV 支持透明或纯色背景；MP4 必须使用纯色背景。 |

透明 MOV 使用 HEVC with Alpha，非透明 MOV 使用 HEVC，MP4 使用 H.264。视频导出会重新编码，并根据源视频码率设定目标码率，不是无损封装转换。

如果源媒体与所选设备框的宽高比不同，SimFrame 会居中裁剪内容，并在导出前显示提示。

## 开发

项目使用原生 SwiftUI 构建，不包含第三方运行时依赖。

```text
SimFrame/App             应用入口
SimFrame/Views           主界面、预览、首次启动页和检查器
SimFrame/Stores          应用状态与用户工作流
SimFrame/Services        设备框导入、媒体检查与渲染
SimFrame/Support         合成几何与日志
SimFrame/DeveloperTools  设备框检查工具
SimFrameTests            单元测试与媒体导出测试
SimFrameUITests          首次启动界面测试
script                   构建与验证素材脚本
doc                      当前项目状态与开发历史
```

构建并运行：

```bash
./script/build_and_run.sh
```

运行测试：

```bash
xcodebuild -project SimFrame.xcodeproj -scheme SimFrame -destination 'platform=macOS' test
```

生成可选的本地媒体测试素材（需要安装 `ffmpeg`）：

```bash
./script/generate_validation_fixtures.sh
```

生成的测试素材和导入的 Apple 美术资源都已被 Git 忽略。缺少本地测试素材时，部分媒体测试会自动跳过。

最新实现状态、验证记录和已知限制请参阅 [doc/current.md](doc/current.md)，开发历史记录在 [doc/devlog.md](doc/devlog.md) 中。
