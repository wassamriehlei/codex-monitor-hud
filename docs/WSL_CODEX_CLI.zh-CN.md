# 用 Windows HUD 监控 WSL 中的 Codex CLI

HUD 仍是原生 Windows 应用。可选 Codex 插件可把 WSL 中运行的 Codex CLI 桥接到 Windows 进程，会话记录依然保留在 Linux 发行版内。

## 推荐配置：在设置中连接

打开“设置 → 监控来源”，启用“WSL 中的 Codex”，选择发行版后点击“检测发行版与主目录”。也可以手动填写 `\\wsl.localhost\Ubuntu\home\你的用户名`。

状态显示“连接正常”后，HUD 会自动重启并同时扫描 Windows 默认 Profile 与独立的 WSL Profile。两个来源可分别开关。路径下尚无 `.codex/sessions` 时，先在该发行版运行一次 Codex CLI，再重新检测。

旧版通过 `CODEX_MONITOR_HUD_HOME` 设置的路径会显示在新界面中，并在下次保存时迁移。开机启动也会同步保存当前 WSL 路径。

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

配置的主目录下应存在 `.codex/sessions`。WSL 是独立只读来源；HUD 不会修改该 Profile。

更新或重新安装插件后，需要新建一个 Codex 任务以加载新的 MCP 配置。仅监控会话时不要求 WSL 侧加载 MCP；WSL 侧 MCP 用于状态工具和通知。设置改变路径后会自动重启单一 HUD 实例。

## 验证

安装的编译版主机支持 `--self-test`。正常桥接会在存在近期任务时返回大于零的 `visible_tasks`。MCP `monitor_hud_status` 应显示新鲜心跳、`wsl: true`，并把 WSL 任务标为 `profile: "wsl"`。

这是由 Windows 托管的 WSL 桥接，不是 Linux GUI 构建。模糊/Acrylic、字体、音频、通知区控制和快捷方式仍由 Windows 提供。
