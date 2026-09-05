# Codex Monitor HUD

<p align="center">
  <img src="assets/codex-monitor-hud-256.png" width="128" alt="Codex Monitor HUD 日系动漫少女图标">
</p>

<p align="center">
  面向 Codex Desktop、VS Code、Windows CLI 与 WSL 的本地轻量悬浮监控器。<br>
  简体中文 · <a href="README.md">English</a>
</p>

Codex Monitor HUD 实时展示任务状态、Token 用量、上下文压力、额度窗口和任务来源，不上传会话数据。界面支持悬浮球、展开悬浮窗、任务列表和独立任务气泡。

## 下载与运行

从 [GitHub Releases](https://github.com/wassamriehlei/codex-monitor-hud/releases/latest) 下载最新正式版。

| 发布包 | 运行方法 | 数据位置 |
| --- | --- | --- |
| `CodexMonitorHUD-Portable-3.4.3-windows-x64.zip` | 完整解压后双击 `CodexMonitorHUD.exe` | EXE 同目录下的 `portable-data\CodexMonitorHUD` |

首次运行前，请安装微软官方 [.NET 10 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/10.0) 的 **Windows x64** 版本。请选择 **Desktop Runtime（桌面运行时）**，不需要 SDK，也不要选成 ASP.NET Core Runtime。

设置从 HUD 或系统托盘菜单进入。Portable 发布包只保留 `CodexMonitorHUD.exe`，不再提供独立 Settings EXE、安装器、公开 CMD 启动器或私有 runtime 文件夹。请把 ZIP 完整解压到可写目录，不要直接在压缩包预览窗口中运行 EXE。

发布包内置默认完成提示音。安装 Desktop Runtime 前置依赖后不需要 .NET SDK。可使用 `SHA256SUMS.txt` 校验下载；当前 EXE 尚未代码签名，因此 Windows 可能显示“未知发布者”。

升级时先退出 HUD，保留原有 `portable-data` 目录，用新版本完整解压后的文件替换其余内容，再把 `portable-data` 放回两个 EXE 旁边即可。

## 主要功能

- 同时监控 Codex Desktop、VS Code 中的 Codex、Windows 原生 Codex CLI、WSL Codex CLI，以及可选的独立 DeepSeek CLI Profile。
- 展示活跃、监听、空闲、暂停、完成、中止和读取错误状态。
- 显示缓存/未缓存输入、输出、推理、本次合计、任务累计、上下文占用、模型、服务提供方标识、周额度和 5 小时额度。
- 主列表中的目录、时间、上下文、状态、模型、缓存命中率和合计等字段均可单独开关。
- 支持汇总、列表、分裂气泡和悬浮球模式。
- 悬浮球可单击立即展开或短暂悬停后展开；拖动时不会误展开，并会根据屏幕空间向左或向右展开。
- 不同任务状态使用跟随状态色的脉冲、呼吸、弹出、轻晃和收束动画。
- 可调整 HUD 宽度、悬浮球大小、独立气泡整体缩放、透明度、圆角、自动贴边及字体；默认优先鸿蒙字体 HarmonyOS Sans SC。
- 完成后可播放内置提示音，也可手动选择 WAV、MP3、WMA、M4A 或 AAC 文件并试听。
- 支持当前用户开机启动，以及完全本地的 MCP 控制接口。

## 软件截图

| 悬浮球 | 展开任务列表 |
| --- | --- |
| ![当前悬浮球模式，显示三个活跃 Codex 任务](assets/screenshots/floating-ball.png) | ![当前展开 HUD，显示四个模拟 Codex 任务](assets/screenshots/hud-expanded.png) |

| Windows、CLI 与 WSL 来源 | 多任务字段与布局 |
| --- | --- |
| ![当前监控来源页面，包含 WSL 支持](assets/screenshots/settings-sources.png) | ![当前多任务布局和字段开关](assets/screenshots/settings-multitask.png) |

| 外观、字体与宽度 | 完成提示音与提醒 |
| --- | --- |
| ![当前外观页面，包含鸿蒙字体与宽度调节](assets/screenshots/settings-appearance.png) | ![当前完成提示音文件和提醒设置](assets/screenshots/settings-sound.png) |

悬浮球只显示当前活跃任务数量，文字颜色与低开销背景动效会跟随任务状态变化；单击或短暂悬停即可展开完整 HUD。

## 配置 WSL Codex CLI

打开 **设置 → 监控来源**，启用 WSL，选择发行版并点击自动检测主目录。Windows 与 WSL Profile 可以同时监控，也可以分别关闭。原生 Windows HUD 通过 `\\wsl.localhost\...` 读取所选 WSL 会话目录，不需要在 Linux 中再启动一套图形程序。

详细步骤和故障排查见 [WSL Codex CLI 配置指南](docs/WSL_CODEX_CLI.zh-CN.md)。

## 从仓库安装与构建

把本仓库链接交给 Codex，然后说一句 **“帮我安装。”** 确定性安装流程见 [INSTALL_WITH_CODEX.md](INSTALL_WITH_CODEX.md) 与 [install-manifest.json](install-manifest.json)。

开发者手动安装：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -DefaultLanguage zh-CN
```

构建 Windows AppHost 与私有运行时：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-dotnet.ps1
```

构建后，仓库根目录只生成依赖系统桌面运行时的 `CodexMonitorHUD.exe`。`scripts/prepare-release.ps1` 只生成带版本号的 Portable ZIP，采用最小体积压缩，并在结束时自动删除临时暂存目录。PDB、CMD、私有 runtime 副本、源码工程、测试夹具、工具链和用户数据均不会进入发布包。

## 隐私说明

所有处理都留在本机。HUD 只读取显示所需的有限会话元数据与计数：用量、模型/Provider 标签、客户端来源、生命周期事件、工作区末级名、会话 ID 和本地标题。它不保存提示词、回复、工具输出、原始转录、凭据或 Provider 配置，也不会修改 Codex 会话文件；HUD 本身没有遥测。

详见 [PRIVACY.md](PRIVACY.md)、[SECURITY.md](SECURITY.md) 与 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 平台与项目说明

- 正式支持并验证 Windows 10/11 x64。
- 本项目为独立、非官方项目，与 OpenAI、Microsoft、DeepSeek 或 Apple 均无隶属或背书关系。
- 当前界面是使用 WPF 实现的轻量 iOS 26 风格，不再使用已移除的 Windows Blur/Acrylic 玻璃模式。
- 日系动漫少女图标为本项目生成，提示词与处理方式已记录在第三方声明中。

MIT License.
