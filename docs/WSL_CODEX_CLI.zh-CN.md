# 用 Windows HUD 监控 WSL 中的 Codex CLI

HUD 仍是原生 Windows 应用。可选 Codex 插件可把 WSL 中运行的 Codex CLI 桥接到 Windows 进程，会话记录依然保留在 Linux 发行版内。

## WSL 侧插件配置

先安装 Windows HUD。在 WSL Codex CLI 使用的插件源中，把 `.mcp.json` 设为以下结构，并替换 `WINDOWS_USER`、`DISTRO` 和 `WSL_USER`：

```json
{
  "mcpServers": {
    "codex-monitor-hud": {
      "command": "node.exe",
      "args": [
        "C:\\Users\\WINDOWS_USER\\plugins\\codex-monitor-hud\\src\\mcp-server.mjs"
      ],
      "env": {
        "CODEX_MONITOR_HUD_STATE_ROOT": "C:\\Users\\WINDOWS_USER\\AppData\\Local\\CodexMonitorHUD",
        "CODEX_MONITOR_HUD_HOME": "\\\\wsl.localhost\\DISTRO\\home\\WSL_USER",
        "WSLENV": "CODEX_MONITOR_HUD_STATE_ROOT/w:CODEX_MONITOR_HUD_HOME/w"
      }
    }
  }
}
```

`WSLENV` 是必需项。WSL 不会把任意 Linux 环境变量自动传给启动的 Windows 程序；两个 `/w` 条目会把对应值依次传入 `node.exe`、PowerShell 和编译版 HUD。

配置的主目录下应存在 `.codex/sessions`。可选的同级 `.codex-deepseek` Profile 也会从该目录推导；HUD 不会修改任何 Profile。

更新或重新安装插件后，需要新建一个 Codex 任务以加载新 MCP 配置。首次使用桥接前，请先退出已运行的 HUD；应用只保留一个桌面实例，较早启动、监听 Windows 主目录的实例会一直占有它，直到该实例退出。

## 验证

安装的编译版主机支持 `--self-test`。通过 `WSLENV` 传递 `CODEX_MONITOR_HUD_HOME` 后启动自检；当存在近期用户 CLI 任务时，正常桥接会返回大于零的 `visible_tasks`。MCP `monitor_hud_status` 还应显示新鲜心跳、`default_cli: true` 以及 `active_tasks` 中的同一批任务。

这是由 Windows 托管的 WSL 桥接，不是 Linux GUI 构建。模糊/Acrylic、字体、音频、通知区控制和快捷方式仍由 Windows 提供。
