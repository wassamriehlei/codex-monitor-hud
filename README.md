# Codex Monitor HUD

<p align="center">
  <img src="assets/codex-monitor-hud-256.png" width="128" alt="Codex Monitor HUD anime mascot icon">
</p>

<p align="center">
  A local, lightweight Windows HUD for Codex Desktop, VS Code, Windows CLI, and WSL.<br>
  <a href="README.zh-CN.md">简体中文</a> · English
</p>

Codex Monitor HUD shows live task state, token usage, context pressure, allowances, and source identity without uploading session data. It supports a compact floating ball, an expandable window, task lists, and detached task bubbles.

![Expanded HUD monitoring Windows and WSL tasks](assets/screenshots/hud-wsl.png)

## Download and run

Download the latest stable assets from [GitHub Releases](https://github.com/wassamriehlei/codex-monitor-hud/releases/latest).

| Package | How to run | Data location |
| --- | --- | --- |
| `CodexMonitorHUD-Setup-3.4.0-windows-x64.exe` | Run the installer; launch from the desktop or Start menu | `%LOCALAPPDATA%\CodexMonitorHUD` |
| `CodexMonitorHUD-Portable-3.4.0-windows-x64.zip` | Extract all files, then double-click `CodexMonitorHUD.exe` | `portable-data\CodexMonitorHUD` beside the EXE |

Open portable Settings with `CodexMonitorHUD-Settings.exe`. Version 3.4 removes the public CMD launchers: both normal startup and Settings are direct EXE entry points. Keep the extracted directory writable and do not run the EXE from inside the ZIP.

Both packages include the private .NET/WPF runtime and the default completion sound. No system-wide .NET SDK is required. Verify downloads with `SHA256SUMS.txt`; the current binaries are not code-signed, so Windows may show an unknown-publisher prompt.

## Highlights

- Monitors Codex Desktop, Codex in VS Code, native Windows Codex CLI, WSL Codex CLI, and an optional isolated DeepSeek CLI profile.
- Shows active, listening, idle, paused, completed, aborted, and read-error states.
- Displays cached and uncached input, output, reasoning, call/task totals, context usage, model, provider badge, weekly allowance, and 5-hour allowance.
- Lets every main-list field be shown or hidden independently.
- Supports summary, list, split-bubble, and floating-ball modes.
- Expands the floating ball on click or after a short hover; dragging does not trigger expansion. It expands toward the available side of the screen.
- Provides state-aware color, pulse, breath, pop, shake, and settle animation cues.
- Supports adjustable HUD width, floating-ball size, whole-bubble scaling, opacity, corners, edge snapping, and any installed Windows font. HarmonyOS Sans SC is preferred by default.
- Plays a built-in completion sound or a user-selected WAV, MP3, WMA, M4A, or AAC file.
- Offers opt-in current-user startup and a local MCP control surface.

## Screenshots

| Floating ball | Appearance and sizing |
| --- | --- |
| ![Floating ball with active task count](assets/screenshots/floating-ball.png) | ![Appearance, font, width and opacity settings](assets/screenshots/settings-overview.png) |

| Monitoring sources | Task-list customization |
| --- | --- |
| ![Independent Codex source switches](assets/screenshots/settings-sources.png) | ![Task-list fields and layout controls](assets/screenshots/settings-list.png) |

| Completion alerts | Expanded multi-task HUD |
| --- | --- |
| ![Completion sound and behavior settings](assets/screenshots/settings-sound.png) | ![Expanded HUD with multiple local tasks](assets/screenshots/hud-wsl.png) |

## WSL Codex CLI

Open **Settings → Sources**, enable WSL, select a distribution, and use automatic home detection. Windows and WSL profiles can run at the same time and be toggled independently. The native Windows HUD reads the selected WSL session directory through `\\wsl.localhost\...`; it does not need a second Linux GUI process.

See [the WSL setup guide](docs/WSL_CODEX_CLI.md) for profile discovery and troubleshooting.

## Install from the repository

Give Codex this repository URL and say **“Install this for me.”** The deterministic flow is documented in [INSTALL_WITH_CODEX.md](INSTALL_WITH_CODEX.md) and [install-manifest.json](install-manifest.json).

Manual developer install:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

Build the Windows AppHost and private runtime:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-dotnet.ps1
```

The build creates `CodexMonitorHUD.exe` and `CodexMonitorHUD-Settings.exe` at the repository root. Release packaging uses separate curated repository and portable stages, smallest-size ZIP compression, no PDB/CMD files, and no development projects or test fixtures in end-user archives. WPF trimming is intentionally avoided because it is not supported by the desktop framework.

## Privacy

All processing stays local. The HUD reads only bounded session metadata and counters needed for the display: usage, model/provider label, client source, lifecycle events, workspace leaf, session ID, and local title. It does not store prompts, replies, tool output, transcripts, credentials, or provider configuration, and it does not modify Codex session files. There is no HUD telemetry.

See [PRIVACY.md](PRIVACY.md), [SECURITY.md](SECURITY.md), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Platform and project status

- Windows 10/11 x64 is packaged and tested.
- The project is independent and unofficial; it is not affiliated with or endorsed by OpenAI, Microsoft, DeepSeek, or Apple.
- The interface is a lightweight WPF interpretation of the iOS 26 visual language. It does not use the retired Windows Blur/Acrylic glass mode.
- The mascot portrait is a modified CC0 asset; full provenance is recorded in the third-party notice.

MIT License.
