# Monitor a WSL Codex CLI from the Windows HUD

The HUD remains a native Windows application. Its optional Codex plugin can bridge a Codex CLI running inside WSL to that Windows process, while the session records stay inside the Linux distribution.

## WSL-side plugin configuration

Install the Windows HUD first. In the plugin source used by the WSL Codex CLI, set `.mcp.json` to the following shape and replace `WINDOWS_USER`, `DISTRO`, and `WSL_USER`:

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

`WSLENV` is required. WSL does not forward arbitrary Linux environment variables to a launched Windows executable; the `/w` entries explicitly carry these two values from WSL into `node.exe`, PowerShell, and the compiled HUD.

The configured home must contain `.codex/sessions`. The same override also derives the optional sibling `.codex-deepseek` profile. It does not change either profile.

After updating or reinstalling the plugin, start a new Codex task so the new MCP configuration is loaded. Stop an already-running HUD once before the first bridged launch; the application intentionally uses one desktop instance, so an earlier instance watching the native Windows home keeps ownership until it exits.

## Verification

The installed compiled host supports `--self-test`. Launch it with `CODEX_MONITOR_HUD_HOME` carried through `WSLENV`; a working bridge reports `visible_tasks` greater than zero while a recent user CLI task exists. The MCP `monitor_hud_status` result should then report a fresh heartbeat, `default_cli: true`, and the same tasks under `active_tasks`.

This is a Windows-hosted WSL bridge, not a Linux GUI build. Blur/Acrylic, fonts, audio, notification-area controls, and shortcuts are still provided by Windows.
