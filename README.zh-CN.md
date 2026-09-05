# Codex Monitor HUD

<p align="center">
  <img src="assets/codex-monitor-hud-256.png" width="128" alt="Codex Monitor HUD 日系动漫少女图标">
</p>

<p align="center">
  面向 Codex Desktop、VS Code、Windows CLI 与 WSL 的本地轻量悬浮监控器。<br>
  简体中文 · <a href="README.md">English</a>
</p>

Codex Monitor HUD 实时展示任务状态、Token 用量、上下文压力、额度窗口和任务来源，不上传会话数据。界面支持悬浮球、展开悬浮窗、任务列表和独立任务气泡。

![同时监控 Windows 与 WSL 任务的展开悬浮窗](assets/screenshots/hud-wsl.png)

## 下载与运行

从 [GitHub Releases](https://github.com/wassamriehlei/codex-monitor-hud/releases/latest) 下载最新正式版。

| 安装包 | 运行方法 | 数据位置 |
| --- | --- | --- |
| `CodexMonitorHUD-Setup-3.4.0-windows-x64.exe` | 运行安装器，然后从桌面或开始菜单启动 | `%LOCALAPPDATA%\CodexMonitorHUD` |
| `CodexMonitorHUD-Portable-3.4.0-windows-x64.zip` | 完整解压后双击 `CodexMonitorHUD.exe` | EXE 同目录下的 `portable-data\CodexMonitorHUD` |

便携版设置入口是 `CodexMonitorHUD-Settings.exe`。3.4 版已删除公开的 CMD 启动器，主程序和设置均由 EXE 直接启动。请把 ZIP 完整解压到可写目录，不要直接在压缩包预览窗口中运行。

两种发布包都内置私有 .NET/WPF 运行时和默认完成提示音，不要求系统另装 .NET SDK。可使用 `SHA256SUMS.txt` 校验下载；当前 EXE 尚未代码签名，因此 Windows 可能显示“未知发布者”。

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

| 悬浮球 | 外观、字体与宽度 |
| --- | --- |
| ![只显示活跃任务数量的悬浮球](assets/screenshots/floating-ball.png) | ![字体、HUD 宽度、圆角和透明度设置](assets/screenshots/settings-overview.png) |

| 监控来源 | 任务列表自定义 |
| --- | --- |
| ![可以独立开关的 Codex 监控来源](assets/screenshots/settings-sources.png) | ![任务列表字段与布局设置](assets/screenshots/settings-list.png) |

| 完成提醒 | 多任务悬浮窗 |
| --- | --- |
| ![完成提示音与行为设置](assets/screenshots/settings-sound.png) | ![展开后的多任务监控悬浮窗](assets/screenshots/hud-wsl.png) |

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

构建后，仓库根目录会生成 `CodexMonitorHUD.exe` 与 `CodexMonitorHUD-Settings.exe`。发布脚本分别建立安装版和便携版最小暂存目录，采用最小体积 ZIP 压缩，并排除 PDB、CMD、源码工程、测试夹具与开发工具。WPF 官方不支持的 IL 裁剪没有启用，从而保持运行稳定性。

## 隐私说明

所有处理都留在本机。HUD 只读取显示所需的有限会话元数据与计数：用量、模型/Provider 标签、客户端来源、生命周期事件、工作区末级名、会话 ID 和本地标题。它不保存提示词、回复、工具输出、原始转录、凭据或 Provider 配置，也不会修改 Codex 会话文件；HUD 本身没有遥测。

详见 [PRIVACY.md](PRIVACY.md)、[SECURITY.md](SECURITY.md) 与 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 平台与项目说明

- 正式支持并验证 Windows 10/11 x64。
- 本项目为独立、非官方项目，与 OpenAI、Microsoft、DeepSeek 或 Apple 均无隶属或背书关系。
- 当前界面是使用 WPF 实现的轻量 iOS 26 风格，不再使用已移除的 Windows Blur/Acrylic 玻璃模式。
- 日系动漫少女图标基于 CC0 素材修改，完整出处已记录在第三方声明中。

MIT License.
